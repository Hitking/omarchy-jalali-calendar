"""A CalDAV client, for company mail servers and everything else speaking it.

A company mail server is the reason this exists, but nothing here is tied to
one product: CalDAV is a standard, so the same code reaches Nextcloud,
Radicale, Fastmail, Zimbra and iCloud. The server to point it at is normally
the host the account's IMAP and webmail are on. Where a particular server
needed accommodating it is marked, and each of those accommodations is a
tolerance rather than a special case.

Standard library only, like the rest of this package. urllib will not send a
PROPFIND or a REPORT on its own and will not carry a method through a
redirect, so both are done by hand below. Doing them by hand also means the
password is ours to place: it goes to the server the user named and nowhere
else, whatever a redirect or an href asks for.
"""

import base64
import ssl
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import timezone

DAV_NS = "DAV:"
CALDAV_NS = "urn:ietf:params:xml:ns:caldav"
APPLE_NS = "http://apple.com/ns/ical/"

NS = {"d": DAV_NS, "c": CALDAV_NS, "x": APPLE_NS}

# Handed out in order to calendars the server gives no colour for, so two
# calendars are never the same dot. Google's own palette, so a file written
# here and a file written by the Google sync look like the same calendar.
FALLBACK_COLORS = (
    "#9fe1e7", "#f83a22", "#7bd148", "#ffad46", "#fad165",
    "#92e1c0", "#b3dc6c", "#ff7537", "#a4bdfc", "#dbadff",
)

MAX_REDIRECTS = 5


class CalDavError(Exception):
    """Raised for anything that stops the sync: transport, auth or protocol."""


class CalDavOriginError(CalDavError):
    """A request would have carried the password to a different server.

    The password belongs to the server the user typed in. A redirect or an
    href naming another host, another port, or plain http is the server
    asking us to hand it somewhere else, and there is no way to tell a
    misconfigured mail server from a hostile one by looking at the answer.
    So we stop instead of guessing.
    """


class CalDavAuthError(CalDavError):
    """The credentials were refused.

    Its own type because discovery tries several URLs and swallows the
    failures, moving on to the next candidate. A rejected password is not a
    reason to try the next URL -- every one of them will reject it too -- and
    swallowing it ends with "check the URL" printed at somebody whose URL is
    fine and whose password is not.
    """


class CalDav:
    def __init__(self, base_url, username, password, *, verify_tls=True,
                 timeout=30, opener=None):
        if not str(base_url or "").strip():
            raise CalDavError("a server URL is required")
        self.base_url = str(base_url).strip()
        if not self.base_url.startswith(("http://", "https://")):
            self.base_url = "https://" + self.base_url
        self.username = username
        self.password = password
        self.timeout = timeout
        self._allowed_origins = _allowed_origins(self.base_url)

        # Injectable so the tests exercise the real request-building and
        # response-parsing without a server. Everything above this line is
        # what the tests are actually about.
        self._opener = opener or self._build_opener(verify_tls)

    @staticmethod
    def _build_opener(verify_tls):
        context = ssl.create_default_context()
        if not verify_tls:
            # Off by default and never silent: an on-premise mail server with
            # a private CA is a real situation, and the alternative is the
            # user pasting a password into a script that disables it wholesale.
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        return urllib.request.build_opener(urllib.request.HTTPSHandler(context=context))

    def _auth_header(self):
        raw = f"{self.username}:{self.password}".encode("utf-8")
        return "Basic " + base64.b64encode(raw).decode("ascii")

    def request(self, method, url, body=None, depth=None):
        """One WebDAV request, following redirects without losing the method.

        urllib turns a redirected POST into a GET, which for a REPORT means
        the server answers with a web page and the parse fails somewhere far
        away from the cause. Redirects are common here: a bare hostname
        usually redirects to the real DAV root.
        """
        target = url
        self._check_origin(target, url)
        for _ in range(MAX_REDIRECTS):
            headers = {
                "Authorization": self._auth_header(),
                "Content-Type": 'application/xml; charset="utf-8"',
                "User-Agent": "omarchy-jalali-calendar",
            }
            if depth is not None:
                headers["Depth"] = str(depth)

            payload = body.encode("utf-8") if isinstance(body, str) else body
            request = urllib.request.Request(
                target, data=payload, headers=headers, method=method
            )

            try:
                with self._opener.open(request, timeout=self.timeout) as response:
                    return response.status, response.read().decode("utf-8", "replace")
            except urllib.error.HTTPError as error:
                if error.code in (301, 302, 307, 308):
                    location = error.headers.get("Location")
                    if not location:
                        raise CalDavError(f"{error.code} redirect with no Location")
                    moved = urllib.parse.urljoin(target, location)
                    self._check_origin(moved, url)
                    target = moved
                    continue
                if error.code in (401, 403):
                    raise CalDavAuthError(
                        "the server rejected the username or password (401). "
                        "An account with two-factor authentication needs an "
                        "application-specific password, not the account "
                        "password."
                    ) from error
                raise CalDavError(
                    f"{method} {target} failed: {error.code} {error.reason}"
                ) from error
            except urllib.error.URLError as error:
                raise CalDavError(f"cannot reach {target}: {error.reason}") from error
            except ssl.SSLError as error:
                raise CalDavError(f"TLS failed for {target}: {error}") from error

        raise CalDavError(f"too many redirects starting at {url}")

    def _check_origin(self, target, started_at):
        """Refuse to send the password anywhere but the server the user named.

        Checked for the first request as much as for a redirect: an href in
        an answer is server-controlled too, and discovery follows those.
        """
        if _origin(target) in self._allowed_origins:
            return
        scheme, host, port = _origin(self.base_url)
        raise CalDavOriginError(
            f"{started_at} pointed at {target}, which is a different server "
            f"({scheme}://{host}:{port} was the one you gave). The password "
            "is not sent there. If the calendars really live on the other "
            "server, give that address as the server URL."
        )

    def propfind(self, url, body, depth=0):
        status, text = self.request("PROPFIND", url, body=body, depth=depth)
        if status not in (207, 200):
            raise CalDavError(f"PROPFIND {url} returned {status}, expected 207")
        return _parse_xml(text)

    # ---- Discovery.
    #
    # Three hops, each one a standard: the server names the principal, the
    # principal names its calendar home, the home lists the calendars. Asking
    # rather than guessing paths is what makes this work against servers that
    # were never tested against.

    def current_user_principal(self):
        body = _propfind_body("<d:current-user-principal/>")
        for start in self._discovery_roots():
            try:
                tree = self.propfind(start, body, depth=0)
            except (CalDavAuthError, CalDavOriginError):
                raise
            except CalDavError:
                continue
            href = _first_href(tree, "d:current-user-principal")
            if href:
                return urllib.parse.urljoin(start, href)
        raise CalDavError(
            "the server did not name a principal. Check the URL: it should be "
            "the mail server root, for example https://mail.example.com/"
        )

    def _discovery_roots(self):
        """Where to start asking, best first."""
        root = self.base_url if self.base_url.endswith("/") else self.base_url + "/"
        return [
            root,
            urllib.parse.urljoin(root, "/.well-known/caldav"),
            # A vendor path some mail servers publish instead, tried last so
            # a standards-compliant answer always wins over it.
            urllib.parse.urljoin(root, "/caldav.aspx"),
        ]

    def calendar_home(self, principal_url):
        body = _propfind_body("<c:calendar-home-set/>")
        tree = self.propfind(principal_url, body, depth=0)
        href = _first_href(tree, "c:calendar-home-set")
        if not href:
            raise CalDavError(f"{principal_url} did not name a calendar home")
        return urllib.parse.urljoin(principal_url, href)

    def calendars(self):
        """Every readable calendar collection, sorted by name."""
        home = self.calendar_home(self.current_user_principal())
        body = _propfind_body(
            "<d:resourcetype/><d:displayname/>"
            "<x:calendar-color/><c:supported-calendar-component-set/>"
        )
        tree = self.propfind(home, body, depth=1)

        found = []
        for response in tree.findall("d:response", NS):
            href_node = response.find("d:href", NS)
            if href_node is None or not (href_node.text or "").strip():
                continue
            url = urllib.parse.urljoin(home, href_node.text.strip())

            propstat = _ok_propstat(response)
            if propstat is None:
                continue

            resourcetype = propstat.find("d:prop/d:resourcetype", NS)
            if resourcetype is None or resourcetype.find("c:calendar", NS) is None:
                continue

            # A collection that holds only todos is not a calendar to show.
            components = propstat.find(
                "d:prop/c:supported-calendar-component-set", NS
            )
            if components is not None:
                names = {
                    (node.get("name") or "").upper()
                    for node in components.findall("c:comp", NS)
                }
                if names and "VEVENT" not in names:
                    continue

            name_node = propstat.find("d:prop/d:displayname", NS)
            name = (name_node.text or "").strip() if name_node is not None else ""

            color_node = propstat.find("d:prop/x:calendar-color", NS)
            color = _normalize_color(color_node.text if color_node is not None else "")

            found.append(
                {
                    "id": url,
                    "name": name or _name_from_url(url),
                    "color": color,
                    "url": url,
                }
            )

        found.sort(key=lambda entry: entry["name"].lower())
        for index, entry in enumerate(found):
            if not entry["color"]:
                entry["color"] = FALLBACK_COLORS[index % len(FALLBACK_COLORS)]
        return found

    def events(self, calendar_url, time_min, time_max):
        """The raw iCalendar text of every event overlapping the window."""
        body = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            f'<c:calendar-query xmlns:d="{DAV_NS}" xmlns:c="{CALDAV_NS}">\n'
            "  <d:prop><d:getetag/><c:calendar-data/></d:prop>\n"
            "  <c:filter>\n"
            '    <c:comp-filter name="VCALENDAR">\n'
            '      <c:comp-filter name="VEVENT">\n'
            f'        <c:time-range start="{_dav_time(time_min)}" '
            f'end="{_dav_time(time_max)}"/>\n'
            "      </c:comp-filter>\n"
            "    </c:comp-filter>\n"
            "  </c:filter>\n"
            "</c:calendar-query>\n"
        )

        status, text = self.request("REPORT", calendar_url, body=body, depth=1)
        if status not in (207, 200):
            raise CalDavError(f"REPORT {calendar_url} returned {status}, expected 207")

        tree = _parse_xml(text)
        objects = []
        for response in tree.findall("d:response", NS):
            propstat = _ok_propstat(response)
            if propstat is None:
                continue
            data = propstat.find("d:prop/c:calendar-data", NS)
            if data is not None and (data.text or "").strip():
                objects.append(data.text)
        return objects

    def check(self):
        """Prove the credentials and the URL work before anything else runs."""
        self.current_user_principal()
        return True


# ---- Where the password may go.


DEFAULT_PORTS = {"http": 80, "https": 443}


def _origin(url):
    """Scheme, host and port, spelled one way so two URLs compare equal.

    https://mail.example.com/ and https://MAIL.example.com:443/dav/ are the
    same server; https://mail.example.com/ and http://mail.example.com/ are
    not, because the second one puts the password on the wire in the clear.
    """
    parts = urllib.parse.urlsplit(url)
    scheme = (parts.scheme or "").lower()
    host = (parts.hostname or "").lower()
    try:
        port = parts.port
    except ValueError:
        # An unparseable port is not a port we can call equal to ours.
        port = None
    return scheme, host, port or DEFAULT_PORTS.get(scheme)


def _allowed_origins(base_url):
    """The origins a request may carry the password to.

    The one the user gave, plus -- when they gave a plain http URL -- the
    same host over https. A server that answers http by redirecting to its
    own https is the ordinary setup, and taking that hop protects a password
    that was about to go out in the clear anyway. Every other change of
    scheme, host or port is a different server and gets nothing.
    """
    origin = _origin(base_url)
    scheme, host, port = origin
    if scheme == "http" and port == DEFAULT_PORTS["http"]:
        return frozenset({origin, ("https", host, DEFAULT_PORTS["https"])})
    return frozenset({origin})


# ---- XML helpers.


def _propfind_body(props):
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<d:propfind xmlns:d="{DAV_NS}" xmlns:c="{CALDAV_NS}" xmlns:x="{APPLE_NS}">\n'
        f"  <d:prop>{props}</d:prop>\n"
        "</d:propfind>\n"
    )


def _parse_xml(text):
    try:
        return ET.fromstring(text)
    except ET.ParseError as error:
        raise CalDavError(f"the server did not return XML: {error}") from error


def _ok_propstat(response):
    """The propstat block carrying a 2xx status, or None.

    A multistatus response reports found and not-found properties in separate
    propstat blocks. Reading the first one blindly picks up the 404 block on
    servers that list it first, and every property then reads as absent.
    """
    blocks = response.findall("d:propstat", NS)
    for block in blocks:
        status = block.find("d:status", NS)
        if status is not None and " 2" in (status.text or ""):
            return block
    return blocks[0] if len(blocks) == 1 else None


def _first_href(tree, prop_path):
    for response in tree.findall("d:response", NS):
        propstat = _ok_propstat(response)
        if propstat is None:
            continue
        node = propstat.find(f"d:prop/{prop_path}", NS)
        if node is None:
            continue
        href = node.find("d:href", NS)
        if href is not None and (href.text or "").strip():
            return href.text.strip()
    return ""


def _normalize_color(value):
    """CalDAV colours arrive as #rrggbb or #rrggbbaa; the contract wants six."""
    text = str(value or "").strip()
    if not text.startswith("#"):
        return ""
    digits = text[1:]
    if len(digits) in (6, 8) and all(c in "0123456789abcdefABCDEF" for c in digits):
        return "#" + digits[:6].lower()
    return ""


def _name_from_url(url):
    path = urllib.parse.urlparse(url).path.rstrip("/")
    return urllib.parse.unquote(path.rsplit("/", 1)[-1]) or "Calendar"


def _dav_time(value):
    """CalDAV time-range bounds are UTC, in basic format, always suffixed Z."""
    return value.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
