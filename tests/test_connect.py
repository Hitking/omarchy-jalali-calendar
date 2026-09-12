import io
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path

from omarchy_calendar_sync import connect

CALENDARS = [
    {"id": "1", "name": "Personal", "color": "#f83a22", "url": "https://mail/cal/1/"},
    {"id": "2", "name": "Work", "color": "#7bd148", "url": "https://mail/cal/2/"},
]

REQUEST = {
    "url": "https://mail.example.com/",
    "username": "me@example.com",
    "password": "hunter2",
}


class FakeClient:
    """Records what it was constructed with, answers with fixed calendars."""

    last = None

    def __init__(self, url, username, password, *, verify_tls=True):
        FakeClient.last = self
        self.url = url
        self.username = username
        self.password = password
        self.verify_tls = verify_tls

    def calendars(self):
        return CALENDARS


def failing_client(error):
    class Failing(FakeClient):
        def calendars(self):
            raise error

    return Failing


class ConnectHarness(unittest.TestCase):
    """A temp home with the collaborators stubbed out.

    Nothing here touches the real config, the real systemd, or the network.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.config_path = self.home / "config" / "calendar-sync.json"
        self.unit_dir = self.home / "systemd"
        self.commands = []
        self.synced = []

    def run_command(self, command):
        self.commands.append(command)
        return None

    def sync(self, config_path):
        # The password reaches the sync through the environment, and asserting
        # that is the point of recording it here.
        self.synced.append((config_path, os.environ.get("OMARCHY_CALDAV_PASSWORD")))
        return 0

    def connect(self, request=None, **overrides):
        kwargs = {
            "client_factory": FakeClient,
            "config_path": self.config_path,
            "unit_dir": self.unit_dir,
            "run_command": self.run_command,
            "sync": self.sync,
        }
        kwargs.update(overrides)
        payload = dict(REQUEST if request is None else request)
        if "passwordFile" not in payload:
            payload["passwordFile"] = str(self.home / "caldav.password")
        return connect.connect(payload, **kwargs)

    @property
    def config(self):
        return json.loads(self.config_path.read_text())


class TestHappyPath(ConnectHarness):
    def test_reports_the_calendars_it_found(self):
        result = self.connect()
        self.assertTrue(result["ok"])
        self.assertEqual(
            result["calendars"],
            [
                {"name": "Personal", "color": "#f83a22"},
                {"name": "Work", "color": "#7bd148"},
            ],
        )

    def test_writes_the_config_the_sync_reads(self):
        self.connect()
        self.assertEqual(self.config["source"], "caldav")
        self.assertEqual(self.config["caldav"]["url"], REQUEST["url"])
        self.assertEqual(self.config["caldav"]["username"], REQUEST["username"])
        self.assertIs(self.config["caldav"]["verifyTls"], True)

    def test_the_written_config_loads(self):
        # The end of this pipeline is config.load, and a document that writes
        # cleanly but fails validation would only show up at the next sync.
        from omarchy_calendar_sync import config as config_module

        self.connect()
        loaded = config_module.load(self.config_path)
        self.assertEqual(loaded["source"], "caldav")
        self.assertEqual(loaded["caldav"]["username"], REQUEST["username"])

    def test_password_file_is_not_readable_by_anyone_else(self):
        result = self.connect()
        path = Path(result["passwordFile"])
        self.assertEqual(path.read_text().strip(), "hunter2")
        mode = path.stat().st_mode
        self.assertFalse(mode & (stat.S_IRWXG | stat.S_IRWXO), oct(mode))

    def test_keeps_unrelated_config_keys(self):
        self.config_path.parent.mkdir(parents=True)
        self.config_path.write_text(json.dumps({
            "profile": "/home/someone/.config/gws-omarchy-calendar",
            "window": {"pastDays": 30, "futureDays": 90},
        }))
        self.connect()
        self.assertEqual(self.config["window"], {"pastDays": 30, "futureDays": 90})
        self.assertEqual(
            self.config["profile"], "/home/someone/.config/gws-omarchy-calendar"
        )

    def test_installs_the_units_pointing_at_this_checkout(self):
        result = self.connect()
        self.assertEqual(result["timer"], "enabled")
        service = (self.unit_dir / "omarchy-calendar-sync.service").read_text()
        self.assertIn(f"ExecStart={connect.SYNC_BIN}", service)
        self.assertTrue((self.unit_dir / "omarchy-calendar-sync.timer").exists())
        self.assertEqual(self.commands[0], ["systemctl", "--user", "daemon-reload"])
        self.assertIn("enable", self.commands[1])

    def test_runs_one_sync_with_the_password_in_the_environment(self):
        result = self.connect()
        self.assertEqual(result["firstSync"], "ok")
        self.assertEqual(self.synced, [(self.config_path, "hunter2")])

    def test_the_environment_is_left_as_it_was_found(self):
        self.connect()
        self.assertIsNone(os.environ.get("OMARCHY_CALDAV_PASSWORD"))

    def test_verify_tls_off_reaches_the_client_and_the_config(self):
        request = dict(REQUEST, verifyTls=False)
        self.connect(request)
        self.assertFalse(FakeClient.last.verify_tls)
        self.assertIs(self.config["caldav"]["verifyTls"], False)


class TestNothingIsWrittenUntilItWorks(ConnectHarness):
    def test_refused_credentials_write_nothing(self):
        from omarchy_calendar_sync.caldav import CalDavAuthError

        with self.assertRaises(connect.ConnectError) as caught:
            self.connect(client_factory=failing_client(CalDavAuthError("401 from the server")))

        self.assertEqual(caught.exception.stage, connect.STAGE_CREDENTIALS)
        self.assertFalse(self.config_path.exists())
        self.assertFalse((self.home / "caldav.password").exists())
        self.assertEqual(self.commands, [])

    def test_an_unreachable_server_writes_nothing(self):
        from omarchy_calendar_sync.caldav import CalDavError

        with self.assertRaises(connect.ConnectError) as caught:
            self.connect(client_factory=failing_client(CalDavError("name or service not known")))

        self.assertEqual(caught.exception.stage, connect.STAGE_CREDENTIALS)
        self.assertFalse(self.config_path.exists())

    def test_an_account_with_no_calendars_is_a_failure(self):
        class Empty(FakeClient):
            def calendars(self):
                return []

        with self.assertRaises(connect.ConnectError) as caught:
            self.connect(client_factory=Empty)
        self.assertEqual(caught.exception.stage, connect.STAGE_CREDENTIALS)

    def test_a_missing_field_never_reaches_the_server(self):
        for key in ("url", "username"):
            request = dict(REQUEST)
            request[key] = "  "
            with self.assertRaises(connect.ConnectError) as caught:
                self.connect(request)
            self.assertEqual(caught.exception.stage, connect.STAGE_INPUT)
            self.assertIn(key.replace("url", "server URL"), caught.exception.message)


class TestStoredPassword(ConnectHarness):
    def test_a_blank_password_keeps_the_stored_one(self):
        # The panel cannot show a password it never had, so editing the URL
        # sends the field blank. That must not erase a working password.
        self.connect()
        result = self.connect(dict(REQUEST, password="", url="https://mail2.example.com/"))
        self.assertTrue(result["ok"])
        self.assertEqual(FakeClient.last.password, "hunter2")
        self.assertEqual(self.config["caldav"]["url"], "https://mail2.example.com/")

    def test_a_blank_password_with_nothing_stored_is_an_error(self):
        with self.assertRaises(connect.ConnectError) as caught:
            self.connect(dict(REQUEST, password=""))
        self.assertEqual(caught.exception.stage, connect.STAGE_INPUT)
        self.assertIn("password", caught.exception.message)

    def test_the_password_file_from_config_is_reused_when_none_is_named(self):
        stored = self.home / "elsewhere.password"
        self.config_path.parent.mkdir(parents=True)
        self.config_path.write_text(json.dumps({"caldav": {"passwordFile": str(stored)}}))

        request = {k: v for k, v in REQUEST.items()}
        result = connect.connect(
            request,
            client_factory=FakeClient,
            config_path=self.config_path,
            unit_dir=self.unit_dir,
            run_command=self.run_command,
            sync=self.sync,
        )
        self.assertEqual(result["passwordFile"], str(stored))
        self.assertEqual(stored.read_text().strip(), "hunter2")


class TestPartialFailuresAreReportedNotRaised(ConnectHarness):
    def test_a_systemctl_that_fails_still_reports_a_connection(self):
        result = self.connect(run_command=lambda command: "Failed to connect to bus")
        self.assertTrue(result["ok"])
        self.assertIn("not enabled", result["timer"])

    def test_a_failing_first_sync_is_named_rather_than_hidden(self):
        result = self.connect(sync=lambda path: 1)
        self.assertTrue(result["ok"])
        self.assertIn("failed", result["firstSync"])


class TestMain(unittest.TestCase):
    """The stdin/stdout contract the panel actually depends on."""

    def call(self, payload, **patches):
        original = connect.connect
        for key, value in patches.items():
            setattr(connect, key, value)
        try:
            out = io.StringIO()
            code = connect.main(
                stdin=io.StringIO(payload), stdout=out, stderr=io.StringIO()
            )
            return code, json.loads(out.getvalue())
        finally:
            connect.connect = original

    def test_a_result_is_one_json_object_on_stdout(self):
        code, document = self.call(
            json.dumps(REQUEST), connect=lambda request: {"ok": True, "calendars": []}
        )
        self.assertEqual(code, 0)
        self.assertTrue(document["ok"])

    def test_a_connect_error_becomes_a_stage_and_a_sentence(self):
        def refuse(request):
            raise connect.ConnectError(connect.STAGE_CREDENTIALS, "401 from the server")

        code, document = self.call(json.dumps(REQUEST), connect=refuse)
        self.assertEqual(code, 1)
        self.assertFalse(document["ok"])
        self.assertEqual(document["stage"], "credentials")
        self.assertEqual(document["error"], "401 from the server")

    def test_an_unexpected_error_is_still_json(self):
        # The panel parses stdout. A traceback on stdout would leave it
        # reporting nothing at all, which is the one outcome worse than an
        # ugly message.
        def explode(request):
            raise RuntimeError("something nobody predicted")

        code, document = self.call(json.dumps(REQUEST), connect=explode)
        self.assertEqual(code, 1)
        self.assertEqual(document["stage"], "unexpected")
        self.assertIn("nobody predicted", document["error"])

    def test_junk_on_stdin_is_rejected_as_json(self):
        code, document = self.call("not json at all")
        self.assertEqual(code, 1)
        self.assertEqual(document["stage"], "input")


if __name__ == "__main__":
    unittest.main()
