import json
import os
import signal
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

from omarchy_calendar_sync import config

CALENDARS = [
    {"id": "a@example.com", "name": "Personal", "color": "#f83a22"},
    {"id": "b@example.com", "name": "Phases of the Moon", "color": "#fad165"},
    {"id": "c@example.com", "name": "Destify", "color": "#ffad46"},
]


class TestLoad(unittest.TestCase):
    def test_missing_file_returns_defaults(self):
        loaded = config.load(Path("/nonexistent/calendar-sync.json"))
        self.assertEqual(loaded, config.DEFAULTS)

    def test_partial_file_is_filled_with_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.json"
            path.write_text(json.dumps({"window": {"futureDays": 90}}))
            loaded = config.load(path)
            self.assertEqual(loaded["window"]["futureDays"], 90)
            self.assertEqual(
                loaded["window"]["pastDays"], config.DEFAULTS["window"]["pastDays"]
            )
            self.assertEqual(loaded["calendars"], config.DEFAULTS["calendars"])

    def test_malformed_json_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.json"
            path.write_text("{not json")
            with self.assertRaises(config.ConfigError):
                config.load(path)

    def test_defaults_are_not_mutated_by_a_returned_config(self):
        loaded = config.load(Path("/nonexistent/calendar-sync.json"))
        loaded["calendars"]["include"].append("leaked@example.com")
        self.assertEqual(config.DEFAULTS["calendars"]["include"], [])

    def test_null_calendars_and_window_keys_fill_with_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.json"
            path.write_text(json.dumps({"calendars": None, "window": None}))
            loaded = config.load(path)
            self.assertEqual(loaded["calendars"], config.DEFAULTS["calendars"])
            self.assertEqual(loaded["window"], config.DEFAULTS["window"])

    def test_null_past_days_raises_config_error_naming_the_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.json"
            path.write_text(json.dumps({"window": {"pastDays": None}}))
            with self.assertRaises(config.ConfigError) as ctx:
                config.load(path)
            self.assertIn("pastDays", str(ctx.exception))

    def test_non_numeric_future_days_raises_config_error_naming_the_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.json"
            path.write_text(json.dumps({"window": {"futureDays": "soon"}}))
            with self.assertRaises(config.ConfigError) as ctx:
                config.load(path)
            self.assertIn("futureDays", str(ctx.exception))

    def test_include_as_a_string_raises_config_error_naming_the_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.json"
            path.write_text(json.dumps({"calendars": {"include": "Personal"}}))
            with self.assertRaises(config.ConfigError) as ctx:
                config.load(path)
            self.assertIn("include", str(ctx.exception))


class TestSelectCalendars(unittest.TestCase):
    def test_empty_include_selects_all(self):
        selected = config.select_calendars(CALENDARS, config.DEFAULTS)
        self.assertEqual(len(selected), 3)

    def test_include_by_name(self):
        cfg = {"calendars": {"include": ["Personal"], "exclude": []}}
        selected = config.select_calendars(CALENDARS, cfg)
        self.assertEqual([c["name"] for c in selected], ["Personal"])

    def test_include_by_id(self):
        cfg = {"calendars": {"include": ["c@example.com"], "exclude": []}}
        selected = config.select_calendars(CALENDARS, cfg)
        self.assertEqual([c["name"] for c in selected], ["Destify"])

    def test_exclude_removes_from_all(self):
        cfg = {"calendars": {"include": [], "exclude": ["Phases of the Moon"]}}
        selected = config.select_calendars(CALENDARS, cfg)
        self.assertEqual([c["name"] for c in selected], ["Personal", "Destify"])

    def test_exclude_beats_include(self):
        cfg = {"calendars": {"include": ["Personal"], "exclude": ["Personal"]}}
        self.assertEqual(config.select_calendars(CALENDARS, cfg), [])

    def test_unknown_name_selects_nothing_rather_than_everything(self):
        cfg = {"calendars": {"include": ["Typo"], "exclude": []}}
        self.assertEqual(config.select_calendars(CALENDARS, cfg), [])


class TestWindowBounds(unittest.TestCase):
    def test_bounds_bracket_now(self):
        now = datetime(2026, 8, 10, 12, 0, tzinfo=timezone.utc)
        time_min, time_max = config.window_bounds(config.DEFAULTS, now)
        self.assertTrue(time_min.startswith("2026-08-03"))
        self.assertTrue(time_max.startswith("2026-10-09"))

    def test_bounds_respect_custom_window(self):
        now = datetime(2026, 8, 10, 12, 0, tzinfo=timezone.utc)
        cfg = {"window": {"pastDays": 1, "futureDays": 2}}
        time_min, time_max = config.window_bounds(cfg, now)
        self.assertTrue(time_min.startswith("2026-08-09"))
        self.assertTrue(time_max.startswith("2026-08-12"))


class TestReadPassword(unittest.TestCase):
    """The file is used only when it is this user's alone. Anything looser is
    an error that stops the sync, not a warning it prints and then ignores."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "caldav.password"
        self.cfg = {"caldav": {"passwordFile": str(self.path)}}

        environment = mock.patch.dict(os.environ)
        environment.start()
        self.addCleanup(environment.stop)
        os.environ.pop("OMARCHY_CALDAV_PASSWORD", None)

    def write(self, mode, text="hunter2\n"):
        self.path.write_text(text)
        os.chmod(self.path, mode)

    def refusal(self):
        with self.assertRaises(config.ConfigError) as caught:
            config.read_password(self.cfg)
        return str(caught.exception)

    def test_a_file_only_its_owner_can_open_is_read(self):
        self.write(0o600)
        self.assertEqual(config.read_password(self.cfg), "hunter2")

    def test_a_file_others_can_read_is_refused(self):
        self.write(0o644)
        self.assertIn(f"chmod 600 {self.path}", self.refusal())

    # Write alone is enough to refuse: whoever can rewrite the file decides
    # what the sync sends to the server as the password.
    def test_any_access_for_group_or_others_is_refused(self):
        for mode in (0o640, 0o620, 0o604, 0o602, 0o610):
            with self.subTest(mode=oct(mode)):
                self.write(mode)
                self.assertIn(f"{mode:04o}", self.refusal())

    def test_a_symlink_is_refused_even_to_a_private_file(self):
        target = Path(self.tmp.name) / "real.password"
        target.write_text("hunter2\n")
        os.chmod(target, 0o600)
        self.path.symlink_to(target)
        self.assertIn("symbolic link", self.refusal())

    def test_a_file_that_belongs_to_someone_else_is_refused(self):
        self.write(0o600)
        with mock.patch.object(config.os, "geteuid", return_value=os.geteuid() + 1):
            self.assertIn("another user", self.refusal())

    def test_a_directory_is_refused_as_a_config_error(self):
        self.path.mkdir()
        self.assertIn("not a regular file", self.refusal())

    def test_a_fifo_is_refused_rather_than_waited_on(self):
        os.mkfifo(self.path, 0o600)

        # A blocking open would wait forever for a writer that never comes.
        # The alarm turns that hang into a failure instead of a stuck suite.
        def hung(signum, frame):
            raise AssertionError("opening the password file blocked on a FIFO")

        previous = signal.signal(signal.SIGALRM, hung)
        signal.alarm(5)
        try:
            self.assertIn("not a regular file", self.refusal())
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, previous)

    def test_a_missing_file_says_how_to_supply_the_password(self):
        self.assertIn("OMARCHY_CALDAV_PASSWORD", self.refusal())

    def test_the_environment_wins_and_the_file_is_not_consulted(self):
        self.write(0o644, "from the file\n")
        os.environ["OMARCHY_CALDAV_PASSWORD"] = "from the environment"
        self.assertEqual(config.read_password(self.cfg), "from the environment")


if __name__ == "__main__":
    unittest.main()


class TestGwsPath(unittest.TestCase):
    def test_defaults_to_the_bare_name(self):
        self.assertEqual(config.DEFAULTS["gwsPath"], "gws")

    def test_an_absolute_path_is_kept(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.json"
            path.write_text(json.dumps({"gwsPath": "/opt/bin/gws"}))
            self.assertEqual(config.load(path)["gwsPath"], "/opt/bin/gws")
