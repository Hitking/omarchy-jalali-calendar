"""The iCalendar reader: parsing, timezones, recurrence, and the rows out."""

import unittest
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from omarchy_calendar_sync import ics, normalize

TEHRAN = ZoneInfo("Asia/Tehran")
UTC = ZoneInfo("UTC")

CALENDAR = {"id": "https://mail.example.com/cal/", "name": "Work", "color": "#f83a22"}


def wrap(*lines):
    return "\r\n".join(("BEGIN:VCALENDAR",) + lines + ("END:VCALENDAR",))


def event(*lines):
    return wrap("BEGIN:VEVENT", *lines, "END:VEVENT")


class UnfoldTests(unittest.TestCase):
    def test_continuation_lines_rejoin(self):
        text = "SUMMARY:A very long\r\n  title that wrapped"
        self.assertEqual(ics.unfold(text), ["SUMMARY:A very long title that wrapped"])

    def test_tab_is_also_a_continuation(self):
        self.assertEqual(ics.unfold("A:one\r\n\ttwo"), ["A:onetwo"])

    def test_bare_newlines_are_tolerated(self):
        # Not legal iCalendar, but plenty of servers emit it.
        self.assertEqual(ics.unfold("A:1\nB:2"), ["A:1", "B:2"])


class ParseLineTests(unittest.TestCase):
    def test_parameters_are_read(self):
        name, params, value = ics.parse_line("DTSTART;TZID=Asia/Tehran:20260830T090000")
        self.assertEqual(name, "DTSTART")
        self.assertEqual(params, {"TZID": "Asia/Tehran"})
        self.assertEqual(value, "20260830T090000")

    def test_a_quoted_parameter_may_contain_a_semicolon(self):
        name, params, _ = ics.parse_line('DTSTART;TZID="Foo;Bar":20260830T090000')
        self.assertEqual(params["TZID"], "Foo;Bar")

    def test_escapes_are_undone_in_the_value(self):
        _, _, value = ics.parse_line(r"SUMMARY:Tea\, cake\nand talk")
        self.assertEqual(value, "Tea, cake\nand talk")

    def test_a_line_without_a_colon_is_not_a_property(self):
        self.assertIsNone(ics.parse_line("GARBAGE"))


class TimezoneTests(unittest.TestCase):
    def test_an_iana_name_resolves(self):
        self.assertEqual(ics.resolve_timezone("Asia/Tehran", UTC), TEHRAN)

    # Exchange-lineage servers, SmarterMail among them, write Windows zone
    # names where the standard asks for IANA ones.
    def test_a_windows_name_resolves_through_the_table(self):
        self.assertEqual(ics.resolve_timezone("Iran Standard Time", UTC), TEHRAN)

    def test_an_unknown_zone_falls_back_rather_than_failing(self):
        self.assertEqual(ics.resolve_timezone("Middle Earth Time", TEHRAN), TEHRAN)
        self.assertEqual(ics.resolve_timezone("", TEHRAN), TEHRAN)

    def test_a_utc_stamp_is_read_as_utc(self):
        parsed, all_day = ics.parse_datetime("20260830T093000Z", {}, TEHRAN)
        self.assertFalse(all_day)
        self.assertEqual(parsed.utcoffset(), timedelta(0))

    def test_a_date_value_is_all_day_in_the_local_zone(self):
        parsed, all_day = ics.parse_datetime("20260830", {"VALUE": "DATE"}, TEHRAN)
        self.assertTrue(all_day)
        self.assertEqual((parsed.year, parsed.month, parsed.day), (2026, 8, 30))
        self.assertEqual(parsed.tzinfo, TEHRAN)

    def test_an_eight_digit_value_is_a_date_even_unlabelled(self):
        _, all_day = ics.parse_datetime("20260830", {}, TEHRAN)
        self.assertTrue(all_day)


class DurationTests(unittest.TestCase):
    def test_the_forms_that_occur(self):
        self.assertEqual(ics.parse_duration("PT1H"), timedelta(hours=1))
        self.assertEqual(ics.parse_duration("PT30M"), timedelta(minutes=30))
        self.assertEqual(ics.parse_duration("P1D"), timedelta(days=1))
        self.assertEqual(ics.parse_duration("P2W"), timedelta(weeks=2))
        self.assertEqual(ics.parse_duration("PT1H30M"), timedelta(hours=1, minutes=30))
        self.assertEqual(ics.parse_duration("-PT15M"), -timedelta(minutes=15))

    def test_nonsense_raises(self):
        with self.assertRaises(ValueError):
            ics.parse_duration("soon")


class ReadEventTests(unittest.TestCase):
    def read_one(self, text):
        events = ics.read_calendar(text, TEHRAN)
        self.assertEqual(len(events), 1)
        return events[0]

    def test_the_basics_come_through(self):
        found = self.read_one(event(
            "UID:abc@example.com",
            "SUMMARY:Standup",
            "LOCATION:Room 2",
            "DTSTART;TZID=Asia/Tehran:20260830T090000",
            "DTEND;TZID=Asia/Tehran:20260830T091500",
        ))
        self.assertEqual(found["uid"], "abc@example.com")
        self.assertEqual(found["title"], "Standup")
        self.assertEqual(found["location"], "Room 2")
        self.assertFalse(found["all_day"])
        self.assertEqual(found["end"] - found["start"], timedelta(minutes=15))

    def test_duration_stands_in_for_a_missing_end(self):
        found = self.read_one(event(
            "UID:a", "SUMMARY:X",
            "DTSTART;TZID=Asia/Tehran:20260830T090000",
            "DURATION:PT45M",
        ))
        self.assertEqual(found["end"] - found["start"], timedelta(minutes=45))

    def test_an_all_day_event_with_no_end_covers_one_day(self):
        found = self.read_one(event(
            "UID:a", "SUMMARY:Holiday", "DTSTART;VALUE=DATE:20260830",
        ))
        self.assertTrue(found["all_day"])
        self.assertEqual(found["end"] - found["start"], timedelta(days=1))

    def test_an_event_with_no_start_is_dropped_rather_than_guessed(self):
        self.assertEqual(ics.read_calendar(event("UID:a", "SUMMARY:X"), TEHRAN), [])

    def test_attendees_are_kept_with_their_status(self):
        found = self.read_one(event(
            "UID:a", "SUMMARY:X", "DTSTART;TZID=Asia/Tehran:20260830T090000",
            "ATTENDEE;PARTSTAT=DECLINED:mailto:Masoud@Example.COM",
            "ATTENDEE;PARTSTAT=ACCEPTED:mailto:other@example.com",
        ))
        self.assertEqual(found["attendees"][0],
                         {"address": "masoud@example.com", "partstat": "DECLINED"})

    def test_several_events_in_one_object(self):
        text = wrap(
            "BEGIN:VEVENT", "UID:a", "SUMMARY:One",
            "DTSTART;TZID=Asia/Tehran:20260830T090000", "END:VEVENT",
            "BEGIN:VEVENT", "UID:b", "SUMMARY:Two",
            "DTSTART;TZID=Asia/Tehran:20260831T090000", "END:VEVENT",
        )
        self.assertEqual([e["title"] for e in ics.read_calendar(text, TEHRAN)],
                         ["One", "Two"])


class RecurrenceTests(unittest.TestCase):
    WINDOW_START = datetime(2026, 8, 1, tzinfo=TEHRAN)
    WINDOW_END = datetime(2026, 10, 1, tzinfo=TEHRAN)

    def expand(self, *lines):
        found = ics.read_calendar(event("UID:a", "SUMMARY:X", *lines), TEHRAN)[0]
        return [d.astimezone(TEHRAN).date().isoformat()
                for d in ics.expand(found, self.WINDOW_START, self.WINDOW_END)]

    def test_a_single_event_yields_itself(self):
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260830T090000"),
            ["2026-08-30"])

    def test_an_event_outside_the_window_yields_nothing(self):
        self.assertEqual(self.expand("DTSTART;TZID=Asia/Tehran:20250830T090000"), [])

    def test_daily_with_a_count(self):
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260830T090000",
                        "RRULE:FREQ=DAILY;COUNT=3"),
            ["2026-08-30", "2026-08-31", "2026-09-01"])

    def test_daily_with_an_interval(self):
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260830T090000",
                        "RRULE:FREQ=DAILY;INTERVAL=3;COUNT=3"),
            ["2026-08-30", "2026-09-02", "2026-09-05"])

    def test_weekly_on_named_days(self):
        # The Iranian working week: Sunday, Tuesday, Thursday.
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260830T090000",
                        "RRULE:FREQ=WEEKLY;BYDAY=SU,TU,TH;COUNT=4"),
            ["2026-08-30", "2026-09-01", "2026-09-03", "2026-09-06"])

    def test_until_stops_the_series(self):
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260830T090000",
                        "RRULE:FREQ=DAILY;UNTIL=20260901T235959Z"),
            ["2026-08-30", "2026-08-31", "2026-09-01"])

    def test_monthly_on_an_ordinal_weekday(self):
        # Second Tuesday of the month.
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260811T090000",
                        "RRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=2"),
            ["2026-08-11", "2026-09-08"])

    def test_monthly_on_the_last_weekday(self):
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260831T090000",
                        "RRULE:FREQ=MONTHLY;BYDAY=-1MO;COUNT=2"),
            ["2026-08-31", "2026-09-28"])

    def test_monthly_on_a_month_day(self):
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260815T090000",
                        "RRULE:FREQ=MONTHLY;BYMONTHDAY=15;COUNT=2"),
            ["2026-08-15", "2026-09-15"])

    def test_exdate_removes_one_occurrence(self):
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260830T090000",
                        "RRULE:FREQ=DAILY;COUNT=3",
                        "EXDATE;TZID=Asia/Tehran:20260831T090000"),
            ["2026-08-30", "2026-09-01"])

    def test_rdate_adds_one(self):
        self.assertIn("2026-09-15", self.expand(
            "DTSTART;TZID=Asia/Tehran:20260830T090000",
            "RDATE;TZID=Asia/Tehran:20260915T090000"))

    # A rule this reader does not implement must not swallow the event: showing
    # one occurrence where there should be several is a smaller failure than
    # the series vanishing with no trace.
    def test_an_unsupported_frequency_degrades_to_the_original_start(self):
        self.assertEqual(
            self.expand("DTSTART;TZID=Asia/Tehran:20260830T090000",
                        "RRULE:FREQ=SECONDLY;COUNT=5"),
            ["2026-08-30"])

    # Without a window this would never return.
    def test_an_endless_rule_is_bounded_by_the_window(self):
        days = self.expand("DTSTART;TZID=Asia/Tehran:20260830T090000",
                           "RRULE:FREQ=DAILY")
        self.assertEqual(days[0], "2026-08-30")
        self.assertLessEqual(days[-1], "2026-10-01")
        self.assertLess(len(days), 40)


class NormalizeOccurrenceTests(unittest.TestCase):
    def rows(self, *lines, account=""):
        found = ics.read_calendar(event("UID:a", "SUMMARY:Standup", *lines), TEHRAN)[0]
        occurrences = ics.expand(
            found, datetime(2026, 8, 1, tzinfo=TEHRAN), datetime(2026, 10, 1, tzinfo=TEHRAN)
        )
        return normalize.normalize_occurrences(
            found, occurrences, CALENDAR, TEHRAN, account
        )

    def test_a_row_carries_the_contract_fields(self):
        rows = self.rows("DTSTART;TZID=Asia/Tehran:20260830T090000",
                         "DTEND;TZID=Asia/Tehran:20260830T093000")
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["dateKey"], "2026-08-30")
        self.assertEqual(row["title"], "Standup")
        self.assertEqual(row["calendarName"], "Work")
        self.assertEqual(row["color"], "#f83a22")
        self.assertFalse(row["allDay"])

    # The dateKey is Gregorian and stays Gregorian: it is what the widget
    # files events under, whichever calendar it happens to be displaying.
    def test_a_multi_day_event_becomes_one_row_per_day(self):
        rows = self.rows("DTSTART;TZID=Asia/Tehran:20260830T220000",
                         "DTEND;TZID=Asia/Tehran:20260901T020000")
        self.assertEqual([r["dateKey"] for r in rows],
                         ["2026-08-30", "2026-08-31", "2026-09-01"])
        self.assertEqual(len({r["id"] for r in rows}), 1, "one event, one id")

    def test_every_instance_of_a_series_gets_its_own_id(self):
        rows = self.rows("DTSTART;TZID=Asia/Tehran:20260830T090000",
                         "RRULE:FREQ=DAILY;COUNT=3")
        self.assertEqual(len(rows), 3)
        self.assertEqual(len({r["id"] for r in rows}), 3,
                         "a shared id would collapse the series in the widget")

    def test_a_cancelled_event_produces_nothing(self):
        self.assertEqual(
            self.rows("DTSTART;TZID=Asia/Tehran:20260830T090000", "STATUS:CANCELLED"),
            [])

    def test_an_untitled_event_gets_a_placeholder(self):
        found = ics.read_calendar(
            event("UID:a", "DTSTART;TZID=Asia/Tehran:20260830T090000"), TEHRAN)[0]
        rows = normalize.normalize_occurrences(
            found, [found["start"]], CALENDAR, TEHRAN, "")
        self.assertEqual(rows[0]["title"], normalize.NO_TITLE)

    def test_a_real_conferencing_link_becomes_a_join_button(self):
        rows = self.rows(
            "DTSTART;TZID=Asia/Tehran:20260830T090000",
            "LOCATION:https://teams.microsoft.com/l/meetup-join/abc")
        self.assertEqual(rows[0]["meetingUrl"],
                         "https://teams.microsoft.com/l/meetup-join/abc")
        self.assertEqual(rows[0]["location"], "",
                         "a location that is only a link is not a place")

    # A Join button is a promise that clicking it joins a meeting.
    def test_an_ordinary_link_does_not(self):
        rows = self.rows("DTSTART;TZID=Asia/Tehran:20260830T090000",
                         "DESCRIPTION:Agenda at https://wiki.example.com/standup")
        self.assertEqual(rows[0]["meetingUrl"], "")

    def test_this_accounts_decline_is_recognised_and_no_one_elses(self):
        lines = ("DTSTART;TZID=Asia/Tehran:20260830T090000",
                 "ATTENDEE;PARTSTAT=DECLINED:mailto:masoud@example.com",
                 "ATTENDEE;PARTSTAT=ACCEPTED:mailto:other@example.com")
        self.assertEqual(
            self.rows(*lines, account="masoud@example.com")[0]["responseStatus"],
            "declined")
        self.assertEqual(
            self.rows(*lines, account="nobody@example.com")[0]["responseStatus"],
            "", "an account not on the invitation has not answered it")


if __name__ == "__main__":
    unittest.main()
