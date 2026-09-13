"""Turn events from any source into contract rows.

Pure functions only. No I/O, no subprocess, no clock reads. Everything this
module needs is passed in, which is what makes the timezone behaviour
testable without freezing time.

Two sources feed this: Google Calendar resources through `normalize_all`, and
iCalendar occurrences -- CalDAV, so any mail server that speaks it --
through `normalize_occurrences`. Both funnel into `rows_for_occurrence`, so
the row shape cannot drift between them: there is one place that decides what
a row looks like, and it is the same one for both.
"""

import re
from datetime import date, datetime, time, timedelta

NO_TITLE = "(no title)"


def _https_only(value):
    """Keep a URL only if it is https.

    Meeting links come from whoever sent the invitation, not from the user, so
    anything else is dropped rather than handed to the widget to launch.
    """
    text = str(value or "").strip()
    if not text.startswith("https://"):
        return ""
    # Must match Model.safeUrl exactly. When the widget is stricter than the
    # sync, a URL is written, then silently refused, and there is nothing to
    # debug: no button, no error.
    if any(char in text for char in ' \t\n"\'<>'):
        return ""
    return text


def _meeting_url(gevent):
    """The video link for an event, preferring the one Google resolves itself."""
    direct = _https_only(gevent.get("hangoutLink"))
    if direct:
        return direct

    conference = gevent.get("conferenceData") or {}
    for entry in conference.get("entryPoints") or []:
        if entry.get("entryPointType") == "video":
            found = _https_only(entry.get("uri"))
            if found:
                return found
    return ""


def _response_status(gevent):
    """The user's own answer to the invitation, blank when not invited.

    Google marks the user's own row in `attendees` with self: true. An event
    the user created alone has no attendees at all.
    """
    for attendee in gevent.get("attendees") or []:
        if attendee.get("self"):
            return str(attendee.get("responseStatus") or "")
    return ""


def normalize_all(gevents, calendar, tz):
    """Normalize a list of Google events, flattening the per-day rows."""
    rows = []
    for gevent in gevents:
        rows.extend(normalize_event(gevent, calendar, tz))
    return rows


def normalize_event(gevent, calendar, tz):
    """Return one contract row per local day this event covers.

    Rows produced from a single Google event share its id, so consumers must
    key on id plus dateKey, never on id alone.
    """
    if gevent.get("status") == "cancelled":
        return []

    start_node = gevent.get("start") or {}
    if not start_node:
        return []

    end_node = gevent.get("end") or start_node

    try:
        start_dt, all_day = _parse_endpoint(start_node, tz)
        end_dt, _ = _parse_endpoint(end_node, tz)
    except (KeyError, ValueError, TypeError):
        return []

    if all_day:
        # Google's all-day end.date must be strictly after start.date.
        if end_dt.date() <= start_dt.date():
            return []
    elif end_dt < start_dt:
        # A zero-length timed event (end == start) is a legal marker.
        return []

    title = (gevent.get("summary") or "").strip() or NO_TITLE
    location = gevent.get("location") or ""
    start_iso = start_dt.isoformat()
    end_iso = end_dt.isoformat()

    meeting_url = _meeting_url(gevent)
    event_url = _https_only(gevent.get("htmlLink"))
    event_type = str(gevent.get("eventType") or "")
    response_status = _response_status(gevent)

    return rows_for_occurrence(
        event_id=gevent.get("id", ""),
        calendar=calendar,
        start_dt=start_dt,
        end_dt=end_dt,
        all_day=all_day,
        title=title,
        location=location,
        meeting_url=meeting_url,
        event_url=event_url,
        event_type=event_type,
        response_status=response_status,
        start_iso=start_iso,
        end_iso=end_iso,
    )


def rows_for_occurrence(
    *,
    event_id,
    calendar,
    start_dt,
    end_dt,
    all_day,
    title,
    location="",
    meeting_url="",
    event_url="",
    event_type="",
    response_status="",
    start_iso=None,
    end_iso=None,
):
    """One contract row per local day a single occurrence covers.

    The only place a row is built. Rows from one occurrence share an id, so
    consumers key on id plus dateKey and never on id alone.
    """
    return [
        {
            "id": event_id,
            "calendarId": calendar["id"],
            "calendarName": calendar["name"],
            "color": calendar["color"],
            "dateKey": day.isoformat(),
            "start": start_iso if start_iso is not None else start_dt.isoformat(),
            "end": end_iso if end_iso is not None else end_dt.isoformat(),
            "allDay": all_day,
            "title": title,
            "location": location,
            "meetingUrl": meeting_url,
            "eventUrl": event_url,
            "eventType": event_type,
            "responseStatus": response_status,
        }
        for day in _covered_days(start_dt, end_dt, all_day)
    ]


def _parse_endpoint(node, tz):
    """Return (aware datetime in tz, is_all_day) for a Google start/end node."""
    if "date" in node:
        parsed = date.fromisoformat(node["date"])
        return datetime(parsed.year, parsed.month, parsed.day, tzinfo=tz), True
    parsed_dt = datetime.fromisoformat(node["dateTime"])
    if parsed_dt.tzinfo is None:
        # A naive dateTime has no offset. Guessing the system timezone
        # would make output depend on the machine running this code, so
        # treat it as unusable instead.
        raise ValueError("dateTime has no timezone offset")
    return parsed_dt.astimezone(tz), False


def _covered_days(start_dt, end_dt, all_day):
    """Inclusive list of local dates the event occupies."""
    first = start_dt.date()

    if all_day:
        # Google's all-day end.date is exclusive.
        last = end_dt.date() - timedelta(days=1)
    else:
        last = end_dt.date()
        # Ending exactly at midnight means the event never occupied that day.
        if end_dt.timetz().replace(tzinfo=None) == time(0, 0) and last > first:
            last -= timedelta(days=1)

    if last < first:
        last = first

    days = []
    cursor = first
    while cursor <= last:
        days.append(cursor)
        cursor += timedelta(days=1)
    return days


# ---- The iCalendar side: CalDAV, so any server that speaks the standard.

# iCalendar spells participation status differently from Google. The contract
# speaks Google's vocabulary because that is what shipped first and what the
# widget already reads, so this is where the two meet.
PARTSTAT_TO_RESPONSE = {
    "ACCEPTED": "accepted",
    "DECLINED": "declined",
    "TENTATIVE": "tentative",
    "NEEDS-ACTION": "needsAction",
    "DELEGATED": "needsAction",
}

# A Join button is a promise that clicking it joins a meeting. Any https URL
# in a description would light it up for a link to an agenda, a ticket or a
# newsletter, so only hosts that actually host meetings count.
MEETING_HOSTS = (
    "teams.microsoft.com",
    "teams.live.com",
    "zoom.us",
    "meet.google.com",
    "meet.jit.si",
    "whereby.com",
    "webex.com",
    "gotomeeting.com",
    "bluejeans.com",
    "chime.aws",
    "skype.com",
)

_URL_IN_TEXT = re.compile(r"https://[^\s<>\"'\]\),]+")


def _meeting_url_in(text):
    """The first real conferencing link in a blob of text, or blank."""
    for candidate in _URL_IN_TEXT.findall(str(text or "")):
        url = _https_only(candidate.rstrip(".,;:"))
        if not url:
            continue
        host = url.split("/", 3)[2].lower() if url.count("/") >= 2 else ""
        if any(host == known or host.endswith("." + known) for known in MEETING_HOSTS):
            return url
    return ""


def _ics_response_status(event, account_address):
    """This account's own answer to the invitation, blank when not invited.

    iCalendar has no "this attendee is you" marker the way Google does, so
    the account the sync authenticated as is matched by address. Without a
    match the answer is blank, which reads as "not an invitation" -- better
    than guessing and striking through somebody else's decline.
    """
    address = str(account_address or "").strip().lower()
    if not address:
        return ""
    for attendee in event.get("attendees") or []:
        if attendee.get("address") == address:
            return PARTSTAT_TO_RESPONSE.get(attendee.get("partstat", ""), "")
    return ""


def normalize_occurrences(event, occurrences, calendar, tz, account_address=""):
    """Contract rows for every expanded occurrence of one iCalendar event."""
    if str(event.get("status", "")).upper() == "CANCELLED":
        return []

    all_day = bool(event.get("all_day"))
    duration = event["end"] - event["start"]
    if duration.total_seconds() < 0:
        duration = timedelta(0)
    if all_day and duration.total_seconds() <= 0:
        # DTEND is exclusive, so a one-day event spans exactly one day.
        duration = timedelta(days=1)

    title = str(event.get("title") or "").strip() or NO_TITLE
    location = str(event.get("location") or "")
    uid = str(event.get("uid") or "")

    meeting_url = _meeting_url_in(location) or _meeting_url_in(
        event.get("description")
    )
    event_url = _https_only(event.get("url"))
    response_status = _ics_response_status(event, account_address)

    rows = []
    for start_dt in occurrences:
        local_start = start_dt.astimezone(tz)
        local_end = (start_dt + duration).astimezone(tz)
        rows.extend(
            rows_for_occurrence(
                # Every occurrence of a series carries the same UID, so the id
                # has to name the instant too or a weekly standup collapses
                # into one row that the widget then keys against every day it
                # appears on.
                event_id=f"{uid}#{start_dt.isoformat()}" if event.get("rrule") else uid,
                calendar=calendar,
                start_dt=local_start,
                end_dt=local_end,
                all_day=all_day,
                title=title,
                location="" if location.startswith("https://") else location,
                meeting_url=meeting_url,
                event_url=event_url,
                response_status=response_status,
            )
        )
    return rows
