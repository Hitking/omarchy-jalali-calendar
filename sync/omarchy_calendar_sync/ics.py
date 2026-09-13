"""A small iCalendar reader: RFC 5545 in, occurrences out.

Enough of the standard to render somebody's calendar, and no more. Written
against the standard library alone, like the rest of this package, because a
systemd user timer that pulls in a dependency tree is a timer that breaks on
a Python upgrade nobody connected to their calendar going quiet.

Two things it deliberately does not do:

- It does not implement every recurrence rule. FREQ, INTERVAL, COUNT, UNTIL,
  BYDAY, BYMONTHDAY, BYMONTH and BYSETPOS cover what real invitations use;
  anything past that is expanded as if the unsupported part were absent,
  which shows a few days too many rather than losing a series entirely.
- It does not interpret VTIMEZONE definitions. A TZID is resolved through
  zoneinfo, with a table for the Windows zone names Exchange-lineage servers
  emit. An unresolvable one falls back to the local zone rather than failing.
"""

import re
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

# Exchange, and every server that grew up speaking to it, writes Windows
# zone names where the standard asks for IANA ones.
# Only the zones a person is plausibly in; anything missing falls back to the
# local zone, which is right for the overwhelmingly common case of a calendar
# kept in the timezone its owner lives in.
WINDOWS_TIMEZONES = {
    "Iran Standard Time": "Asia/Tehran",
    "Arabian Standard Time": "Asia/Dubai",
    "Arab Standard Time": "Asia/Riyadh",
    "Turkey Standard Time": "Europe/Istanbul",
    "GMT Standard Time": "Europe/London",
    "W. Europe Standard Time": "Europe/Berlin",
    "Central Europe Standard Time": "Europe/Budapest",
    "Central European Standard Time": "Europe/Warsaw",
    "Romance Standard Time": "Europe/Paris",
    "E. Europe Standard Time": "Europe/Chisinau",
    "FLE Standard Time": "Europe/Kiev",
    "Russian Standard Time": "Europe/Moscow",
    "India Standard Time": "Asia/Kolkata",
    "China Standard Time": "Asia/Shanghai",
    "Tokyo Standard Time": "Asia/Tokyo",
    "Korea Standard Time": "Asia/Seoul",
    "Singapore Standard Time": "Asia/Singapore",
    "AUS Eastern Standard Time": "Australia/Sydney",
    "Eastern Standard Time": "America/New_York",
    "Central Standard Time": "America/Chicago",
    "Mountain Standard Time": "America/Denver",
    "Pacific Standard Time": "America/Los_Angeles",
    "UTC": "UTC",
}

WEEKDAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}

# A runaway rule -- one with no COUNT, no UNTIL and a window that somehow got
# very wide -- must not spin forever inside a timer.
MAX_OCCURRENCES = 2000


class IcsError(Exception):
    """Raised when a calendar object cannot be read at all."""


# ---- Lexing.


def unfold(text):
    """Join continuation lines. A line starting with space or tab continues."""
    out = []
    for raw in str(text).replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and out:
            out[-1] += raw[1:]
        else:
            out.append(raw)
    return out


def _unescape(value):
    out = []
    index = 0
    while index < len(value):
        char = value[index]
        if char == "\\" and index + 1 < len(value):
            nxt = value[index + 1]
            out.append({"n": "\n", "N": "\n"}.get(nxt, nxt))
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def parse_line(line):
    """Split "NAME;PARAM=v:value" into (name, params dict, value)."""
    head, _, value = line.partition(":")
    if not _:
        return None

    parts = []
    current = ""
    quoted = False
    for char in head:
        if char == '"':
            quoted = not quoted
            continue
        if char == ";" and not quoted:
            parts.append(current)
            current = ""
            continue
        current += char
    parts.append(current)

    name = parts[0].strip().upper()
    params = {}
    for chunk in parts[1:]:
        key, _, val = chunk.partition("=")
        if key:
            params[key.strip().upper()] = val.strip()
    return name, params, _unescape(value)


def parse_components(text, wanted="VEVENT"):
    """Return each wanted component as a list of (name, params, value)."""
    components = []
    current = None
    depth = 0

    for line in unfold(text):
        parsed = parse_line(line)
        if parsed is None:
            continue
        name, _, value = parsed

        if name == "BEGIN" and value.upper() == wanted:
            # Nested components of the same type do not occur, but a guard
            # costs nothing and a malformed feed should not corrupt state.
            if depth == 0:
                current = []
            depth += 1
            continue
        if name == "END" and value.upper() == wanted:
            depth -= 1
            if depth == 0 and current is not None:
                components.append(current)
                current = None
            continue
        if current is not None:
            current.append(parsed)

    return components


# ---- Values.


def resolve_timezone(tzid, fallback):
    """Best effort TZID lookup: IANA first, then the Windows aliases."""
    name = str(tzid or "").strip()
    if not name:
        return fallback
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        pass
    mapped = WINDOWS_TIMEZONES.get(name)
    if mapped:
        try:
            return ZoneInfo(mapped)
        except (ZoneInfoNotFoundError, ValueError):
            pass
    return fallback


def parse_datetime(value, params, local_tz):
    """Return (datetime, is_all_day). All-day values carry no useful time."""
    text = str(value or "").strip()
    if not text:
        raise ValueError("empty date value")

    if params.get("VALUE", "").upper() == "DATE" or (
        len(text) == 8 and text.isdigit()
    ):
        parsed = datetime.strptime(text[:8], "%Y%m%d")
        return parsed.replace(tzinfo=local_tz), True

    if text.endswith("Z"):
        parsed = datetime.strptime(text[:15], "%Y%m%dT%H%M%S")
        return parsed.replace(tzinfo=ZoneInfo("UTC")), False

    parsed = datetime.strptime(text[:15], "%Y%m%dT%H%M%S")
    return parsed.replace(tzinfo=resolve_timezone(params.get("TZID"), local_tz)), False


_DURATION = re.compile(
    r"^(?P<sign>[+-])?P(?:(?P<weeks>\d+)W)?(?:(?P<days>\d+)D)?"
    r"(?:T(?:(?P<hours>\d+)H)?(?:(?P<minutes>\d+)M)?(?:(?P<seconds>\d+)S)?)?$"
)


def parse_duration(value):
    match = _DURATION.match(str(value or "").strip())
    if not match:
        raise ValueError(f"bad duration: {value!r}")
    parts = {k: int(v) for k, v in match.groupdict(default="0").items() if k != "sign"}
    delta = timedelta(
        weeks=parts["weeks"],
        days=parts["days"],
        hours=parts["hours"],
        minutes=parts["minutes"],
        seconds=parts["seconds"],
    )
    return -delta if match.group("sign") == "-" else delta


def parse_rrule(value):
    """RRULE into a dict. Unknown parts are kept but ignored by the expander."""
    rule = {}
    for chunk in str(value or "").split(";"):
        key, _, val = chunk.partition("=")
        if key:
            rule[key.strip().upper()] = val.strip()
    return rule


# ---- Events.


def read_event(properties, local_tz):
    """Turn one VEVENT's properties into a plain dict, or None if unusable."""
    fields = {}
    exdates = []
    rdates = []

    for name, params, value in properties:
        if name == "DTSTART":
            fields["start"], fields["all_day"] = parse_datetime(value, params, local_tz)
        elif name == "DTEND":
            fields["end"], _ = parse_datetime(value, params, local_tz)
        elif name == "DURATION":
            fields["duration"] = parse_duration(value)
        elif name == "RRULE":
            fields["rrule"] = parse_rrule(value)
        elif name == "RECURRENCE-ID":
            fields["recurrence_id"], _ = parse_datetime(value, params, local_tz)
        elif name == "EXDATE":
            for piece in value.split(","):
                try:
                    parsed, _ = parse_datetime(piece, params, local_tz)
                    exdates.append(parsed)
                except ValueError:
                    continue
        elif name == "RDATE":
            for piece in value.split(","):
                try:
                    parsed, _ = parse_datetime(piece, params, local_tz)
                    rdates.append(parsed)
                except ValueError:
                    continue
        elif name == "UID":
            fields["uid"] = value
        elif name == "SUMMARY":
            fields["title"] = value
        elif name == "LOCATION":
            fields["location"] = value
        elif name == "STATUS":
            fields["status"] = value.upper()
        elif name == "URL":
            fields["url"] = value
        elif name == "DESCRIPTION":
            fields["description"] = value
        elif name == "ORGANIZER":
            fields["organizer"] = value
        elif name == "ATTENDEE":
            # PARTSTAT on the attendee row belonging to this account is how a
            # declined invitation is recognised. Which row that is cannot be
            # known here, so every row is kept and the caller matches by
            # address against the account it authenticated as.
            fields.setdefault("attendees", []).append(
                {
                    "address": _address(value),
                    "partstat": params.get("PARTSTAT", "").upper(),
                }
            )

    if "start" not in fields:
        return None

    fields["exdates"] = exdates
    fields["rdates"] = rdates

    if "end" not in fields:
        if "duration" in fields:
            fields["end"] = fields["start"] + fields["duration"]
        elif fields.get("all_day"):
            # An all-day event with no end covers one day, and DTEND is
            # exclusive, so tomorrow is the right answer.
            fields["end"] = fields["start"] + timedelta(days=1)
        else:
            fields["end"] = fields["start"]

    return fields


def _address(value):
    """The mail address out of a MAILTO: value, lowercased."""
    text = str(value or "").strip()
    if text.upper().startswith("MAILTO:"):
        text = text[7:]
    return text.strip().lower()


# ---- Recurrence.


def _nth_weekday(year, month, weekday, ordinal):
    """The `ordinal`-th `weekday` of a month; negative counts from the end."""
    if ordinal > 0:
        first = date(year, month, 1)
        offset = (weekday - first.weekday()) % 7
        day = 1 + offset + (ordinal - 1) * 7
    else:
        if month == 12:
            last = date(year, 12, 31)
        else:
            last = date(year, month + 1, 1) - timedelta(days=1)
        offset = (last.weekday() - weekday) % 7
        day = last.day - offset + (ordinal + 1) * 7

    try:
        return date(year, month, day)
    except ValueError:
        return None


def _parse_byday(rule):
    """BYDAY into [(ordinal or None, weekday index)]."""
    out = []
    for token in str(rule.get("BYDAY", "")).split(","):
        token = token.strip().upper()
        if not token:
            continue
        match = re.match(r"^([+-]?\d+)?([A-Z]{2})$", token)
        if not match or match.group(2) not in WEEKDAYS:
            continue
        ordinal = int(match.group(1)) if match.group(1) else None
        out.append((ordinal, WEEKDAYS[match.group(2)]))
    return out


def _add_months(anchor, months):
    total = anchor.year * 12 + (anchor.month - 1) + months
    year, month = divmod(total, 12)
    month += 1
    day = min(anchor.day, [31, 29 if _leap(year) else 28, 31, 30, 31, 30,
                           31, 31, 30, 31, 30, 31][month - 1])
    return date(year, month, day)


def _leap(year):
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


def expand(event, window_start, window_end):
    """Every start instant of `event` inside the window, earliest first.

    A non-recurring event yields its own start when that falls in the window.
    The window is what bounds the work: a rule with no COUNT and no UNTIL is
    infinite, and the only reason walking it terminates is that nothing past
    `window_end` is wanted.
    """
    start = event["start"]
    rule = event.get("rrule")
    excluded = {_instant(value) for value in event.get("exdates", [])}

    starts = []

    def keep(candidate):
        if _instant(candidate) in excluded:
            return
        if candidate > window_end or candidate < window_start:
            return
        starts.append(candidate)

    if not rule:
        keep(start)
    else:
        for candidate in _walk(start, rule, window_end):
            keep(candidate)

    for extra in event.get("rdates", []):
        keep(extra)

    return sorted(set(starts))


def _instant(value):
    """A comparable identity for an occurrence, immune to timezone spelling."""
    return value.astimezone(ZoneInfo("UTC")).replace(microsecond=0)


def _walk(start, rule, window_end):
    """Yield candidate starts for a rule, stopping at COUNT, UNTIL or window."""
    freq = str(rule.get("FREQ", "")).upper()
    if freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY"):
        # An unsupported frequency degrades to the single original start
        # rather than dropping the event.
        yield start
        return

    try:
        interval = max(1, int(rule.get("INTERVAL", 1)))
    except (TypeError, ValueError):
        interval = 1

    count = None
    if rule.get("COUNT"):
        try:
            count = max(0, int(rule["COUNT"]))
        except (TypeError, ValueError):
            count = None

    until = None
    if rule.get("UNTIL"):
        try:
            until, _ = parse_datetime(rule["UNTIL"], {}, start.tzinfo)
        except ValueError:
            until = None

    limit = until if until is not None and until < window_end else window_end
    byday = _parse_byday(rule)
    bymonth = _int_list(rule.get("BYMONTH"))
    bymonthday = _int_list(rule.get("BYMONTHDAY"))

    emitted = 0
    period = 0
    anchor = start.date()

    while period < MAX_OCCURRENCES:
        days = _period_days(freq, anchor, period, interval, byday, bymonthday)
        if days is None:
            return

        for day in sorted(days):
            if bymonth and day.month not in bymonth:
                continue
            candidate = start.replace(year=day.year, month=day.month, day=day.day)
            if candidate < start:
                continue
            if candidate > limit:
                return
            yield candidate
            emitted += 1
            if count is not None and emitted >= count:
                return

        period += 1
        # A period that has already run past the limit with nothing to emit
        # means the walk is over; without this a BYMONTH rule would spin
        # through eleven empty months for every one it wants.
        if _period_start(freq, anchor, period, interval) > limit.date():
            return


def _period_start(freq, anchor, period, interval):
    if freq == "DAILY":
        return anchor + timedelta(days=period * interval)
    if freq == "WEEKLY":
        return anchor + timedelta(weeks=period * interval)
    if freq == "MONTHLY":
        return _add_months(anchor, period * interval)
    return _add_months(anchor, period * interval * 12)


def _period_days(freq, anchor, period, interval, byday, bymonthday):
    """The candidate days inside one period of the rule."""
    base = _period_start(freq, anchor, period, interval)

    if freq == "DAILY":
        return [base]

    if freq == "WEEKLY":
        if not byday:
            return [base]
        monday = base - timedelta(days=base.weekday())
        return [monday + timedelta(days=weekday) for _, weekday in byday]

    # MONTHLY and YEARLY share their day selection: an ordinal weekday, a set
    # of month days, or failing both, the day the series started on.
    days = []
    if byday:
        for ordinal, weekday in byday:
            if ordinal is None:
                cursor = date(base.year, base.month, 1)
                while cursor.month == base.month:
                    if cursor.weekday() == weekday:
                        days.append(cursor)
                    cursor += timedelta(days=1)
            else:
                found = _nth_weekday(base.year, base.month, weekday, ordinal)
                if found:
                    days.append(found)
    if bymonthday:
        for day_number in bymonthday:
            try:
                if day_number > 0:
                    days.append(date(base.year, base.month, day_number))
                else:
                    following = _add_months(date(base.year, base.month, 1), 1)
                    last = following - timedelta(days=1)
                    days.append(last + timedelta(days=day_number + 1))
            except ValueError:
                continue
    return days or [base]


def _int_list(value):
    out = []
    for chunk in str(value or "").split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        try:
            out.append(int(chunk))
        except ValueError:
            continue
    return out


def read_calendar(text, local_tz):
    """Every VEVENT in an iCalendar object, as dicts. Unusable ones dropped."""
    events = []
    for properties in parse_components(text, "VEVENT"):
        try:
            event = read_event(properties, local_tz)
        except (ValueError, TypeError):
            continue
        if event is not None:
            events.append(event)
    return events
