"""Public Flyover command dispatch; policy lives in the imported owners."""

import argparse
from contextlib import contextmanager
import os
import signal
import subprocess
import sys

from Tools.flyover_export import ExportRequest, export_atlas
from Tools.flyover_apps import load_app
from Tools.flyover_publication import resolve_destination
from Tools.repository import repository_root


DEFAULT_OUTPUT = '.build/flyover/where'
DEFAULT_PROFILES = ('phone-light', 'phone-dark')
PROFILES = (*DEFAULT_PROFILES, 'tablet-light', 'phone-landscape', 'phone-small',
            'phone-xxxl', 'phone-ax3', 'phone-contrast', 'phone-rtl', 'phone-bold',
            'phone-voiceover')


class CommandParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, f'flyover: {message}\n')


def profile(value: str) -> str:
    if value not in PROFILES:
        raise argparse.ArgumentTypeError(f"unknown profile '{value}'")
    return value


def port(value: str) -> int:
    if not value.isascii() or not value.isdecimal() or not 0 <= int(value) <= 65535:
        raise argparse.ArgumentTypeError('--port must be a number from 0 through 65535')
    return int(value)


def parser() -> argparse.ArgumentParser:
    result = CommandParser(
        prog='./flyover', description='Export or preview the Flyover catalog.',
        epilog='./flyover export | ./flyover preview | ./flyover dev', allow_abbrev=False,
    )
    commands = result.add_subparsers(dest='command', required=True)
    export = commands.add_parser('export', allow_abbrev=False,
                                 formatter_class=argparse.RawTextHelpFormatter,
                                 epilog='Profiles: ' + ', '.join(PROFILES))
    export.add_argument('--app', default='where', help='Registered app ID (default: %(default)s)')
    export.add_argument('--output', help='Generated directory (default: .build/flyover/<app>)')
    export.add_argument('--profile', action='append', type=profile,
                        help='Repeat to add profiles; the defaults are phone-light and phone-dark.')
    for name in ('preview', 'dev'):
        preview = commands.add_parser(name, allow_abbrev=False,
                                      epilog='LAN preview has no authentication or TLS. Press Ctrl-C to stop.')
        preview.add_argument('--output', default=DEFAULT_OUTPUT)
        preview.add_argument('--port', type=port, default=0)
        preview.add_argument('--lan', action='store_true')
    return result


class Interrupted(BaseException):
    def __init__(self, number: int):
        self.number = number
        super().__init__(f'interrupted by signal {number}')


@contextmanager
def interruption_handling():
    def interrupt(number, _frame):
        # Let recovery finish even if the caller repeats Ctrl-C.
        for item in (signal.SIGINT, signal.SIGTERM):
            signal.signal(item, signal.SIG_IGN)
        raise Interrupted(number)

    previous = {number: signal.signal(number, interrupt)
                for number in (signal.SIGINT, signal.SIGTERM)}
    try:
        yield
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)


def main(arguments=None) -> int:
    options = parser().parse_args(arguments)
    workspace = repository_root(__file__)
    try:
        # The launcher selects this checkout's modules before restoring the caller's cwd.
        caller = os.environ.pop('FLYOVER_CALLER_DIRECTORY', None)
        if caller is not None:
            os.chdir(caller)
        if options.command == 'export':
            load_app(options.app)
            output = options.output or f'.build/flyover/{options.app}'
        else:
            output = options.output
        destination = resolve_destination(output, workspace,
                                          action='replace' if options.command == 'export' else 'serve')
        if options.command == 'export':
            profiles = tuple(dict.fromkeys(options.profile or DEFAULT_PROFILES))
            with interruption_handling():
                export_atlas(ExportRequest(destination, profiles, options.app), workspace)
            return 0
        # Retain the public preview process seam and Astro's own signal lifecycle.
        os.chdir(workspace)
        argv = [os.environ.get('FLYOVER_PREVIEW_PYTHON', sys.executable),
                '-m', 'Tools.flyover_site', options.command, str(destination),
                '--port', str(options.port)]
        if options.lan:
            argv.append('--lan')
        os.execvpe(argv[0], argv, {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
    except Interrupted as error:
        return 128 + error.number
    except subprocess.CalledProcessError as error:
        return error.returncode if error.returncode >= 0 else 128 - error.returncode
    except (OSError, ValueError) as error:
        print(f'flyover: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
