"""Project-scoped preview policy around Astro's own background server lifecycle."""

import argparse
from contextlib import contextmanager
from dataclasses import dataclass, replace
import fcntl
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
from urllib.parse import urlsplit

from Tools.astro_site import SOURCE_ROOT, astro_command, resolve_mise
from Tools.repository import repository_root


@dataclass(frozen=True)
class Server:
    pid: int
    port: int
    path: str
    background: bool
    record: dict


def project_directory(value):
    project = Path(value).expanduser().resolve(strict=True)
    if not (project / "astro.config.mjs").is_file():
        raise ValueError(f"Expected astro.config.mjs in {project}")
    if (project / ".astro").is_symlink():
        raise ValueError("Keep the project's .astro directory local, not symlinked.")
    return project


def read_server(project):
    """Only absence means no record; inspection/parse errors must stay visible."""
    path = project / ".astro/dev.json"
    try:
        if path.is_symlink():
            raise ValueError(f"Refusing a symlinked server record: {path}")
        data = json.loads(path.read_text())
    except FileNotFoundError:
        return None
    if not isinstance(data, dict):
        raise ValueError(f"Invalid Astro server record: {path}")
    pid, port = data.get("pid"), data.get("port")
    if (
        type(pid) is not int
        or pid <= 1
        or type(port) is not int
        or not 1 <= port <= 65535
        or type(data.get("background")) is not bool
        or not isinstance(data.get("startedAt"), str)
    ):
        raise ValueError(f"Invalid Astro server record: {path}")
    url = local_url(data.get("url"), port)
    return Server(pid, port, url.path or "/", data["background"], data)


def local_url(value, port):
    if not isinstance(value, str):
        raise ValueError("Invalid local URL in Astro server record.")
    url = urlsplit(value)
    if (
        url.scheme != "http"
        or url.hostname not in ("localhost", "127.0.0.1", "::1", "0.0.0.0")
        or url.username is not None
        or url.password is not None
        or (url.port if url.port is not None else 80) != port
        or url.query
        or url.fragment
    ):
        raise ValueError("Invalid local URL in Astro server record.")
    return url


def captured(command):
    result = subprocess.run(command, text=True, capture_output=True, timeout=5)
    if result.returncode:
        raise ValueError(
            f"Cannot inspect server: {result.stderr.strip() or command[0]}"
        )
    return result.stdout.strip()


def process_identity(pid):
    """Read exact argv on Linux, command text plus cwd on macOS; fail closed."""
    state = captured(["/bin/ps", "-ww", "-p", str(pid), "-o", "stat="])
    if state.startswith(("Z", "X")):
        return None
    if sys.platform == "linux":
        process = Path("/proc") / str(pid)
        return (
            (process / "cmdline").read_bytes().decode().rstrip("\0").split("\0"),
            (process / "cwd").resolve(strict=True),
        )
    if sys.platform == "darwin":
        command = captured(["/bin/ps", "-ww", "-p", str(pid), "-o", "command="])
        executable = captured(["/bin/ps", "-ww", "-p", str(pid), "-o", "comm="])
        cwd = captured(["/usr/sbin/lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"])
        paths = [line[1:] for line in cwd.splitlines() if line.startswith("n")]
        if len(paths) != 1 or not command.startswith(executable + " "):
            raise ValueError(f"Cannot inspect server process {pid}")
        return (executable, command[len(executable) + 1 :]), Path(paths[0]).resolve()
    raise ValueError("Prototype server management supports macOS and Linux.")


def owns_process(project, server):
    """A live PID alone is insufficient: require Astro dev and this project root."""
    try:
        os.kill(server.pid, 0)
    except ProcessLookupError:
        return False
    # PermissionError deliberately propagates: an inaccessible process is not stale.
    try:
        process = process_identity(server.pid)
    except (OSError, ValueError):
        # A process can exit between kill(0) and inspection; only ESRCH proves
        # absence. Permission and command-inspection failures remain errors.
        try:
            os.kill(server.pid, 0)
        except ProcessLookupError:
            return False
        raise
    if process is None:
        return False
    identity, cwd = process
    roots = {SOURCE_ROOT}
    try:
        roots.add(repository_root(project / "astro.config.mjs"))
    except FileNotFoundError:
        # A standalone project can still use this checkout's Astro executable.
        pass
    entries = {
        str((root / "node_modules" / entry).resolve())
        for root in roots
        for entry in (".bin/astro", "astro/bin/astro.mjs")
    }
    entries.update(str(root / "node_modules/.bin/astro") for root in roots)
    if sys.platform == "linux":
        argv = identity
        matches = (
            len(argv) >= 5
            and Path(argv[0]).name == "node"
            and argv[1] in entries
            and argv[2] == "dev"
            and argv.count("--root") == 1
            and argv.index("--root") + 1 < len(argv)
            and argv[argv.index("--root") + 1] == str(project)
        )
    else:
        executable, arguments = identity
        # ps flattens argv on macOS. Native background Astro puts --root after
        # port/host/config and only --json after it in commands supported here.
        matches = Path(executable).name == "node" and any(
            arguments.startswith(entry + " dev ")
            and re.search(
                r" --root " + re.escape(str(project)) + r"(?: --json)?$", arguments
            )
            for entry in entries
        )
    if cwd != project or not matches or not server.background:
        raise ValueError(
            f"PID {server.pid} is not an owned background Astro server for {project}; "
            "leaving it and its record untouched."
        )
    return True


def live_server(project):
    server = read_server(project)
    return server if server and owns_process(project, server) else None


def current_addresses():
    """Discover current IPv4 interfaces rather than Astro's cached startup URLs."""
    command = [
        resolve_mise(),
        "exec",
        "node",
        "--",
        "node",
        "-e",
        "process.stdout.write(JSON.stringify(require('node:os').networkInterfaces()))",
    ]
    result = subprocess.run(
        command, cwd=SOURCE_ROOT, text=True, capture_output=True, timeout=10
    )
    if result.returncode:
        raise ValueError(f"Cannot discover network interfaces: {result.stderr.strip()}")
    addresses = []
    for name, interfaces in json.loads(result.stdout).items():
        for interface in interfaces or []:
            if interface["family"] != "IPv4" or interface["internal"]:
                continue
            address = str(ipaddress.IPv4Address(interface["address"]))
            if (name, address) not in addresses:
                addresses.append((name, address))
    return addresses


def responds(host, server):
    # Direct connections bypass proxy variables and never follow redirects.
    connection = http.client.HTTPConnection(host, server.port, timeout=2)
    try:
        connection.request("GET", server.path)
        response = connection.getresponse()
        return 200 <= response.status < 300
    except (OSError, http.client.HTTPException):
        return False
    finally:
        connection.close()


def report(project, server, *, path="/", lan_required=False, wait_seconds=0):
    server = replace(server, path=path)
    deadline = time.monotonic() + wait_seconds
    while not responds("127.0.0.1", server):
        if time.monotonic() >= deadline:
            raise ValueError(
                f"PID {server.pid} has no successful HTTP response at {server.path} on port {server.port}. "
                f"For a non-root route, pass --path /your-route/. Inspect ./prototype logs {project}"
            )
        time.sleep(0.2)
    print(
        f"Project: {project}\nPID: {server.pid}\nLocal: http://localhost:{server.port}{server.path}"
    )
    reachable = []
    for name, address in current_addresses():
        if responds(address, server):
            reachable.append(address)
            print(f"Network ({name}): http://{address}:{server.port}{server.path}")
    if not reachable:
        print("Network: no current IPv4 interface returned a successful HTTP response.")
        if lan_required:
            raise ValueError(
                "LAN preview is unavailable. If this server was started without --lan, "
                "stop it and start again with --lan."
            )
    print(f"Log: {project / '.astro/dev.log'}")


@contextmanager
def lifecycle_lock(project):
    """Serialize wrapper operations; Astro continues to own the PID and daemon."""
    (project / ".astro").mkdir(exist_ok=True)
    with (project / ".astro/prototype-command.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError(
                "Another prototype start/stop is in progress for this project."
            ) from error
        yield


def run_astro(project, *arguments):
    command = astro_command(project, project, *arguments)
    result = subprocess.run(
        command, cwd=SOURCE_ROOT, env={**os.environ, "ASTRO_TELEMETRY_DISABLED": "1"}
    )
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


def start(project, port, lan, *, path="/"):
    # Resolve dependencies before writing any state; native Astro owns readiness
    # of its daemon (30s), then we verify the served route with a bounded probe.
    astro_command(project, project, "dev")
    live_server(project)
    with lifecycle_lock(project):
        server = live_server(project)
        if server:
            if port is not None and port != server.port:
                raise ValueError(
                    f"Already running on port {server.port}; stop it before changing ports."
                )
            print("Reusing the existing server.")
        else:
            port = port or 4321
            host = "0.0.0.0" if lan else "127.0.0.1"
            with socket.socket() as probe:
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                try:
                    probe.bind((host, port))
                except OSError as error:
                    raise ValueError(
                        f"Port {port} is unavailable; choose another --port. {error}"
                    ) from error
            result = run_astro(
                project, "dev", "--host", host, "--port", str(port), "--background"
            )
            if result:
                return result
            server = live_server(project)
            if server is None:
                raise ValueError(
                    "Astro exited without a live server record. Inspect prototype logs."
                )
            if server.port != port:
                raise ValueError(
                    f"Astro selected port {server.port} instead of {port}; inspect status or stop it."
                )
        report(project, server, path=path, lan_required=lan, wait_seconds=10)
    return 0


def stop(project):
    server = live_server(project)
    if server is None:
        print("No prototype server is running.")
        return 0
    astro_command(project, project, "dev", "stop")
    with lifecycle_lock(project):
        # Re-read after acquiring the lock; never act on a superseded record.
        current = live_server(project)
        if current is None:
            print("No prototype server is running.")
            return 0
        if current != server:
            raise ValueError("Server changed during inspection; retry stop.")
        result = run_astro(project, "dev", "stop")
        if result == 0 and owns_process(project, current):
            raise ValueError(f"Astro did not stop PID {current.pid}.")
        return result


def port_number(value):
    port = int(value)
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("port must be between 1 and 65535")
    return port


def preview_path(value):
    url = urlsplit(value)
    if (
        not value.startswith("/")
        or value.startswith("//")
        or url.query
        or url.fragment
        or not value.isascii()
        or re.search(r"[\x00-\x20\x7f]", value)
    ):
        raise argparse.ArgumentTypeError(
            "path must be an absolute URL path, percent-encoded, without query or fragment"
        )
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Manage a project-scoped Astro prototype with the repository's pinned tools.",
        epilog="PROJECT is relative to your current directory (or absolute). Requires astro.config.mjs. "
        "Start leaves Astro running in the background. --lan allows same-network device review.",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("start", "status", "stop", "logs", "check", "build"):
        command = commands.add_parser(name)
        command.add_argument("project", metavar="PROJECT")
        if name in ("start", "status"):
            command.add_argument(
                "--path",
                type=preview_path,
                default="/",
                help="HTTP route to check and share; use for Astro base paths (default: /)",
            )
        if name == "start":
            command.add_argument(
                "--lan", action="store_true", help="listen on all IPv4 interfaces"
            )
            command.add_argument(
                "--port",
                type=port_number,
                help="default: reuse existing server, otherwise 4321",
            )
    args = parser.parse_args(argv)
    try:
        project = project_directory(args.project)
        if args.command == "start":
            return start(project, args.port, args.lan, path=args.path)
        if args.command == "stop":
            return stop(project)
        if args.command == "status":
            server = live_server(project)
            if server is None:
                print("No prototype server is running (any stale record is unchanged).")
                return 1
            report(project, server, path=args.path)
            return 0
        if args.command == "logs":
            # Read Astro's own log even after startup fails; status must not erase
            # its stale record, and log inspection needs neither Node nor mise.
            print((project / ".astro/dev.log").read_text(), end="")
            return 0
        return run_astro(project, args.command)
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"prototype: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
