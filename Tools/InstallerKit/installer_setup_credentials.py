"""Resolve local maintenance credentials without storing or displaying secrets."""

import getpass
import json
import os
from pathlib import Path
import sys
import warnings


def signing_environment(environment=None, home=None, interactive=None, prompt=getpass.getpass):
    values = dict(os.environ if environment is None else environment)
    default_key = (Path.home() if home is None else home) / '.config/stuff/signing/app-store-connect.json'
    key = Path(values.get('INSTALLER_API_KEY_PATH') or default_key).expanduser().resolve()
    try:
        data = json.loads(key.read_text())
        valid = isinstance(data, dict) and all(isinstance(data.get(name), str) and data[name]
                                               for name in ('key_id', 'issuer_id', 'key'))
    except (OSError, ValueError):
        valid = False
    if not valid:
        raise ValueError('Set INSTALLER_API_KEY_PATH to a readable Fastlane Team API-key JSON file with key_id, issuer_id, and key.')
    values['INSTALLER_API_KEY_PATH'] = str(key)
    if not values.get('MATCH_PASSWORD'):
        if not (sys.stdin.isatty() if interactive is None else interactive):
            raise ValueError('MATCH_PASSWORD is required. Run setup in a terminal for a hidden prompt, or supply it in the environment.')
        # Never let getpass fall back to an echoed password.
        with warnings.catch_warnings():
            warnings.simplefilter('error', getpass.GetPassWarning)
            try:
                password = prompt('Existing signing repository password: ')
            except (EOFError, getpass.GetPassWarning) as error:
                raise ValueError('Cannot read the password without echo. Supply MATCH_PASSWORD securely and rerun setup.') from error
        if not password:
            raise ValueError('The signing repository password cannot be empty')
        values['MATCH_PASSWORD'] = password
    return values
