"""Local HTTP serving for validated Flyover atlases."""

from __future__ import annotations

import argparse
import ipaddress
import os
import signal
import socket
import stat
import sys
import threading
from contextlib import contextmanager
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Callable, Iterable, Iterator, Optional, TextIO
from urllib.parse import unquote, urlsplit

try:
    from Tools.flyover_manifest import (
        FlyoverArtifact,
        FlyoverArtifactError,
        validate_artifact,
    )
except ModuleNotFoundError as error:
    if error.name != "Tools":
        raise
    from flyover_manifest import (
        FlyoverArtifact,
        FlyoverArtifactError,
        validate_artifact,
    )


def usable_ipv4_addresses(candidates: Iterable[str]) -> tuple[str, ...]:
    """Return deterministic non-loopback IPv4 addresses."""
    addresses: set[ipaddress.IPv4Address] = set()
    for candidate in candidates:
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if not isinstance(address, ipaddress.IPv4Address):
            continue
        if address.is_unspecified or address.is_loopback or address.is_multicast:
            continue
        addresses.add(address)
    return tuple(str(address) for address in sorted(addresses))


def discover_network_addresses() -> tuple[str, ...]:
    """Discover IPv4 addresses that can identify this host on a local network."""
    candidates: list[str] = []
    try:
        candidates.extend(
            item[4][0]
            for item in socket.getaddrinfo(
                socket.gethostname(),
                None,
                family=socket.AF_INET,
                type=socket.SOCK_STREAM,
            )
        )
    except OSError:
        pass

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("192.0.2.1", 9))
            candidates.append(probe.getsockname()[0])
    except OSError:
        pass
    return usable_ipv4_addresses(candidates)


class FlyoverRequestHandler(SimpleHTTPRequestHandler):
    """Serve only files declared by a validated Flyover artifact."""

    def __init__(
        self,
        *args: object,
        root_descriptor: int,
        allowed_paths: frozenset[str],
        **kwargs: object,
    ) -> None:
        self.root_descriptor = os.dup(root_descriptor)
        self.allowed_paths = allowed_paths
        try:
            super().__init__(*args, directory="/", **kwargs)
        finally:
            os.close(self.root_descriptor)

    def send_head(self) -> Optional[BinaryIO]:
        relative = self._allowed_relative_path()
        if relative is None:
            self.send_error(404)
            return None
        try:
            file = _open_file_beneath(self.root_descriptor, relative)
        except OSError:
            self.send_error(404)
            return None

        try:
            status = os.fstat(file.fileno())
            self.send_response(200)
            self.send_header("Content-type", self.guess_type(relative))
            self.send_header("Content-Length", str(status.st_size))
            self.send_header("Last-Modified", self.date_time_string(status.st_mtime))
            self.end_headers()
            return file
        except BaseException:
            file.close()
            raise

    def list_directory(self, path: str) -> None:
        self.send_error(404)
        return None

    def log_message(self, message: str, *args: object) -> None:
        """Keep untrusted HTTP request data out of the terminal."""

    def _allowed_relative_path(self) -> Optional[str]:
        try:
            target = urlsplit(self.path)
        except ValueError:
            return None
        if target.scheme or target.netloc or target.fragment:
            return None
        raw_path = unquote(target.path)
        if raw_path == "/":
            return "index.html" if "index.html" in self.allowed_paths else None
        if not raw_path.startswith("/") or raw_path.endswith("/"):
            return None
        segments = raw_path[1:].split("/")
        if any(segment in ("", ".", "..") for segment in segments):
            return None
        relative = "/".join(segments)
        return relative if relative in self.allowed_paths else None


def _open_file_beneath(root_descriptor: int, relative: str) -> BinaryIO:
    """Open one allowlisted regular file without following symbolic links."""
    flags = os.O_RDONLY | os.O_NOFOLLOW
    directory_flags = flags | os.O_DIRECTORY
    current_descriptor = os.dup(root_descriptor)
    file_descriptor: Optional[int] = None
    try:
        parts = PurePosixPath(relative).parts
        for part in parts[:-1]:
            next_descriptor = os.open(
                part,
                directory_flags,
                dir_fd=current_descriptor,
            )
            os.close(current_descriptor)
            current_descriptor = next_descriptor
        file_descriptor = os.open(parts[-1], flags, dir_fd=current_descriptor)
        if not stat.S_ISREG(os.fstat(file_descriptor).st_mode):
            raise OSError("the request target is not a regular file")
        file = os.fdopen(file_descriptor, "rb")
        file_descriptor = None
        return file
    finally:
        if file_descriptor is not None:
            os.close(file_descriptor)
        os.close(current_descriptor)


@contextmanager
def _open_artifact_root(artifact: FlyoverArtifact) -> Iterator[int]:
    """Pin the validated atlas directory for the server lifetime."""
    try:
        descriptor = os.open(
            artifact.root,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
    except OSError as error:
        raise FlyoverArtifactError(
            f"could not open the validated atlas directory {artifact.root}: {error}"
        ) from error
    try:
        status = os.fstat(descriptor)
        if (status.st_dev, status.st_ino) != (artifact.root_device, artifact.root_inode):
            raise FlyoverArtifactError("the atlas directory changed during server startup")
        yield descriptor
    finally:
        os.close(descriptor)


ServerFactory = Callable[..., ThreadingHTTPServer]


@contextmanager
def _serve_until_interrupted(server: ThreadingHTTPServer) -> Iterator[None]:
    """Serve on a worker until the main process receives Ctrl-C."""
    stop_requested = threading.Event()
    serving_finished = threading.Event()
    serving_errors: list[BaseException] = []

    def request_shutdown(_signal_number: int, _frame: object) -> None:
        stop_requested.set()

    def serve_forever() -> None:
        try:
            server.serve_forever()
        except BaseException as error:
            serving_errors.append(error)
        finally:
            serving_finished.set()
            stop_requested.set()

    server_thread = threading.Thread(
        target=serve_forever,
        name="flyover-preview-server",
        daemon=True,
    )
    previous_handler = signal.signal(signal.SIGINT, request_shutdown)
    thread_started = False
    try:
        server_thread.start()
        thread_started = True
        yield
        stop_requested.wait()
    finally:
        try:
            if thread_started and not serving_finished.is_set():
                server.shutdown()
            if thread_started:
                server_thread.join()
        finally:
            signal.signal(signal.SIGINT, previous_handler)

    if serving_errors:
        raise serving_errors[0]


def serve(
    directory: Path,
    *,
    lan: bool,
    port: int,
    output: TextIO = sys.stdout,
    server_factory: ServerFactory = ThreadingHTTPServer,
    address_provider: Callable[[], tuple[str, ...]] = discover_network_addresses,
) -> None:
    artifact = validate_artifact(directory)
    host = "0.0.0.0" if lan else "127.0.0.1"
    with _open_artifact_root(artifact) as root_descriptor:
        handler = partial(
            FlyoverRequestHandler,
            root_descriptor=root_descriptor,
            allowed_paths=artifact.allowed_paths,
        )
        try:
            server = server_factory((host, port), handler)
        except OSError as error:
            raise FlyoverArtifactError(
                f"could not start the preview server on {host}:{port}: {error}"
            ) from error

        with server, _serve_until_interrupted(server):
            selected_port = int(server.server_address[1])
            print(f"Flyover preview: {artifact.root}", file=output)
            print(f"Local:   http://127.0.0.1:{selected_port}/", file=output)
            if lan:
                addresses = address_provider()
                for address in addresses:
                    print(f"Network: http://{address}:{selected_port}/", file=output)
                if not addresses:
                    print(
                        "Network: bound to all interfaces, but no LAN address was found.",
                        file=output,
                    )
                print("Warning: LAN preview has no authentication or TLS.", file=output)
            print("Press Ctrl-C to stop.", file=output, flush=True)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(add_help=False)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", add_help=False)
    validate.add_argument("directory", type=Path)
    validate.add_argument("--without-marker", action="store_true")

    preview = subparsers.add_parser("serve", add_help=False)
    preview.add_argument("directory", type=Path)
    preview.add_argument("--port", type=int, required=True)
    preview.add_argument("--lan", action="store_true")
    return parser


def main(arguments: list[str] | None = None) -> int:
    try:
        options = _parser().parse_args(arguments)
        if options.command == "validate":
            validate_artifact(
                options.directory,
                require_marker=not options.without_marker,
            )
        elif options.command == "serve":
            serve(options.directory, lan=options.lan, port=options.port)
        return 0
    except FlyoverArtifactError as error:
        print(f"flyover: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
