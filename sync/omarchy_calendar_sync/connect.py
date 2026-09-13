"""Connect a CalDAV account, without anyone having to be at a terminal.

The settings panel collects a URL, a username and a password and hands them
here over stdin. The interactive script next door collects the same three
things from prompts and hands them here too. One implementation, so what the
panel does and what the terminal does cannot drift apart -- and the panel is
not left reimplementing credential checks, file permissions and unit
installation in QML, where none of that belongs.

Nothing here is tied to one vendor. CalDAV is a standard, so the same path
reaches a company mail server, Nextcloud, Radicale, Fastmail, Zimbra and
iCloud.

The order matters and is deliberate: prove the credentials before writing
anything. A typo should leave no half-configured sync behind for someone to
debug a week later.
"""

import json
import os
import subprocess
from pathlib import Path

from . import config as config_module
from .caldav import CalDav, CalDavAuthError, CalDavError

# The sync directory of this checkout, which is where the units and the
# executable live. Resolved from this file so a hand-cloned repo anywhere on
# disk installs units that point back at itself rather than at the path the
# marketplace would have used.
SYNC_DIR = Path(__file__).resolve().parent.parent
SYNC_BIN = SYNC_DIR / "omarchy-calendar-sync"
UNIT_SOURCE = SYNC_DIR / "systemd"
UNIT_NAMES = ("omarchy-calendar-sync.service", "omarchy-calendar-sync.timer")
TIMER = "omarchy-calendar-sync.timer"

DEFAULT_UNIT_DIR = Path.home() / ".config" / "systemd" / "user"

# Stages, in the order they run. The panel shows a different sentence for
# each: "the server refused the password" and "the timer would not start"
# are not the same problem and must not read as though they were.
STAGE_INPUT = "input"
STAGE_CREDENTIALS = "credentials"
STAGE_PASSWORD = "password"
STAGE_CONFIG = "config"
STAGE_TIMER = "timer"
STAGE_SYNC = "sync"


class ConnectError(Exception):
    """A failure at one named stage of the connect."""

    def __init__(self, stage, message):
        super().__init__(message)
        self.stage = stage
        self.message = message


def connect(request, *, client_factory=CalDav, config_path=None, unit_dir=None,
            sync_dir=None, run_command=None, sync=None):
    """Verify, store and install. Returns the result dict the caller prints.

    Every collaborator is injectable because the interesting failures here are
    a refused password, a read-only config directory and a systemctl that is
    not there -- none of which a test can arrange with the real thing.
    """
    url = _required(request, "url", "a server URL is required")
    username = _required(request, "username", "a username is required")
    verify_tls = request.get("verifyTls", True) is not False

    config_path = Path(config_path) if config_path else config_module.CONFIG_PATH
    password_path = _password_path(request, config_path)
    password = _resolve_password(request, password_path)

    client = client_factory(url, username, password, verify_tls=verify_tls)
    calendars = _verified_calendars(client)

    # Only now is anything written. Password first, so the config never names
    # a file that does not exist yet.
    _write_password(password_path, password)
    _write_config(config_path, url, username, password_path, verify_tls)

    result = {
        "ok": True,
        "calendars": [
            {"name": calendar["name"], "color": calendar["color"]}
            for calendar in calendars
        ],
        "configPath": str(config_path),
        "passwordFile": str(password_path),
    }

    # The timer and the first sync are reported rather than raised on. The
    # account is connected at this point: a user whose systemd is unusual
    # should be told the sync is wired up but not scheduled, not told the
    # whole thing failed and left with a working config they think is broken.
    result["timer"] = _install_timer(
        unit_dir=unit_dir, sync_dir=sync_dir, run_command=run_command
    )
    result["firstSync"] = _first_sync(config_path, password, sync=sync)
    return result


def _required(request, key, message):
    value = str(request.get(key) or "").strip()
    if not value:
        raise ConnectError(STAGE_INPUT, message)
    return value


def _password_path(request, config_path):
    """Where the password goes: what was asked for, else what config already
    says, else the default beside the config."""
    asked = str(request.get("passwordFile") or "").strip()
    if asked:
        return Path(asked).expanduser()

    existing = _read_json(config_path).get("caldav") or {}
    from_config = str(existing.get("passwordFile") or "").strip()
    if from_config:
        return Path(from_config).expanduser()

    return Path(config_module.DEFAULTS["caldav"]["passwordFile"])


def _resolve_password(request, password_path):
    """An absent password means "keep the one already stored".

    The panel cannot show a password it never had, so it sends the field
    blank when the user only changed the URL. Treating blank as "erase the
    password" would break a working sync on an edit that never mentioned it.
    """
    password = request.get("password")
    if password:
        return str(password)

    try:
        stored = password_path.read_text().strip() if password_path.exists() else ""
    except OSError as error:
        raise ConnectError(STAGE_PASSWORD, f"cannot read {password_path}: {error}") from error

    if not stored:
        raise ConnectError(STAGE_INPUT, "a password is required")
    return stored


def _verified_calendars(client):
    try:
        calendars = client.calendars()
    except CalDavAuthError as error:
        raise ConnectError(STAGE_CREDENTIALS, str(error)) from error
    except CalDavError as error:
        raise ConnectError(STAGE_CREDENTIALS, str(error)) from error

    if not calendars:
        raise ConnectError(
            STAGE_CREDENTIALS,
            "connected, but the account has no calendars to read",
        )
    return calendars


def _write_password(path, password):
    """Written through a mode the rest of the machine cannot read.

    Created empty at 0600 before a byte goes in, so the password is never
    briefly on disk as world-readable.
    """
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        handle = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(handle, "w") as stream:
            stream.write(password.rstrip("\n") + "\n")
        os.chmod(str(path), 0o600)
    except OSError as error:
        raise ConnectError(STAGE_PASSWORD, f"cannot write {path}: {error}") from error


def _write_config(config_path, url, username, password_path, verify_tls):
    """Merge into whatever is already there rather than replacing it.

    A Google profile, a window, a calendar include list: none of that is this
    function's business, and all of it survives.
    """
    document = _read_json(config_path)
    document["source"] = config_module.SOURCE_CALDAV
    caldav = dict(document.get("caldav") or {})
    caldav.update({
        "url": url,
        "username": username,
        "passwordFile": str(password_path),
        "verifyTls": bool(verify_tls),
    })
    document["caldav"] = caldav

    try:
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(document, indent=2) + "\n")
    except OSError as error:
        raise ConnectError(STAGE_CONFIG, f"cannot write {config_path}: {error}") from error


def _read_json(path):
    """Existing config, or an empty document. A corrupt file is not a reason
    to refuse the connect -- it is a reason to replace it."""
    try:
        loaded = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}
    return loaded if isinstance(loaded, dict) else {}


def _install_timer(*, unit_dir=None, sync_dir=None, run_command=None):
    """Copy the units, point them at this checkout, enable the timer.

    Returns a short status string rather than raising: see connect().
    """
    unit_dir = Path(unit_dir) if unit_dir else DEFAULT_UNIT_DIR
    sync_dir = Path(sync_dir) if sync_dir else SYNC_DIR
    run_command = run_command or _run

    try:
        unit_dir.mkdir(parents=True, exist_ok=True)
        for name in UNIT_NAMES:
            text = (sync_dir / "systemd" / name).read_text()
            if name.endswith(".service"):
                # The shipped unit assumes the marketplace install path. A
                # checkout can live anywhere, so the real path is written in.
                text = "\n".join(
                    "ExecStart=" + str(sync_dir / "omarchy-calendar-sync")
                    if line.startswith("ExecStart=") else line
                    for line in text.splitlines()
                ) + "\n"
            (unit_dir / name).write_text(text)
    except OSError as error:
        return f"not installed: {error}"

    failed = run_command(["systemctl", "--user", "daemon-reload"])
    if failed:
        return f"not enabled: {failed}"
    failed = run_command(["systemctl", "--user", "enable", "--now", TIMER])
    if failed:
        return f"not enabled: {failed}"
    return "enabled"


def _run(command):
    """Run a command, returning None on success or a one-line reason."""
    try:
        completed = subprocess.run(
            command, capture_output=True, text=True, check=False, timeout=30
        )
    except (OSError, subprocess.SubprocessError) as error:
        return str(error)

    if completed.returncode == 0:
        return None
    detail = (completed.stderr or completed.stdout or "").strip().splitlines()
    return detail[-1] if detail else f"exit {completed.returncode}"


def _first_sync(config_path, password, *, sync=None):
    """Run one sync now, so the calendar has events before the timer's first
    tick five minutes from now.

    The password goes through the environment rather than being re-read from
    disk, which keeps this working when the file is a password-manager stub
    that only the service environment resolves.
    """
    sync = sync or _sync_once
    previous = os.environ.get("OMARCHY_CALDAV_PASSWORD")
    os.environ["OMARCHY_CALDAV_PASSWORD"] = password
    try:
        code = sync(config_path)
    finally:
        if previous is None:
            os.environ.pop("OMARCHY_CALDAV_PASSWORD", None)
        else:
            os.environ["OMARCHY_CALDAV_PASSWORD"] = previous

    return "ok" if code == 0 else f"failed (exit {code})"


def _sync_once(config_path):
    from .cli import main

    return main(["--config", str(config_path)])


def main(argv=None, stdin=None, stdout=None, stderr=None):
    """Read one JSON request on stdin, write one JSON result on stdout.

    One object in, one object out, and never a password on the command line:
    an argument is visible in `ps` to every process on the machine, and this
    is called from a status bar popup where the user is watching.
    """
    import sys

    stdin = stdin if stdin is not None else sys.stdin
    stdout = stdout if stdout is not None else sys.stdout
    stderr = stderr if stderr is not None else sys.stderr

    try:
        request = json.loads(_read_request(stdin) or "{}")
    except ValueError as error:
        _emit(stdout, {"ok": False, "stage": STAGE_INPUT, "error": f"unreadable request: {error}"})
        return 1

    if not isinstance(request, dict):
        _emit(stdout, {"ok": False, "stage": STAGE_INPUT, "error": "request must be a JSON object"})
        return 1

    try:
        result = connect(request)
    except ConnectError as error:
        _emit(stdout, {"ok": False, "stage": error.stage, "error": error.message})
        return 1
    except Exception as error:  # noqa: BLE001 - the panel gets a sentence, not a traceback
        print(f"connect failed: {error!r}", file=stderr)
        _emit(stdout, {"ok": False, "stage": "unexpected", "error": str(error) or error.__class__.__name__})
        return 1

    _emit(stdout, result)
    return 0


def _read_request(stdin):
    """One line is the whole request, so a caller that holds stdin open still
    gets an answer.

    The settings panel writes a single line into a pipe it keeps open for the
    life of the process; waiting for EOF there would hang until the user gave
    up. A file redirected in is usually one line too, but an indented one is
    read to the end rather than rejected on its first brace.
    """
    first = stdin.readline()
    if not first.strip():
        return first

    try:
        json.loads(first)
    except ValueError:
        return first + stdin.read()
    return first


def _emit(stream, document):
    json.dump(document, stream, ensure_ascii=False)
    stream.write("\n")
    stream.flush()
