"""The CalDAV client: what it sends, and what it makes of what comes back.

No network. A fake opener records every request and answers from a script, so
these tests are about request construction and multistatus parsing -- the two
places a CalDAV client actually goes wrong.
"""

import unittest
import urllib.error
from datetime import datetime, timezone

from omarchy_calendar_sync.caldav import (
    CalDav, CalDavAuthError, CalDavError, CalDavOriginError)

MULTISTATUS = '<?xml version="1.0"?>\n<d:multistatus xmlns:d="DAV:" %s>%s</d:multistatus>'
CALDAV_NS = 'xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:x="http://apple.com/ns/ical/"'


class FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self._body = body.encode("utf-8")

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeOpener:
    """Answers in order, or per-URL, and remembers everything it was asked."""

    def __init__(self, script):
        self.script = script
        self.requests = []

    def open(self, request, timeout=None):
        self.requests.append(request)
        answer = self.script(request)
        if isinstance(answer, Exception):
            raise answer
        return answer


def responder(*pairs):
    """Match a request by an `in` test against its URL, in order given."""
    remaining = list(pairs)

    def answer(request):
        for index, (needle, response) in enumerate(remaining):
            if needle in request.full_url:
                if not isinstance(response, list):
                    return response
                found = response.pop(0)
                if not response:
                    remaining.pop(index)
                return found
        raise urllib.error.HTTPError(request.full_url, 404, "Not Found", {}, None)

    return answer


PRINCIPAL_BODY = MULTISTATUS % ("", """
  <d:response>
    <d:href>/</d:href>
    <d:propstat>
      <d:status>HTTP/1.1 200 OK</d:status>
      <d:prop><d:current-user-principal>
        <d:href>/principals/masoud@example.com/</d:href>
      </d:current-user-principal></d:prop>
    </d:propstat>
  </d:response>""")

HOME_BODY = MULTISTATUS % (CALDAV_NS, """
  <d:response>
    <d:href>/principals/masoud@example.com/</d:href>
    <d:propstat>
      <d:status>HTTP/1.1 200 OK</d:status>
      <d:prop><c:calendar-home-set>
        <d:href>/calendars/masoud@example.com/</d:href>
      </c:calendar-home-set></d:prop>
    </d:propstat>
  </d:response>""")

CALENDARS_BODY = MULTISTATUS % (CALDAV_NS, """
  <d:response>
    <d:href>/calendars/masoud@example.com/</d:href>
    <d:propstat><d:status>HTTP/1.1 200 OK</d:status>
      <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/calendars/masoud@example.com/work/</d:href>
    <d:propstat><d:status>HTTP/1.1 200 OK</d:status>
      <d:prop>
        <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
        <d:displayname>Work</d:displayname>
        <x:calendar-color>#FF8800FF</x:calendar-color>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/calendars/masoud@example.com/tasks/</d:href>
    <d:propstat><d:status>HTTP/1.1 200 OK</d:status>
      <d:prop>
        <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
        <d:displayname>Tasks</d:displayname>
        <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/calendars/masoud@example.com/personal/</d:href>
    <d:propstat><d:status>HTTP/1.1 200 OK</d:status>
      <d:prop>
        <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
        <d:displayname>Personal</d:displayname>
      </d:prop>
    </d:propstat>
    <d:propstat><d:status>HTTP/1.1 404 Not Found</d:status>
      <d:prop><x:calendar-color/></d:prop>
    </d:propstat>
  </d:response>""")


def discovering_client(extra=()):
    opener = FakeOpener(responder(
        ("/principals/", FakeResponse(207, HOME_BODY)),
        ("/calendars/", FakeResponse(207, CALENDARS_BODY)),
        *extra,
        ("", FakeResponse(207, PRINCIPAL_BODY)),
    ))
    return CalDav("https://mail.example.com", "masoud@example.com", "pw",
                  opener=opener), opener


class RequestTests(unittest.TestCase):
    def test_credentials_are_sent_without_waiting_to_be_challenged(self):
        client, opener = discovering_client()
        client.check()
        header = opener.requests[0].get_header("Authorization")
        self.assertTrue(header.startswith("Basic "))

    def test_a_bare_hostname_is_assumed_to_be_https(self):
        self.assertEqual(
            CalDav("mail.example.com", "u", "p", opener=FakeOpener(lambda r: None)).base_url,
            "https://mail.example.com")

    def test_an_empty_url_is_refused_up_front(self):
        with self.assertRaises(CalDavError):
            CalDav("", "u", "p")

    def test_propfind_is_sent_as_propfind_with_a_depth(self):
        client, opener = discovering_client()
        client.calendars()
        methods = [(r.get_method(), r.get_header("Depth")) for r in opener.requests]
        self.assertIn(("PROPFIND", "0"), methods)
        self.assertIn(("PROPFIND", "1"), methods)

    # urllib turns a redirected POST into a GET. For a REPORT that means the
    # server answers with a web page and the failure surfaces far from its
    # cause, so redirects are followed by hand.
    def test_a_redirect_keeps_the_method(self):
        redirect = urllib.error.HTTPError(
            "https://mail.example.com/", 301, "Moved",
            {"Location": "https://mail.example.com/dav/"}, None)
        opener = FakeOpener(responder(
            ("/dav/", FakeResponse(207, PRINCIPAL_BODY)),
            ("", redirect),
        ))
        client = CalDav("https://mail.example.com", "u", "p", opener=opener)
        client.current_user_principal()
        self.assertEqual(opener.requests[-1].get_method(), "PROPFIND")
        self.assertEqual(opener.requests[-1].full_url, "https://mail.example.com/dav/")

    # A redirect is the server choosing where the next request goes, and the
    # next request carries the password. A server that names another host is
    # asking for a credential it was never given, so the answer is no.
    def test_a_redirect_to_another_host_does_not_take_the_password_along(self):
        away = urllib.error.HTTPError(
            "https://mail.example.com/", 302, "Found",
            {"Location": "https://evil.example.net/dav/"}, None)
        opener = FakeOpener(lambda r: away)
        client = CalDav("https://mail.example.com", "u", "pw", opener=opener)
        with self.assertRaises(CalDavOriginError):
            client.current_user_principal()
        self.assertEqual(
            [r.full_url for r in opener.requests],
            ["https://mail.example.com/"])

    def test_a_redirect_to_plain_http_does_not_take_the_password_along(self):
        downgrade = urllib.error.HTTPError(
            "https://mail.example.com/", 301, "Moved",
            {"Location": "http://mail.example.com/dav/"}, None)
        opener = FakeOpener(lambda r: downgrade)
        client = CalDav("https://mail.example.com", "u", "pw", opener=opener)
        with self.assertRaises(CalDavOriginError):
            client.request("PROPFIND", "https://mail.example.com/")
        self.assertEqual(len(opener.requests), 1)

    def test_a_redirect_to_another_port_does_not_take_the_password_along(self):
        moved = urllib.error.HTTPError(
            "https://mail.example.com/", 307, "Moved",
            {"Location": "https://mail.example.com:8443/dav/"}, None)
        client = CalDav("https://mail.example.com", "u", "pw",
                        opener=FakeOpener(lambda r: moved))
        with self.assertRaises(CalDavOriginError):
            client.request("PROPFIND", "https://mail.example.com/")

    # The default port spelled out is the same server, not a new one.
    def test_the_default_port_written_out_is_the_same_server(self):
        moved = urllib.error.HTTPError(
            "https://mail.example.com/", 301, "Moved",
            {"Location": "https://MAIL.example.com:443/dav/"}, None)
        opener = FakeOpener(responder(
            ("/dav/", FakeResponse(207, PRINCIPAL_BODY)),
            ("", moved),
        ))
        client = CalDav("https://mail.example.com", "u", "pw", opener=opener)
        client.current_user_principal()
        self.assertEqual(opener.requests[-1].get_method(), "PROPFIND")

    # Discovery swallows failures and tries the next candidate URL. This one
    # it must not swallow: the next candidate would fail the same way and the
    # user would be told to check a URL that is fine.
    def test_a_redirect_off_the_server_is_reported_not_retried(self):
        away = urllib.error.HTTPError(
            "https://mail.example.com/", 302, "Found",
            {"Location": "https://evil.example.net/"}, None)
        client = CalDav("https://mail.example.com", "u", "pw",
                        opener=FakeOpener(lambda r: away))
        with self.assertRaises(CalDavOriginError) as caught:
            client.check()
        self.assertIn("evil.example.net", str(caught.exception))

    # An href in an answer is the server choosing a URL too, and discovery
    # follows those from one hop to the next.
    def test_an_href_pointing_off_the_server_is_refused(self):
        away_body = PRINCIPAL_BODY.replace(
            "<d:href>/principals/masoud@example.com/</d:href>",
            "<d:href>https://evil.example.net/principals/</d:href>")
        opener = FakeOpener(responder(("", FakeResponse(207, away_body))))
        client = CalDav("https://mail.example.com", "u", "pw", opener=opener)
        with self.assertRaises(CalDavOriginError):
            client.calendars()
        self.assertNotIn(
            "evil.example.net", " ".join(r.full_url for r in opener.requests))

    # The other direction is the ordinary setup, and it takes the password
    # off the clear wire rather than putting it on one.
    def test_http_redirected_to_https_on_the_same_host_is_followed(self):
        upgrade = urllib.error.HTTPError(
            "http://mail.example.com/", 301, "Moved",
            {"Location": "https://mail.example.com/"}, None)
        opener = FakeOpener(responder(
            ("https://", FakeResponse(207, PRINCIPAL_BODY)),
            ("", upgrade),
        ))
        client = CalDav("http://mail.example.com", "u", "pw", opener=opener)
        client.current_user_principal()
        self.assertEqual(
            opener.requests[-1].full_url, "https://mail.example.com/")

    def test_a_redirect_loop_gives_up_rather_than_spinning(self):
        loop = urllib.error.HTTPError(
            "https://mail.example.com/", 302, "Found",
            {"Location": "https://mail.example.com/"}, None)
        client = CalDav("https://x/", "u", "p", opener=FakeOpener(lambda r: loop))
        with self.assertRaises(CalDavError):
            client.request("PROPFIND", "https://x/")

    # The single most likely failure, so it gets the message that says what to
    # do rather than a status code.
    def test_a_rejected_password_says_so_in_words(self):
        denied = urllib.error.HTTPError("https://x/", 401, "Unauthorized", {}, None)
        client = CalDav("https://x/", "u", "p", opener=FakeOpener(lambda r: denied))
        with self.assertRaises(CalDavAuthError) as caught:
            client.check()
        self.assertIn("username or password", str(caught.exception))

    # Discovery tries several URLs and moves past the ones that fail. A
    # refused password must not be one of those: every candidate would refuse
    # it too, and the user would be told to check a URL that is correct.
    def test_a_rejected_password_is_not_retried_against_other_urls(self):
        denied = urllib.error.HTTPError("https://x/", 401, "Unauthorized", {}, None)
        opener = FakeOpener(lambda r: denied)
        client = CalDav("https://x/", "u", "p", opener=opener)
        with self.assertRaises(CalDavAuthError):
            client.current_user_principal()
        self.assertEqual(len(opener.requests), 1, "it gave up on the first refusal")

    def test_an_unreachable_server_is_reported_as_such(self):
        client = CalDav("https://x/", "u", "p", opener=FakeOpener(
            lambda r: urllib.error.URLError("Name or service not known")))
        with self.assertRaises(CalDavError) as caught:
            client.request("PROPFIND", "https://x/")
        self.assertIn("cannot reach", str(caught.exception))

    def test_a_non_xml_answer_is_reported_rather_than_crashing(self):
        client = CalDav("https://x/", "u", "p",
                        opener=FakeOpener(lambda r: FakeResponse(207, "<html>hi")))
        with self.assertRaises(CalDavError) as caught:
            client.propfind("https://x/", "<body/>")
        self.assertIn("did not return XML", str(caught.exception))


class DiscoveryTests(unittest.TestCase):
    def test_the_principal_and_home_are_asked_for_rather_than_guessed(self):
        client, _ = discovering_client()
        principal = client.current_user_principal()
        self.assertEqual(principal, "https://mail.example.com/principals/masoud@example.com/")
        self.assertEqual(client.calendar_home(principal),
                         "https://mail.example.com/calendars/masoud@example.com/")

    def test_a_server_that_names_no_principal_says_what_to_check(self):
        client = CalDav("https://x/", "u", "p", opener=FakeOpener(
            lambda r: FakeResponse(207, MULTISTATUS % ("", ""))))
        with self.assertRaises(CalDavError) as caught:
            client.current_user_principal()
        self.assertIn("mail server root", str(caught.exception))


class CalendarListTests(unittest.TestCase):
    def setUp(self):
        client, _ = discovering_client()
        self.found = client.calendars()

    def test_only_real_calendars_are_listed(self):
        names = [c["name"] for c in self.found]
        self.assertEqual(names, ["Personal", "Work"], "sorted by name")

    def test_a_plain_collection_is_not_a_calendar(self):
        self.assertNotIn("/calendars/masoud@example.com/",
                         [c["url"] for c in self.found])

    # A collection that holds only todos has nothing to put on a month grid.
    def test_a_todo_only_collection_is_skipped(self):
        self.assertNotIn("Tasks", [c["name"] for c in self.found])

    def test_an_eight_digit_colour_loses_its_alpha(self):
        work = next(c for c in self.found if c["name"] == "Work")
        self.assertEqual(work["color"], "#ff8800")

    # A dot needs a colour whether or not the server has an opinion, and two
    # calendars sharing one would make the grid unreadable.
    def test_a_calendar_with_no_colour_still_gets_one(self):
        personal = next(c for c in self.found if c["name"] == "Personal")
        self.assertRegex(personal["color"], r"^#[0-9a-f]{6}$")
        self.assertNotEqual(personal["color"], "#ff8800")

    def test_the_url_is_absolute_so_it_can_be_fetched(self):
        for calendar in self.found:
            self.assertTrue(calendar["url"].startswith("https://mail.example.com/"))
            self.assertEqual(calendar["id"], calendar["url"])


ONE_EVENT = """BEGIN:VCALENDAR\r
BEGIN:VEVENT\r
UID:a@example.com\r
SUMMARY:Standup\r
DTSTART;TZID=Iran Standard Time:20260830T090000\r
END:VEVENT\r
END:VCALENDAR"""

REPORT_BODY = MULTISTATUS % (CALDAV_NS, """
  <d:response>
    <d:href>/calendars/masoud@example.com/work/1.ics</d:href>
    <d:propstat><d:status>HTTP/1.1 200 OK</d:status>
      <d:prop><d:getetag>"1"</d:getetag><c:calendar-data>%s</c:calendar-data></d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/calendars/masoud@example.com/work/2.ics</d:href>
    <d:propstat><d:status>HTTP/1.1 404 Not Found</d:status>
      <d:prop><c:calendar-data/></d:prop>
    </d:propstat>
  </d:response>""" % ONE_EVENT.replace("\r\n", "&#13;\n"))


class ReportTests(unittest.TestCase):
    def fetch(self):
        opener = FakeOpener(lambda r: FakeResponse(207, REPORT_BODY))
        client = CalDav("https://mail.example.com", "u", "p", opener=opener)
        objects = client.events(
            "https://mail.example.com/calendars/masoud@example.com/work/",
            datetime(2026, 8, 1, tzinfo=timezone.utc),
            datetime(2026, 10, 1, tzinfo=timezone.utc))
        return objects, opener

    def test_the_query_is_a_report_with_a_utc_time_range(self):
        _, opener = self.fetch()
        request = opener.requests[0]
        body = request.data.decode("utf-8")
        self.assertEqual(request.get_method(), "REPORT")
        self.assertIn("calendar-query", body)
        self.assertIn('start="20260801T000000Z"', body)
        self.assertIn('end="20261001T000000Z"', body)

    def test_calendar_data_comes_back(self):
        objects, _ = self.fetch()
        self.assertEqual(len(objects), 1)
        self.assertIn("SUMMARY:Standup", objects[0])

    # A multistatus reports found and missing properties in separate blocks.
    # Reading the first one blindly picks up the 404 block on servers that
    # list it first, and then every property reads as absent.
    def test_a_not_found_block_is_not_mistaken_for_data(self):
        objects, _ = self.fetch()
        self.assertEqual(len(objects), 1, "the 404 response contributed nothing")



class RunCalDavTests(unittest.TestCase):
    """The whole CalDAV path, from a fake server to a validated file."""

    def run_sync(self, calendar_data, config_extra=None):
        import json
        import tempfile
        from pathlib import Path
        from zoneinfo import ZoneInfo

        from omarchy_calendar_sync import cli, config as config_module

        report = MULTISTATUS % (CALDAV_NS, """
          <d:response>
            <d:href>/calendars/masoud@example.com/work/1.ics</d:href>
            <d:propstat><d:status>HTTP/1.1 200 OK</d:status>
              <d:prop><c:calendar-data>%s</c:calendar-data></d:prop>
            </d:propstat>
          </d:response>""" % calendar_data)

        opener = FakeOpener(responder(
            ("/principals/", FakeResponse(207, HOME_BODY)),
            ("/work/", FakeResponse(207, report)),
            ("/personal/", FakeResponse(207, MULTISTATUS % (CALDAV_NS, ""))),
            ("/calendars/", FakeResponse(207, CALENDARS_BODY)),
            ("", FakeResponse(207, PRINCIPAL_BODY)),
        ))
        client = CalDav("https://mail.example.com", "masoud@example.com", "pw",
                        opener=opener)

        cfg = config_module.load("/nonexistent")
        cfg["source"] = "caldav"
        cfg["caldav"] = {"url": "https://mail.example.com", "username": "masoud@example.com",
                         "passwordFile": "", "verifyTls": True}
        if config_extra:
            cfg.update(config_extra)

        now = datetime(2026, 8, 25, 12, 0, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "events.json"
            code = cli.run_caldav(client, cfg, now, out, ZoneInfo("Asia/Tehran"))
            doc = json.loads(out.read_text()) if out.exists() else None
        return code, doc

    def test_a_recurring_event_becomes_one_row_per_occurrence(self):
        data = ("BEGIN:VCALENDAR&#13;\n"
                "BEGIN:VEVENT&#13;\n"
                "UID:a@example.com&#13;\n"
                "SUMMARY:Standup&#13;\n"
                "DTSTART;TZID=Iran Standard Time:20260830T090000&#13;\n"
                "DTEND;TZID=Iran Standard Time:20260830T091500&#13;\n"
                "RRULE:FREQ=DAILY;COUNT=3&#13;\n"
                "END:VEVENT&#13;\n"
                "END:VCALENDAR")
        code, doc = self.run_sync(data)

        self.assertEqual(code, 0)
        self.assertEqual([row["dateKey"] for row in doc["events"]],
                         ["2026-08-30", "2026-08-31", "2026-09-01"])
        self.assertTrue(doc["source"].startswith("caldav/mail.example.com"))

    # The file the widget reads is a contract, and a source that wrote an
    # invalid one would be a source the widget renders as an empty month.
    def test_the_document_it_writes_satisfies_the_contract(self):
        from omarchy_calendar_sync import contract

        data = ("BEGIN:VCALENDAR&#13;\nBEGIN:VEVENT&#13;\n"
                "UID:a@example.com&#13;\nSUMMARY:Review&#13;\n"
                "DTSTART;TZID=Iran Standard Time:20260901T140000&#13;\n"
                "DTEND;TZID=Iran Standard Time:20260901T150000&#13;\n"
                "END:VEVENT&#13;\nEND:VCALENDAR")
        code, doc = self.run_sync(data)

        self.assertEqual(code, 0)
        self.assertEqual(contract.validate(doc), [])
        self.assertEqual(doc["version"], 1)

    # The Jalali display is a rendering of a day, never its name, so the file
    # is Gregorian no matter which calendar the widget is showing.
    def test_the_date_keys_are_gregorian(self):
        data = ("BEGIN:VCALENDAR&#13;\nBEGIN:VEVENT&#13;\n"
                "UID:a@example.com&#13;\nSUMMARY:Nowruz planning&#13;\n"
                "DTSTART;TZID=Iran Standard Time:20260901T090000&#13;\n"
                "END:VEVENT&#13;\nEND:VCALENDAR")
        _, doc = self.run_sync(data)
        self.assertEqual(doc["events"][0]["dateKey"], "2026-09-01")

    def test_an_empty_calendar_still_writes_a_valid_file(self):
        from omarchy_calendar_sync import contract

        code, doc = self.run_sync("BEGIN:VCALENDAR&#13;\nEND:VCALENDAR")
        self.assertEqual(code, 0)
        self.assertEqual(doc["events"], [])
        self.assertEqual(contract.validate(doc), [])

    def test_the_include_list_narrows_which_calendars_are_read(self):
        data = ("BEGIN:VCALENDAR&#13;\nBEGIN:VEVENT&#13;\n"
                "UID:a&#13;\nSUMMARY:X&#13;\n"
                "DTSTART;TZID=Iran Standard Time:20260901T090000&#13;\n"
                "END:VEVENT&#13;\nEND:VCALENDAR")
        code, doc = self.run_sync(data, {"calendars": {"include": ["Work"], "exclude": []}})
        self.assertEqual(code, 0)
        self.assertTrue(all(row["calendarName"] == "Work" for row in doc["events"]))

    def test_a_server_failure_is_reported_and_writes_nothing(self):
        from omarchy_calendar_sync import cli, config as config_module
        from pathlib import Path
        from zoneinfo import ZoneInfo
        import tempfile

        denied = urllib.error.HTTPError("https://x/", 401, "Unauthorized", {}, None)
        client = CalDav("https://x/", "u", "p", opener=FakeOpener(lambda r: denied))

        cfg = config_module.load("/nonexistent")
        cfg["source"] = "caldav"
        cfg["caldav"] = {"url": "https://x/", "username": "u",
                         "passwordFile": "", "verifyTls": True}

        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "events.json"
            code = cli.run_caldav(client, cfg,
                                  datetime(2026, 8, 25, tzinfo=timezone.utc),
                                  out, ZoneInfo("Asia/Tehran"))
            self.assertEqual(code, 1)
            self.assertFalse(out.exists(), "a failed sync leaves the old file alone")



if __name__ == "__main__":
    unittest.main()
