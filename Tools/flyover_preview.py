"""Validation and local HTTP serving for generated Flyover atlases."""

from __future__ import annotations

import argparse
import ipaddress
import json
import signal
import socket
import sys
import threading
from contextlib import contextmanager
from dataclasses import dataclass
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from typing import Callable, Iterable, Iterator, TextIO
from urllib.parse import unquote, urlsplit


MARKER_CONTENT = "schemaVersion=1"
REQUIRED_FILES = (
    "index.html",
    "manifest.json",
    "manifest.js",
    "assets/app.js",
    "assets/styles.css",
)


class FlyoverArtifactError(ValueError):
    """A generated atlas is incomplete or unsafe to serve."""


@dataclass(frozen=True)
class FlyoverArtifact:
    root: Path
    allowed_paths: frozenset[str]


def validate_artifact(
    directory: Path,
    *,
    require_marker: bool = True,
) -> FlyoverArtifact:
    """Validate a generated atlas and return its HTTP allowlist."""
    root = directory
    if root.is_symlink():
        raise FlyoverArtifactError(f"the atlas directory is a symbolic link: {root}")
    if not root.exists():
        raise FlyoverArtifactError(
            f"no generated atlas exists at {root}. Run ./flyover export first."
        )
    if not root.is_dir():
        raise FlyoverArtifactError(f"the atlas path is not a directory: {root}")

    symbolic_link = next((path for path in root.rglob("*") if path.is_symlink()), None)
    if symbolic_link is not None:
        relative = symbolic_link.relative_to(root)
        raise FlyoverArtifactError(f"the atlas contains a symbolic link: {relative}")

    marker = root / ".flyover-generated"
    if require_marker:
        if not marker.is_file():
            raise FlyoverArtifactError(
                f"the directory is not a generated Flyover atlas: {root}"
            )
        try:
            marker_content = marker.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError) as error:
            raise FlyoverArtifactError(f"could not read {marker}: {error}") from error
        if marker_content != MARKER_CONTENT:
            raise FlyoverArtifactError(
                f"the generated marker is unsupported: {marker_content or 'empty'}"
            )

    for relative in REQUIRED_FILES:
        path = root / relative
        if not path.is_file():
            raise FlyoverArtifactError(f"the generated atlas is missing {relative}")

    manifest_path = root / "manifest.json"
    try:
        manifest_data = manifest_path.read_bytes()
        manifest = json.loads(manifest_data)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise FlyoverArtifactError(f"could not read manifest.json: {error}") from error
    if not isinstance(manifest, dict):
        raise FlyoverArtifactError("manifest.json is not a JSON object")
    if (
        type(manifest.get("schemaVersion")) is not int
        or manifest["schemaVersion"] != 1
    ):
        raise FlyoverArtifactError("manifest.json does not use schemaVersion 1")

    manifest_script_path = root / "manifest.js"
    try:
        manifest_script = manifest_script_path.read_bytes()
    except OSError as error:
        raise FlyoverArtifactError(f"could not read manifest.js: {error}") from error
    expected_script = b"window.FLYOVER_MANIFEST = " + manifest_data + b";\n"
    if manifest_script != expected_script:
        raise FlyoverArtifactError("manifest.js does not match manifest.json")

    images = manifest.get("images")
    if not isinstance(images, list):
        raise FlyoverArtifactError("manifest.json has no image list")

    image_paths: list[str] = []
    for image in images:
        if not isinstance(image, dict):
            raise FlyoverArtifactError("manifest.json contains an invalid image record")
        relative_value = image.get("relativePath")
        if not isinstance(relative_value, str):
            raise FlyoverArtifactError("manifest.json contains an invalid image path")
        relative = _safe_image_path(relative_value)
        path = root.joinpath(*relative.parts)
        if not path.is_file():
            raise FlyoverArtifactError(f"the manifest image is missing: {relative}")
        image_paths.append(relative.as_posix())

    if len(set(image_paths)) != len(image_paths):
        raise FlyoverArtifactError("manifest.json contains a duplicate image path")

    images_directory = root / "images"
    if images_directory.is_dir():
        actual_paths = {
            path.relative_to(root).as_posix()
            for path in images_directory.rglob("*.png")
            if path.is_file()
        }
    else:
        actual_paths = set()
    declared_paths = set(image_paths)
    if actual_paths != declared_paths:
        raise FlyoverArtifactError(
            "the image files do not match the manifest "
            f"({len(declared_paths)} declared, {len(actual_paths)} found)"
        )

    return FlyoverArtifact(
        root=root,
        allowed_paths=frozenset((*REQUIRED_FILES, *image_paths)),
    )


def _safe_image_path(value: str) -> PurePosixPath:
    relative = PurePosixPath(value)
    if (
        not value
        or "\\" in value
        or relative.is_absolute()
        or ".." in relative.parts
        or relative.parts[:1] != ("images",)
        or relative.suffix.lower() != ".png"
    ):
        raise FlyoverArtifactError(f"the manifest contains an unsafe image path: {value}")
    return relative


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
        directory: str,
        allowed_paths: frozenset[str],
        **kwargs: object,
    ) -> None:
        self.allowed_paths = allowed_paths
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        if not self._request_is_allowed():
            self.send_error(404)
            return
        super().do_GET()

    def do_HEAD(self) -> None:  # noqa: N802 - stdlib handler API
        if not self._request_is_allowed():
            self.send_error(404)
            return
        super().do_HEAD()

    def list_directory(self, path: str) -> None:
        self.send_error(404)
        return None

    def log_message(self, message: str, *args: object) -> None:
        """Keep untrusted HTTP request data out of the terminal."""

    def _request_is_allowed(self) -> bool:
        try:
            target = urlsplit(self.path)
        except ValueError:
            return False
        if target.scheme or target.netloc or target.fragment:
            return False
        raw_path = unquote(target.path)
        if raw_path == "/":
            return "index.html" in self.allowed_paths
        if not raw_path.startswith("/") or raw_path.endswith("/"):
            return False
        segments = raw_path[1:].split("/")
        if any(segment in ("", ".", "..") for segment in segments):
            return False
        relative = "/".join(segments)
        return relative in self.allowed_paths


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
    handler = partial(
        FlyoverRequestHandler,
        directory=str(artifact.root),
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
