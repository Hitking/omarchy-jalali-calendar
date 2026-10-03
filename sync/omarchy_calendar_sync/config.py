"""User configuration for the sync.

Absent config is a valid state: every key has a default, so a first run works
with no file at all.
"""

import copy
import errno
import json
import os
import stat
from datetime import timedelta
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "omarchy" / "calendar-sync.json"

# Which backend to pull from. "google" keeps the original behaviour for
# everyone already set up, so this key can be absent and nothing changes.
SOURCE_GOOGLE = "google"
SOURCE_CALDAV = "caldav"
SOURCES = (SOURCE_GOOGLE, SOURCE_CALDAV)

DEFAULTS = {
    "source": SOURCE_GOOGLE,
    # CalDAV, which is what company mail servers speak -- and Nextcloud,
    # Radicale, Fastmail and iCloud with it. The password is read from a
    # file rather than held here: config lands in a git-managed dotfiles
    # repo often enough that a mail password in it is a matter of time.
    "caldav": {
        "url": "",
        "username": "",
        "passwordFile": str(Path.home() / ".config" / "omarchy" / "calendar-caldav.password"),
        "verifyTls": True,
    },
    "profile": str(Path.home() / ".config" / "gws-omarchy-calendar"),
    # Resolved to an absolute path by sync/setup. A systemd user service
    # does not inherit an interactive shell PATH, so relying on the bare
    # name works from a terminal and fails from the timer.
    "gwsPath": "gws",
    "calendars": {"include": [], "exclude": []},
    "window": {"pastDays": 7, "futureDays": 60},
}


class ConfigError(Exception):
    """Raised when the config file exists but cannot be used."""


def load(path=None):
    """Load config, filling in defaults for anything absent."""
    path = Path(path) if path is not None else CONFIG_PATH

    if not path.exists():
        return _merge(copy.deepcopy(DEFAULTS), {})

    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigError(f"cannot read {path}: {error}") from error

    if not isinstance(raw, dict):
        raise ConfigError(f"{path} must contain a JSON object")

    merged = _merge(copy.deepcopy(DEFAULTS), raw)

    _validate_calendars(merged.get("calendars"))
    merged["source"] = _validate_source(merged.get("source"))
    _validate_caldav(merged)

    window = merged.get("window")
    if isinstance(window, dict):
        window["pastDays"] = _coerce_days(window.get("pastDays"), "window.pastDays")
        window["futureDays"] = _coerce_days(
            window.get("futureDays"), "window.futureDays"
        )

    return merged


def _merge(defaults, override):
    """One level of nesting is all this config has, so this stays simple."""
    merged = {}
    for key, fallback in defaults.items():
        value = override.get(key, fallback)
        if value is None:
            # An explicit null for a nested key means "not set", not "empty".
            value = fallback
        if isinstance(fallback, dict) and isinstance(value, dict):
            merged[key] = {**fallback, **value}
        else:
            merged[key] = value
    return merged


def _validate_calendars(calendars):
    """Reject a non-list include or exclude instead of silently misreading it."""
    if not isinstance(calendars, dict):
        return
    for key in ("include", "exclude"):
        value = calendars.get(key)
        if value is not None and not isinstance(value, list):
            raise ConfigError(f"calendars.{key} must be a list")


def _coerce_days(value, key):
    """Turn a window day count into an int, or fail loudly naming the key."""
    if isinstance(value, bool):
        raise ConfigError(f"{key} must be a number")
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            raise ConfigError(f"{key} must be a number") from None
    raise ConfigError(f"{key} must be a number")


def select_calendars(calendars, config):
    """Apply the include and exclude lists. Exclude always wins."""
    rules = config.get("calendars") or {}
    include = set(rules.get("include") or [])
    exclude = set(rules.get("exclude") or [])

    selected = []
    for calendar in calendars:
        keys = {calendar["id"], calendar["name"]}
        if keys & exclude:
            continue
        if include and not (keys & include):
            continue
        selected.append(calendar)
    return selected


def window_bounds(config, now):
    """Return RFC3339 timeMin and timeMax for the events query."""
    window = config.get("window") or {}
    past = int(window.get("pastDays", DEFAULTS["window"]["pastDays"]))
    future = int(window.get("futureDays", DEFAULTS["window"]["futureDays"]))
    return (
        (now - timedelta(days=past)).isoformat(),
        (now + timedelta(days=future)).isoformat(),
    )


def _validate_source(value):
    source = str(value or SOURCE_GOOGLE).strip().lower()
    if source not in SOURCES:
        raise ConfigError(
            f"source must be one of {', '.join(SOURCES)}, got {value!r}"
        )
    return source


def _validate_caldav(merged):
    """Only checked when it is the source in use.

    A half-filled caldav block sitting unused next to a working Google setup
    is not an error, and refusing to start over it would be.
    """
    caldav = merged.get("caldav")
    if not isinstance(caldav, dict):
        raise ConfigError("caldav must be a JSON object")

    caldav["verifyTls"] = caldav.get("verifyTls", True) is not False

    if merged.get("source") != SOURCE_CALDAV:
        return

    for key in ("url", "username"):
        if not str(caldav.get(key) or "").strip():
            raise ConfigError(f"caldav.{key} is required when source is caldav")


def read_password(cfg):
    """The CalDAV password, from the environment or the file named in config.

    OMARCHY_CALDAV_PASSWORD wins so a password manager can supply it without
    ever writing it to disk. The file is the fallback, and only a file that is
    this user's alone will do: see read_password_file.
    """
    from_env = os.environ.get("OMARCHY_CALDAV_PASSWORD")
    if from_env:
        return from_env

    path = Path(str(cfg.get("caldav", {}).get("passwordFile") or "")).expanduser()
    stored = read_password_file(path)
    if stored is None:
        raise ConfigError(
            f"no password: set OMARCHY_CALDAV_PASSWORD or create {path} "
            "containing the password on one line"
        )
    return stored


def read_password_file(path):
    """The password stored in a file, or None when there is no file.

    The file has to belong to this user and be closed to everyone else, or it
    is refused -- not warned about. A warning lands in a journal nobody reads
    while the sync goes on sending a password every other account on the
    machine could have copied, or rewritten. A symlink is refused as well:
    whoever can write the directory it sits in would get to choose which of
    the user's files goes to the server as the password.

    The checks run on the open descriptor, not on the name, so the file that
    passed them is the file that is read. The open does not block, so a FIFO
    left at the name is refused rather than hanging the sync.
    """
    path = Path(path)
    try:
        handle = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    except OSError as error:
        if error.errno == errno.ELOOP:
            raise ConfigError(
                f"{path} is a symbolic link; the password has to be in a plain file"
            ) from error
        raise ConfigError(f"cannot read {path}: {error}") from error

    try:
        problem = _password_file_problem(path, os.fstat(handle))
        if problem:
            raise ConfigError(problem)
        with open(handle, encoding="utf-8", closefd=False) as stream:
            return stream.read().strip()
    except (OSError, UnicodeDecodeError) as error:
        raise ConfigError(f"cannot read {path}: {error}") from error
    finally:
        os.close(handle)


def _password_file_problem(path, status):
    """Why the file at path cannot hold the password, or "" if it can."""
    if not stat.S_ISREG(status.st_mode):
        return f"{path} is not a regular file"
    if status.st_uid != os.geteuid():
        return f"{path} belongs to another user; create it again as yourself"
    if status.st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        return (
            f"{path} is open to other users (mode "
            f"{stat.S_IMODE(status.st_mode):04o}); run: chmod 600 {path}"
        )
    return ""
