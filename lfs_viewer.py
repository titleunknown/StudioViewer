#!/usr/bin/env python3
"""LfS Web Viewer: view a Capture One "Live for Studio" session in a web browser.

Made by Faini Made (https://fainimade.com). Not affiliated with Capture One.
Tested with Capture One 16.7.3 and the Live for Studio iPad app 1.4.2.3.
Needs only Python 3 (no extra packages). See README.md for the user guide.

Capture One's Live for Studio server is a plain-HTTP API on a random port,
advertised over Bonjour. This script finds it, opens its own session, and
serves viewer.html, which browses folders, shows images and follows new
captures. The browser never talks to Capture One directly; this script
relays every call (Capture One sends no CORS headers).

Usage:
    python3 lfs_viewer.py                 # this Mac and your network; prints the addresses
    python3 lfs_viewer.py --local         # this Mac only (http://localhost:8787)
    python3 lfs_viewer.py --port 9000     # another port (the next free one is used if taken)
    python3 lfs_viewer.py --c1 127.0.0.1:49670   # skip auto-discovery
    python3 lfs_viewer.py --session "/path/Session.cosessiondb"   # where to read exposure info
    python3 lfs_viewer.py --no-open       # don't open the browser
    python3 lfs_viewer.py --debug         # print each change message from Capture One
    python3 lfs_viewer.py --tunnel-port 8797   # also listen for a Cloudflare tunnel (see Remote)
    python3 lfs_viewer.py --control --settings PATH   # run by the LfS app (see Control)

Files next to this script:
    viewer.html               the web page (read from disk on each load, so edits need only a reload)
    gate.html                 the "enter the viewing code" page for remote visitors (see Remote)
    settings.json             network access mode, PINs and codes, created on first run (see Access);
                              --settings puts it elsewhere
    Start LfS Viewer.command  double-click launcher for Finder

The viewer's own endpoints (used by viewer.html):
    GET  /                    the page
    GET  /api/state?c=C[&client=K&feed=F]   folder list and images (relays getServerStateForLive).
                              With client and feed (random ids of 8-40 letters, digits, _ or -) it also
                              starts a private change feed: its own Capture One session (see Feeds)
    GET  /api/changes?c=C&feed=F   long-poll for the feed's changes (relays getServerChangesForLive;
                              204 when idle, 410 when the feed is gone: start a new one with /api/state)
    GET  /api/image?c=C&id=V&w=W&h=H&v=T[&l=&t=&r=&b=]   JPEG, optionally a crop (relays getImageForLive,
                              cached; see Pictures). T is the photo's "lfsPicture" token from its record
                              (the viewer adds one to every record in /api/state and /api/changes),
                              optionally followed by "." and more: with the current token, the
                              picture may be kept for good
    GET  /api/exposure        {image uuid: [aperture, shutter s, iso]} from the session database
    GET  /api/latest[?hint=C] {c, id, n}: the newest capture in any shared folder (for Follow)
    GET  /api/counts          {folder id: number of photos}, for the folder list (see FolderCounts)
    GET  /api/ping            {}: the page times it (Connection panel). Image replies carry Server-Timing
                              (c1: Capture One's drawing time, memory: answered from the viewer's cache)
    GET  /api/access          what this device may do: {mode, isOwner, canRate, unlocked, managed, ...}
    POST /api/set?c=C&id=V&prop=rating|tag&value=N   rate or tag (if allowed)
    POST /api/access {mode, pin}   change the network mode (this Mac only, and not with --control)
    POST /api/unlock {pin}    unlock rating on a network device (sets a cookie)
    POST /api/lock            give that back
    POST /api/view {code}     tunnel only: enter the remote viewing code (sets a cookie)
    POST /api/looking {photo} the photo this page shows now, for the LfS app's Viewers panel
    Every POST must carry the header "X-LfS: 1", which blocks cross-site requests.

Remote (--tunnel-port N): a second listener on 127.0.0.1:N for cloudflared, so people outside the
studio can watch through the photographer's own domain. Point the tunnel at http://localhost:N,
never at the main port: cloudflared connects from this Mac, and the main port treats this Mac as
the owner (so it refuses anything carrying Cloudflare's headers). On the tunnel listener:
    - nobody is the owner; a visitor's address is Cloudflare's CF-Connecting-IP header
    - with remote view "code" (the default), every request needs the viewing code first: the page
      is gate.html until it's entered, and the API answers 401. "open" skips this, for when
      Cloudflare Access already guards the hostname.
    - rating follows the same mode as the network (view, PIN, open)
    - besides the per-device limit, wrong codes and PINs from all remote visitors together are
      capped (REMOTE_MAX in REMOTE_WINDOW seconds), since the internet has plenty of addresses

Control (--control): how the LfS menu bar app runs this script. Settings move out of the web page
(POST /api/access is refused, and /api/access no longer shows the PIN or addresses), and:
    stdout  besides the usual messages, events as lines of "@lfs " + one JSON object:
              {"event": "c1", "state": "waiting|connected|lost", "url": ..., "session": name}
              {"event": "listening", "port": P, "requestedPort": R, "local": bool, "urls": {...}, "tunnelPort": T}
                                   (P differs from R when R was in use: the next free one is taken, never T)
              {"event": "addresses", "urls": {...}}     the network addresses changed
              {"event": "tunnel", "port": T or null}    the tunnel port opened or closed
              {"event": "viewers", "total": n, "remote": m}   open pages (remote = through the tunnel)
              {"event": "devices", "devices": [...]}    connected and removed devices (see Devices)
              {"event": "settings", "settings": {...}}  after any change, PINs and codes included
              {"event": "guessing", "wait": s}  too many wrong remote codes; remote unlocks paused
              {"event": "error", "message": ...}   something the app should show (e.g. port in use)
              {"event": "reply", "id": ..., "ok": bool, "error": ...}   answer to a command
              {"event": "status", ...}          everything above at once, answer to "status"
              {"event": "stopped"}
    stdin   commands, one JSON object per line, each answered with a reply (or status) event that
            repeats its optional "id":
              {"cmd": "status"}
              {"cmd": "access", "mode": "view|pin|open", "pin": "1234"}
              {"cmd": "lockout", "maxFails": 5, "seconds": 60}   wrong tries per device, then wait
              {"cmd": "remote", "view": "code|open", "code": "123456"}   code: 6 to 12 digits
              {"cmd": "signout"}   every device's PIN unlock and remote viewing code must be re-entered
              {"cmd": "wording", "operator": "the digi-tech"}   how visitors' pages name you
                                   (default "the photographer"; 1 to 40 characters)
              {"cmd": "tunnel", "port": 8797}   open the tunnel port now ("port": null closes it)
              {"cmd": "block", "device": D}     remove a device: its page is cut off and shows "removed"
              {"cmd": "unblock", "device": D}   let a removed device watch again
              {"cmd": "rating", "device": D, "allow": false}   stop (or allow) rating on one device
              {"cmd": "stop"}
            The script also stops when stdin closes, so it never outlives the app.

Exposure info (aperture, shutter, ISO) isn't part of Live for Studio. It's read, read-only, from
the session's own database (ZIMAGE table in <name>.cosessiondb), matched by image UUID.

Capture One's protocol (observed from the Live for Studio iPad app, protocol 1.1):
    GET /connectToServiceForLive?appVersion=1.4.2.3&protocolVersion=1.1
        -> body is a numeric session ID
    GET /getServerStateForLive?sessionID=S&collectionID=C
        -> JSON: folders (objects[0].kObjectKey_Collections) + images (variants)
    GET /getServerChangesForLive?sessionID=S&collectionID=C
        -> long-poll; returns when something changes, or empty after ~60 s
    GET /getImageForLive?sessionID=S&collectionID=C&id=V&width=W&height=H
            &left=L&top=T&right=R&bottom=B
        -> JPEG fitted to W x H. L/T/R/B crop to that rectangle in full-image
           pixels (all 0 = whole image); R < L gives 404.
    GET /setPropertyForLive?sessionID=S&collectionID=C&objectType=kObjectType_ImageAdjustments
            &objectID=V&propertyID=kImageAdjustmentProperty_Rating&propertyValue=N
        -> sets the rating (0-5); kImageAdjustmentProperty_ColorTag sets the color tag (0-7).
           Other objectType/propertyID names are accepted with HTTP 200 but ignored.
    GET /disconnectFromServiceForLive?sessionID=S
        -> ends the session; a change listener waiting on it returns empty straight away.
    An invalid or expired session answers 403.
    Each change is delivered to only ONE listener of a session, so every browser (and every folder
    it opens) listens on a session of its own; see Feeds.
"""
import argparse
import collections
import hashlib
import html
import hmac
import http.cookies
import os
import json
import re
import secrets
import signal
import sqlite3
import subprocess
import sys
import queue
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_VERSION = "1.4.2.3"
PROTOCOL_VERSION = "1.1"
USER_AGENT = f"Live/{APP_VERSION} LfSWebViewer"
LONG_POLL_TIMEOUT = 75  # Capture One answers an idle long-poll after ~60 s
DEBUG = False  # --debug prints each change message from Capture One
HERE = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(HERE, "viewer.html")
GATE = os.path.join(HERE, "gate.html")  # remote visitors see this until they enter the viewing code
SETTINGS = os.path.join(HERE, "settings.json")  # network access mode and PIN (see Access); --settings changes it
CONTROL = False  # --control: run by the LfS app (see Control)
# Set by the app's "stop" or by stdin closing (from the command thread). Not a simulated Ctrl-C: a
# process started in the background ignores SIGINT, and then _thread.interrupt_main() silently does
# nothing. The main thread polls it with is_set() and short sleeps rather than waiting on it: see
# _terminate for why nothing may wait on a lock the SIGTERM handler could need.
STOP = threading.Event()


def _terminate(*_):
    """SIGTERM (the app's fallback Stop, or a logout): stop like Ctrl-C does. The handler runs on
    the main thread, between whatever it was doing, so it must take no lock: STOP.set() would wait
    for the Event's own lock, which the main thread may be holding inside STOP.wait(), and the
    viewer would hang for good (seen in testing on 2026-10-21)."""
    raise KeyboardInterrupt


def wait_for_stop(seconds=None):
    """Sleep until STOP is set (or for at most `seconds`); return whether it was set."""
    end = None if seconds is None else time.time() + seconds
    while not STOP.is_set():
        if end is not None and time.time() >= end:
            return False
        time.sleep(0.25)
    return True
HIDDEN_FOLDER = re.compile(r"^(Cache|Proxies|Thumbnails|Settings\d*)$")  # Capture One's own folders
ACCESS_LABELS = {
    "view": "other devices can view only",
    "pin": "other devices can rate after entering the PIN",
    "open": "anyone on the network can rate",
}
# What the page may change: name -> (Capture One property, highest value).
SETTABLE = {
    "rating": ("kImageAdjustmentProperty_Rating", 5),  # 0-5 stars
    "tag": ("kImageAdjustmentProperty_ColorTag", 7),   # 0 none, 1 red ... 7 purple
}
# Everything printed goes through one writer thread, a line at a time, so lines from different
# threads never mix, and no thread ever waits on the output: if whoever reads it (the Terminal, or
# the LfS app) stops reading, a full pipe would otherwise freeze any request that logs a line.
# Past OUT_MAX waiting lines, new ones are dropped instead.
OUT_MAX = 2000
OUT = queue.Queue(maxsize=OUT_MAX)


def _write_out():
    while True:
        line = OUT.get()
        try:
            sys.stdout.write(line)
            sys.stdout.flush()
        except (OSError, ValueError):
            pass  # the reader has gone; nothing to do but keep the queue moving
        finally:
            OUT.task_done()


threading.Thread(target=_write_out, daemon=True).start()


def _out(line):
    try:
        OUT.put_nowait(line)
    except queue.Full:
        pass  # nobody is reading: drop the line rather than block


def flush_out(timeout=3):
    """Wait (a little) for queued lines to be written, before the script exits."""
    end = time.time() + timeout
    while OUT.unfinished_tasks and time.time() < end:
        time.sleep(0.05)


def say(text=""):
    """Print a line (see OUT)."""
    _out(text + "\n")


def emit(event, **data):
    """Tell the LfS app something (with --control only). See Control."""
    if CONTROL:
        _out("@lfs " + json.dumps({"event": event, **data}) + "\n")


class CaptureOne:
    """Holds the Capture One address and our session, reconnecting on 403.

    With rediscover=True, a refused connection (Capture One restarted, so its port changed)
    triggers a fresh search for the server.
    """

    def __init__(self, base, rediscover=False):
        self.base = base
        self.rediscover = rediscover
        self.session = None
        self.lock = threading.Lock()

    def _get(self, path, timeout):
        req = urllib.request.Request(self.base + path, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()

    def connect(self):
        status, body = self._get(
            f"/connectToServiceForLive?appVersion={APP_VERSION}&protocolVersion={PROTOCOL_VERSION}", 5
        )
        sid = body.decode().strip()
        if status != 200 or not sid.isdigit():
            raise RuntimeError(f"Capture One refused the connection (HTTP {status}, body {body[:80]!r})")
        self.session = sid
        return sid

    @staticmethod
    def path(method, sid, params):
        query = f"sessionID={sid}&" + "&".join(f"{k}={urllib.parse.quote(str(v), safe='/')}" for k, v in params.items())
        return f"/{method}?{query}"

    def disconnect(self):
        """Tell Capture One this session is finished. It also ends any change listener still
        waiting on the session. Best effort: errors are ignored."""
        with self.lock:
            sid, self.session = self.session, None
        if sid:
            try:
                self._get(f"/disconnectFromServiceForLive?sessionID={sid}", 5)
            except Exception:
                pass

    def call(self, method, params, timeout=15):
        """Call a Live endpoint with our session; reconnect once if the session expired
        or Capture One moved to a new port."""
        for attempt in (1, 2):
            sid = None
            try:
                with self.lock:
                    if self.session is None:
                        self.connect()
                    sid = self.session
                return self._get(self.path(method, sid, params), timeout)
            except urllib.error.HTTPError as e:
                if e.code == 403 and attempt == 1:
                    with self.lock:
                        if self.session == sid:
                            self.session = None
                    continue
                return e.code, b""
            except urllib.error.URLError as e:
                if attempt == 1 and self.rediscover and isinstance(e.reason, ConnectionRefusedError):
                    base = find_capture_one()
                    if base:
                        with self.lock:
                            self.base, self.session = base, None
                        say(f"Capture One moved to {base}; reconnected.")
                        continue
                raise
        return 403, b""


class Gone(Exception):
    """A change feed no longer exists (retired, expired, or Capture One restarted)."""


class Feeds:
    """One Capture One session per browser tab and folder visit, for the change feed.

    Capture One delivers each change to only ONE listener of a session. If every browser shared
    one session, an iPad and a Mac watching the same folder would each get only some of the
    changes. So each folder a page opens gets a "feed" of its own: a private Capture One session
    used for that folder's state and its change long-poll. (Not one per tab: after leaving a
    folder, its last long-poll is still waiting on the session for up to a minute, and would
    swallow a change meant for the next listener if the page came back to that folder.)

    A page identifies itself with `client` (random, per page load) and starts a feed with `feed`
    (random, per folder visit). Starting a feed retires that client's previous one, which
    disconnects its session and so also ends its waiting long-poll. Feeds nobody has used for
    IDLE seconds are retired too, and at most MAX are kept. Image requests, ratings, Follow and
    exposure don't need a feed; they use the shared session.
    """

    IDLE = 300  # seconds without a request before a feed is retired
    MAX = 40    # most feeds at once; the least recently used is retired beyond this
    ID_FORMAT = re.compile(r"[A-Za-z0-9_-]{8,40}")

    class Feed:
        def __init__(self, fid, client, base, remote, device):
            self.id, self.client, self.remote = fid, client, remote  # remote: opened through the tunnel
            self.device = device  # the browser's device cookie (see Devices)
            self.co = CaptureOne(base, rediscover=True)
            self.last = time.time()
            self.closed = False
            self.waiting = False  # a change listener is waiting on this feed's session

    def __init__(self, shared):
        self.shared = shared  # the CaptureOne the viewer started with (supplies Capture One's address)
        self.feeds = {}
        self.lock = threading.Lock()
        threading.Thread(target=self._sweep, daemon=True).start()

    @classmethod
    def valid(cls, ident):
        return bool(ident) and cls.ID_FORMAT.fullmatch(ident) is not None

    def _retire(self, feed):
        """Close a feed and disconnect its Capture One session (in the background)."""
        feed.closed = True
        self.feeds.pop(feed.id, None)
        threading.Thread(target=feed.co.disconnect, daemon=True).start()

    def _sweep(self):
        while True:
            time.sleep(30)
            with self.lock:
                # A feed with a listener waiting is in use, however long that wait has lasted so far
                # (it ends within LONG_POLL_TIMEOUT).
                for f in [f for f in self.feeds.values() if not f.waiting and time.time() - f.last > self.IDLE]:
                    self._retire(f)

    def viewers(self):
        """(open pages, of which through the tunnel). A page keeps a long-poll going, so one
        that hasn't asked for 90 s has gone (closed, or a tablet asleep)."""
        with self.lock:
            live = [f for f in self.feeds.values() if f.waiting or time.time() - f.last < 90]
        return len(live), sum(f.remote for f in live)

    def retire_device(self, device):
        """End a removed device's feeds: its waiting long-poll returns, and its next request is refused."""
        with self.lock:
            for f in [f for f in self.feeds.values() if f.device == device]:
                self._retire(f)

    def state(self, client, fid, collection, timeout, remote=False, device=""):
        """The folder's state, starting the feed if it's new. The feed's change listener then
        reports everything that happens after this."""
        with self.lock:
            feed = self.feeds.get(fid)
            if feed is None:
                for old in [f for f in self.feeds.values() if f.client == client]:
                    self._retire(old)  # one feed per tab
                while len(self.feeds) >= self.MAX:
                    self._retire(min(self.feeds.values(), key=lambda f: f.last))
                feed = self.feeds[fid] = self.Feed(fid, client, self.shared.base, remote, device)
            feed.last = time.time()
        try:
            return feed.co.call("getServerStateForLive", {"collectionID": collection}, timeout=timeout)
        finally:
            feed.last = time.time()

    def changes(self, fid, collection, timeout):
        """Wait for the feed's next change. Raises Gone if the feed isn't usable any more: the
        page then starts a new one with a fresh state. (A feed never reconnects by itself: a new
        Capture One session wouldn't know which changes this page already has.)"""
        with self.lock:
            feed = self.feeds.get(fid)
            if feed is None or feed.closed or feed.co.session is None:
                raise Gone()
            if feed.waiting:
                # A second listener on one session would compete with the first for each change
                # (the first may belong to a connection the browser already dropped). Start over.
                self._retire(feed)
                raise Gone()
            feed.waiting = True
            feed.last = time.time()
            sid = feed.co.session
        try:
            status, body = feed.co._get(CaptureOne.path("getServerChangesForLive", sid, {"collectionID": collection}), timeout)
        except urllib.error.HTTPError as e:
            if e.code == 403:
                raise Gone()
            return e.code, b""
        except urllib.error.URLError as e:
            if isinstance(e.reason, ConnectionRefusedError):
                raise Gone()  # Capture One restarted
            raise
        finally:
            feed.waiting = False
            feed.last = time.time()
        if feed.closed:
            raise Gone()  # retired while waiting: whatever arrived is for a session nobody reads
        return status, body

    def close_all(self):
        with self.lock:
            feeds = list(self.feeds.values())
            for f in feeds:
                f.closed = True
            self.feeds.clear()
        for f in feeds:
            f.co.disconnect()


DEVICE_COOKIE = "lfs_device"
DEVICE_FORMAT = re.compile(r"[0-9a-f]{32}")
REMOVED_PAGE = b"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>LfS Web Viewer</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#111214;color:#e8e8ea;
font:16px/1.5 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;padding:16px;text-align:center}
p{color:#8b8d94}</style></head><body><div><h1 style="font-size:20px">This device was removed</h1>
<p>{{Operator}} has removed this device from the live view.<br>Ask them if you think this is a mistake.</p>
</div></body></html>"""


def describe_agent(ua):
    """'iPhone · Safari' from a browser's User-Agent. (An iPad in desktop mode says Mac.)"""
    ua = ua or ""
    kinds = (("iPad", "iPad"), ("iPhone", "iPhone"), ("Android", "Android"), ("CrOS", "Chromebook"),
             ("Macintosh", "Mac"), ("Windows", "Windows PC"), ("Linux", "Linux"))
    kind = next((name for key, name in kinds if key in ua), "Device")
    if "Edg/" in ua:
        browser = "Edge"
    elif "Firefox/" in ua or "FxiOS" in ua:
        browser = "Firefox"
    elif "CriOS" in ua or "Chrome/" in ua:
        browser = "Chrome"
    elif "Safari/" in ua:
        browser = "Safari"
    else:
        browser = ""
    return f"{kind} · {browser}" if browser else kind


class Devices:
    """Who's watching, for the LfS app's Viewers panel: one entry per browser, identified by a
    device cookie (random, kept for a year) that the viewer gives every browser it serves. Unlike
    a page's client id, it survives reloads, so a removed device stays removed.

    For each device: what it is (from its User-Agent), where it connects from (this Mac, the
    network, or the tunnel), for remote visitors their Cloudflare Access email, country and (if
    the Cloudflare zone adds visitor location headers) city, region and rough coordinates, the
    folder and photo it's on (the page reports the photo, POST /api/looking), how many ratings
    and tags it has set, and how much the viewer has sent it (response bodies; photos a browser
    already has cached aren't sent again). Devices not heard from for ACTIVE seconds are listed
    as having left, until FORGET seconds have passed.
    """

    ACTIVE = 90    # a page's long-poll asks at least every ~75 s while it's open
    FORGET = 3600  # "Recently left" covers the last hour

    def __init__(self, access):
        self.access = access
        self.lock = threading.Lock()
        self.seen = {}  # device id -> details

    def touch(self, device, handler):
        """Note a request from this device."""
        h = handler
        remote = h.remote
        with self.lock:
            d = self.seen.get(device)
            if d is None or time.time() - d["last"] > self.ACTIVE:
                # New, or back after leaving: a fresh visit (the ratings and data it had are kept).
                old = d or {"bytes": 0, "ratings": 0, "tags": 0}
                d = self.seen[device] = {"id": device, "first": time.time(), "bytes": old["bytes"],
                                         "folder": "", "photo": "", "ratings": old["ratings"], "tags": old["tags"]}
            agent = h.headers.get("User-Agent") or ""
            if d.get("agent") != agent:  # every photo and tile is a request: parse it once per device
                d.update(agent=agent, name=describe_agent(agent))
            d.update(last=time.time(), ip=h.ip().removeprefix("::ffff:"), remote=remote, owner=h.is_owner(),
                     auth=h.cookie(),
                     # Cloudflare adds these on the tunnel only (the main port refuses Cloudflare traffic).
                     email=(h.headers.get("Cf-Access-Authenticated-User-Email") or "") if remote else "",
                     country=(h.headers.get("Cf-Ipcountry") or "") if remote else "",
                     # With the zone's "Add visitor location headers" managed transform on.
                     city=(h.headers.get("Cf-Ipcity") or "")[:80] if remote else "",
                     region=(h.headers.get("Cf-Region") or "")[:80] if remote else "",
                     lat=self._coordinate(h.headers.get("Cf-Iplatitude"), 90) if remote else None,
                     lon=self._coordinate(h.headers.get("Cf-Iplongitude"), 180) if remote else None)

    @staticmethod
    def _coordinate(text, limit):
        try:
            value = float(text)
        except (TypeError, ValueError):
            return None
        return value if -limit <= value <= limit else None

    def sent(self, device, n):
        with self.lock:
            if device in self.seen:
                self.seen[device]["bytes"] += n

    def watching(self, device, folder):
        with self.lock:
            if device in self.seen:
                if self.seen[device]["folder"] != folder:
                    self.seen[device]["photo"] = ""  # until the page says which photo it shows there
                self.seen[device]["folder"] = folder

    def looking(self, device, photo):
        with self.lock:
            if device in self.seen:
                self.seen[device]["photo"] = photo

    def rated(self, device, prop):
        """A rating ("rating") or color tag ("tag") was set from this device."""
        with self.lock:
            if device in self.seen:
                self.seen[device]["ratings" if prop == "rating" else "tags"] += 1

    def info(self, device):
        with self.lock:
            d = self.seen.get(device)
            return dict(d) if d else None

    @staticmethod
    def where(d):
        return "this-mac" if d["owner"] else "remote" if d["remote"] else "network"

    def snapshot(self, folders):
        """The devices connected now, those that left in the last hour ("left": true, newest
        first), then the removed ones, as the LfS app shows them."""
        now = time.time()
        a = self.access
        with a.lock:
            blocked = dict(a.data["blocked"])
        with self.lock:
            for gone in [k for k, d in self.seen.items() if now - d["last"] > self.FORGET]:
                del self.seen[gone]
            active = sorted((dict(d) for d in self.seen.values() if now - d["last"] < self.ACTIVE),
                            key=lambda d: d["first"])
            left = sorted((dict(d) for d in self.seen.values()
                           if now - d["last"] >= self.ACTIVE and d["id"] not in blocked),
                          key=lambda d: -d["last"])
        out = [{"id": d["id"], "name": d["name"], "where": self.where(d), "ip": d["ip"], "email": d["email"],
                "country": d["country"], "city": d["city"], "region": d["region"], "lat": d["lat"], "lon": d["lon"],
                "folder": folders.get(d["folder"], ""), "photo": d["photo"],
                "ratings": d["ratings"], "tags": d["tags"],
                "canRate": a.can_rate(d["owner"], d["auth"], d["id"]), "unlocked": a.unlocked(d["auth"]),
                "ratingBlocked": not a.rating_allowed(d["id"]), "since": d["first"],
                # Only for those that left: a connected page checks in every minute, and listing that
                # would send the app a new list every few seconds with nothing new to show.
                "lastSeen": d["last"] if i >= len(active) else None,
                "bytes": d["bytes"], "blocked": False, "left": i >= len(active)}
               for i, d in enumerate(active + left)]
        out += [{**info, "id": device, "blocked": True} for device, info in blocked.items()]
        return out


class Exposure:
    """Aperture, shutter speed and ISO for each image, read from the open session's database.

    Live for Studio doesn't send exposure data, but the viewer runs on the same Mac as
    Capture One, so it reads the session file (<name>.cosessiondb, or a catalog's
    <name>.cocatalogdb) directly: read-only, and only for a few milliseconds.
    Images are matched by kVariantKey_ImageID == ZIMAGE.ZIMAGEUUID. The full read is cached until
    the database (or its write-ahead log) changes, and a database Spotlight can't find is looked
    for again only every RETRY_MISSING seconds.
    """

    RETRY_MISSING = 60  # seconds before Spotlight is asked again for a database it couldn't find

    def __init__(self, override=None):
        self.override = override  # --session path, if given
        self.paths = {}           # document name -> database path
        self.missing = {}         # document name -> when Spotlight last failed to find it
        self.lock = threading.Lock()
        self.cache = None         # (path, database change stamp, rows) of the last full read

    def locate(self, name):
        if self.override:
            return self.override
        if name in self.paths and os.path.exists(self.paths[name]):
            return self.paths[name]
        # Follow asks every 2 s from every page: don't run Spotlight that often for a database it
        # can't find (a session on an unindexed drive, say).
        if time.time() - self.missing.get(name, 0) < self.RETRY_MISSING:
            return None
        found = []
        for fname in (f"{name}.cosessiondb", f"{name}.cocatalogdb"):
            try:
                out = subprocess.run(["mdfind", "-name", fname], capture_output=True, text=True, timeout=10).stdout
            except (OSError, subprocess.TimeoutExpired):
                out = ""
            found += [p for p in out.splitlines() if os.path.basename(p) == fname]
        if not found:
            self.missing[name] = time.time()
            return None
        self.missing.pop(name, None)
        # Several sessions with the same name: the one Capture One wrote to last is the open one.
        self.paths[name] = max(found, key=os.path.getmtime)
        return self.paths[name]

    @staticmethod
    def _stamp(path):
        """Changes whenever Capture One writes to the database (or its write-ahead log)."""
        stamp = []
        for p in (path, path + "-wal"):
            try:
                st = os.stat(p)
                stamp.append((st.st_mtime_ns, st.st_size))
            except OSError:
                stamp.append(None)
        return tuple(stamp)

    def read_json(self, name):
        """The named document's {image uuid: [aperture, shutter seconds, iso]}, as JSON bytes.
        Read again only when the database has changed: every page asks after every capture."""
        path = self.locate(name)
        if not path:
            return b"{}"
        stamp = self._stamp(path)
        with self.lock:
            if self.cache and self.cache[:2] == (path, stamp):
                return self.cache[2]
        body = json.dumps(self.read(name, path)).encode()
        with self.lock:
            self.cache = (path, stamp, body)
        return body

    def read(self, name, path=None):
        """Return {image uuid: [aperture, shutter seconds, iso]} for the named document."""
        path = path or self.locate(name)
        if not path:
            return {}
        con = sqlite3.connect(f"file:{urllib.parse.quote(path)}?mode=ro", uri=True, timeout=2)
        try:
            rows = con.execute("SELECT ZIMAGEUUID, ZEXP_APERTURE, ZEXP_SHUTTERSPEED, ZISO FROM ZIMAGE").fetchall()
        finally:
            con.close()
        return {uuid: [ap, sh, iso] for uuid, ap, sh, iso in rows if uuid}

    def signature(self, name):
        """(number of photos, newest number) in the session, or None without the database: cheap
        enough to check often, and it changes when photos are added or removed."""
        path = self.locate(name)
        if not path:
            return None
        con = sqlite3.connect(f"file:{urllib.parse.quote(path)}?mode=ro", uri=True, timeout=2)
        try:
            return tuple(con.execute(
                "SELECT COUNT(*), MAX(v.Z_PK) FROM ZVARIANT v JOIN ZIMAGE i ON v.ZIMAGE = i.Z_PK "
                "WHERE IFNULL(i.ZISTRASHED, 0) = 0").fetchone())
        finally:
            con.close()

    @staticmethod
    def process_counters(path):
        """{variant number: (low-res, high-res, sync) process counters} from the database at `path`.
        Capture One raises these each time it re-processes a photo (an adjustment, a crop, a
        style); asking Live for Studio for a picture doesn't. See Pictures."""
        con = sqlite3.connect(f"file:{urllib.parse.quote(path)}?mode=ro", uri=True, timeout=2)
        try:
            rows = con.execute("SELECT Z_PK, ZLOWRESPROCESSCOUNTER, ZHIGHRESPROCESSCOUNTER, ZSYNCPROCESSCOUNTER "
                               "FROM ZVARIANT").fetchall()
        finally:
            con.close()
        return {pk: (lo, hi, sync) for pk, lo, hi, sync in rows}

    def newest_numbers(self, name, limit=30):
        """The most recently added image numbers in the session, newest first, or None if the
        database can't be found. These are the number before the "/" in Live for Studio's
        variant IDs (ZVARIANT.Z_PK), which rises with every capture or import."""
        path = self.locate(name)
        if not path:
            return None
        con = sqlite3.connect(f"file:{urllib.parse.quote(path)}?mode=ro", uri=True, timeout=2)
        try:
            rows = con.execute(
                "SELECT v.Z_PK FROM ZVARIANT v JOIN ZIMAGE i ON v.ZIMAGE = i.Z_PK "
                "WHERE IFNULL(i.ZISTRASHED, 0) = 0 ORDER BY v.Z_PK DESC LIMIT ?", (limit,)).fetchall()
        finally:
            con.close()
        return [r[0] for r in rows]


class Pictures:
    """Each photo's picture version, and a cache of Capture One's renders.

    Version: nothing in Live for Studio's records changes when a photo is edited (it sends a
    "modified" change, and only to pages watching that folder). So every record the viewer passes
    on gets an "lfsPicture" token, which the page puts in the picture's address. The token changes
    when
      - Capture One re-processes the photo: the session database's process counters rise (see
        Exposure.process_counters), whichever folder anyone is watching, and also for edits made
        while the viewer wasn't running;
      - a page's change feed reports the photo "modified" for anything but a rating or tag.
    An address with the current token is then the same picture for good, so browsers may keep it
    for a year without asking again ("immutable"). Not while a photo has only just changed:
    Capture One can report a change before it has redrawn the picture, so for GRACE seconds its
    pictures must be checked each time and aren't cached here. And not without the session
    database: then pictures are always checked (with an ETag).

    Cache: recent renders, up to MAX_BYTES, keyed by what shapes the picture (folder, photo,
    size, crop) and the current token. Several devices on one photo, a reload or a second visit
    then cost Capture One nothing, and a browser checking its copy gets its 304 straight away.
    """

    GRACE = 8                       # seconds after a change before a picture is final
    MAX_BYTES = 256 * 1024 * 1024
    SAME_CHANGE = 10                # seconds in which another feed's report of a rating change is the same one
    BOOT = secrets.token_hex(4)     # without the database, tokens start afresh each time the viewer starts

    def __init__(self, c1, exposure):
        self.c1, self.exposure = c1, exposure
        self.lock = threading.Lock()
        self.edits = {}       # variant number -> edits reported by change feeds
        self.marks = {}       # variant id -> (rating, tag, when it last changed), to tell a rating change from an edit
        self.changed = {}     # variant number -> when its picture last changed
        self.read = None      # (database path, change stamp, {variant number: process counters}) of the last read
        self.cache = collections.OrderedDict()  # key -> (etag, body), least recently used first
        self.bytes = 0

    @staticmethod
    def number(vid):
        """A variant id's number (ZVARIANT.Z_PK), the part before the "/"."""
        head = str(vid).split("/", 1)[0]
        return int(head) if head.isdigit() else -1

    def counters(self):
        """{variant number: process counters}, read again only when the database has changed;
        None without the database. Photos whose counters moved since the last read have changed."""
        name = known_session(self.c1)
        path = self.exposure.locate(name) if name else None
        if not path:
            return None
        stamp = Exposure._stamp(path)
        with self.lock:
            if self.read and self.read[:2] == (path, stamp):
                return self.read[2]
        try:
            new = Exposure.process_counters(path)
        except sqlite3.Error:
            return None
        with self.lock:
            if self.read and self.read[0] == path:
                old, now = self.read[2], time.time()
                for n, c in new.items():
                    if old.get(n) != c:
                        self._changed(n, now)
            self.read = (path, stamp, new)
        return new

    def _changed(self, n, now):
        """Photo number n has a new picture: start its grace period, and drop its cached renders."""
        self.changed[n] = now
        for key in [k for k in self.cache if k[1] == n]:
            self.bytes -= len(self.cache.pop(key)[1])

    def token(self, vid, counters):
        n = self.number(vid)
        basis = counters.get(n) if counters is not None else self.BOOT
        with self.lock:
            edits = self.edits.get(n, 0)
        return hashlib.blake2s(f"{n}:{edits}:{basis}".encode(), digest_size=5).hexdigest()

    def settled(self, n):
        with self.lock:
            return time.time() - self.changed.get(n, 0) >= self.GRACE

    def annotate(self, body, live):
        """Note what a state body (live=False) or a change-feed body (live=True) says about each
        photo, and add each record's token. Returns the body to send."""
        try:
            data = json.loads(body)
        except ValueError:
            return body
        variants = data.get("variants") if isinstance(data, dict) else None
        if not variants:
            return body
        counters = self.counters()
        now = time.time()
        with self.lock:
            for v in variants:
                vid = v.get("kVariantKey_VariantID") if isinstance(v, dict) else None
                if not vid:
                    continue
                p = v.get("kVariantKey_Properties") or {}
                mark = (p.get("kVariantProperty_Rating") or 0, p.get("kVariantProperty_Colortag") or 0)
                prev = self.marks.get(vid)
                if prev is None or prev[:2] != mark:
                    self.marks[vid] = (*mark, now if prev is not None else 0)
                elif live and v.get("kVariantKey_ChangeType") == "modified" and now - prev[2] > self.SAME_CHANGE:
                    # The rating and tag are as before, so the picture is what changed. (Within
                    # SAME_CHANGE of a rating change, this is another page's feed reporting that.)
                    n = self.number(vid)
                    self.edits[n] = self.edits.get(n, 0) + 1
                    self._changed(n, now)
        for v in variants:
            if isinstance(v, dict) and v.get("kVariantKey_VariantID"):
                v["lfsPicture"] = self.token(v["kVariantKey_VariantID"], counters)
        return json.dumps(data).encode()

    def lookup(self, key):
        with self.lock:
            hit = self.cache.get(key)
            if hit:
                self.cache.move_to_end(key)
            return hit

    def store(self, key, etag, body):
        """Keep a render, unless its photo has only just changed (it may be the old picture)."""
        with self.lock:
            if time.time() - self.changed.get(key[1], 0) < self.GRACE or key in self.cache:
                return
            self.cache[key] = (etag, body)
            self.bytes += len(body)
            while self.bytes > self.MAX_BYTES and self.cache:
                self.bytes -= len(self.cache.popitem(last=False)[1][1])


class Latest:
    """Finds the most recent capture in any shared folder, for Follow.

    Live for Studio only reports changes in the folder a client is watching, so a capture that
    lands in another folder would be missed. The session database says which image is newest
    (cheap, read-only); the shared folders are then searched once to find which one holds it.
    Folders are searched with a separate Capture One session, so the page's own change feed
    isn't disturbed. Without the database, the folders are searched at most every 10 seconds.
    Every page with Follow on asks every 2 s, so one answer is shared by all pages for a second.
    """

    def __init__(self, c1, exposure):
        self.c1, self.exposure = c1, exposure
        self.scanner = CaptureOne(c1.base)
        self.lock = threading.Lock()
        self.where = {}          # image number -> (folder path depth, folder id, variant id)
        self.scanned_for = None  # the newest image number being searched for
        self.scan_tries = 0      # searches made for it so far
        self.last_scan = 0.0
        self.answer = (0.0, {})  # (when, result): every page polls every 2 s; they share one answer a second

    def _call(self, method, params):
        if self.scanner.base != self.c1.base:  # Capture One moved; follow it
            self.scanner.base, self.scanner.session = self.c1.base, None
        status, body = self.scanner.call(method, params, timeout=30)
        return json.loads(body) if status == 200 and body else {}

    def _scan(self, hint):
        root = self._call("getServerStateForLive", {"collectionID": ""})
        obj = (root.get("objects") or [{}])[0]
        folders = [c for c in obj.get("kObjectKey_Collections", [])
                   if not any(HIDDEN_FOLDER.match(p) for p in (c.get("kObjectCollectionKey_relativePath")
                                                              or c.get("kObjectCollectionKey_name", "")).split("/"))]
        folders.sort(key=lambda c: c["kObjectCollectionKey_id"] != hint)  # the hinted folder first
        where = {}
        for c in folders:
            path = c.get("kObjectCollectionKey_relativePath") or c.get("kObjectCollectionKey_name", "")
            depth = path.count("/")
            for v in self._call("getServerStateForLive", {"collectionID": c["kObjectCollectionKey_id"]}).get("variants", []):
                vid = v.get("kVariantKey_VariantID", "")
                num = vid.split("/")[0]
                if v.get("kVariantKey_ChangeType") == "deleted" or not num.isdigit():
                    continue
                # A parent folder may list its subfolders' images too: keep the most specific folder.
                if int(num) not in where or where[int(num)][0] < depth:
                    where[int(num)] = (depth, c["kObjectCollectionKey_id"], vid)
        self.where, self.last_scan = where, time.time()
        return obj.get("kObjectKey_ObjectName", "")

    def find(self, hint=""):
        """Return {"c": folder id, "id": variant id, "n": image number} for the newest shared capture."""
        with self.lock:
            if time.time() - self.answer[0] < 1:
                return self.answer[1]
            self.answer = (time.time(), self._find(hint))
            return self.answer[1]

    def _find(self, hint):
        name = known_session(self.c1)
        newest = self.exposure.newest_numbers(name) if name else None
        if newest is not None:
            top = newest[0] if newest else None
            if top is not None and top not in self.where:
                # Something new. Search the shared folders, and again a few times 2 s apart:
                # a capture can reach the database before Live for Studio lists it. If it
                # never shows up, it's in a folder that isn't shared.
                if self.scanned_for != top:
                    self.scanned_for, self.scan_tries = top, 0
                if self.scan_tries < 5 and time.time() - self.last_scan >= 2:
                    self._scan(hint)
                    self.scan_tries += 1
            hit = next((n for n in newest if n in self.where), None)
            if hit is None and self.where:
                hit = max(self.where)  # the newest images are all outside the shared folders
        else:
            if time.time() - self.last_scan > 10:
                self._scan(hint)
            hit = max(self.where) if self.where else None
        if hit is None:
            return {}
        _, folder, vid = self.where[hit]
        return {"c": folder, "id": vid, "n": hit}


class FolderCounts:
    """How many photos each shared folder holds, for the counts in the page's folder list.

    Live for Studio lists folders by name only, so each folder's state is fetched and its photos
    counted (the same ones the page shows on opening it). This uses a Capture One session of its
    own, like Latest, so no page's change feed is disturbed, and is redone at most every MAX_AGE
    seconds however many pages ask (with the session database: only when photos were added or
    removed, or every RECHECK seconds), and never while a page waits, except for the first time.
    The page counts the folder it has open itself, live.
    """

    MAX_AGE = 20     # seconds, without the session database
    RECHECK = 120    # with it: rescanned when photos are added or removed, and at least this often

    def __init__(self, c1, exposure):
        self.c1, self.exposure = c1, exposure
        self.scanner = CaptureOne(c1.base)
        self.lock = threading.Lock()
        self.counts, self.at = {}, 0.0
        self.scanning = False
        self.scan_lock = threading.Lock()
        self.signature = None  # the session's (photo count, newest number) at the last scan

    def _state(self, collection):
        if self.scanner.base != self.c1.base:  # Capture One moved; follow it
            self.scanner.base, self.scanner.session = self.c1.base, None
        status, body = self.scanner.call("getServerStateForLive", {"collectionID": collection}, timeout=30)
        return json.loads(body) if status == 200 and body else {}

    def get(self):
        """{folder id: number of photos}. A page never waits for a rescan, except for the first."""
        with self.lock:
            if self.at and (self.scanning or not self._stale()):
                return dict(self.counts)
            self.scanning = True
        with self.scan_lock:  # one scan at a time; until the first is done, pages wait for it
            try:
                if not self.at or self._stale():
                    signature = self._signature()
                    counts = self._scan()
                    with self.lock:
                        self.counts, self.at, self.signature = counts, time.time(), signature
            finally:
                with self.lock:
                    self.scanning = False
        with self.lock:
            return dict(self.counts)

    def _signature(self):
        name = known_session(self.c1)
        try:
            return self.exposure.signature(name) if name else None
        except sqlite3.Error:
            return None

    def _stale(self):
        """Whether the counts may be out of date: photos were added or removed (the session
        database says so cheaply), or, without the database, MAX_AGE has passed."""
        age, signature = time.time() - self.at, self._signature()
        if signature is None:
            return age > self.MAX_AGE
        return signature != self.signature or age > self.RECHECK

    def _scan(self):
        root = (self._state("").get("objects") or [{}])[0]
        counts = {}
        for c in root.get("kObjectKey_Collections", []):
            path = c.get("kObjectCollectionKey_relativePath") or c.get("kObjectCollectionKey_name", "")
            if any(HIDDEN_FOLDER.match(p) for p in path.split("/")):
                continue
            # The list can name a photo more than once (one entry per change: new, metadata,
            # modified...), so count distinct photos, the way the page merges them.
            photos = set()
            for v in self._state(c["kObjectCollectionKey_id"]).get("variants", []):
                if v.get("kVariantKey_ChangeType") == "deleted":
                    photos.discard(v.get("kVariantKey_VariantID"))
                else:
                    photos.add(v.get("kVariantKey_VariantID"))
            counts[c["kObjectCollectionKey_id"]] = len(photos)
        return counts


def lan_addresses():
    """[(interface, IPv4 address)] for this Mac's network connections, skipping loopback,
    self-assigned (169.254.x.x) and VPN tunnel addresses."""
    try:
        out = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    addrs, iface = [], ""
    for line in out.splitlines():
        if line and not line[0].isspace():
            iface = line.split(":")[0]
        m = re.match(r"\s+inet (\d+\.\d+\.\d+\.\d+)", line)
        if m and iface != "lo0" and not iface.startswith(("utun", "lo")) and not m.group(1).startswith(("127.", "169.254.")):
            addrs.append((iface, m.group(1)))
    return addrs


def local_hostname():
    """This Mac's Bonjour name (e.g. "Faini-book-14"), reachable as <name>.local."""
    try:
        return subprocess.run(["scutil", "--get", "LocalHostName"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def network_urls(port):
    """[(interface, address)] other devices can open: one per network connection, then the
    Bonjour name (labelled "bonjour") for Apple devices."""
    urls = [(name, f"http://{ip}:{port}") for name, ip in lan_addresses()]
    host = local_hostname()
    if host:
        urls.append(("bonjour", f"http://{host}.local:{port}"))
    return urls


def find_capture_one():
    """Return 'http://127.0.0.1:PORT' for Capture One's Live for Studio server."""
    try:
        out = subprocess.run(
            ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "Capture"],
            capture_output=True, text=True, timeout=10,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        out = ""
    ports = sorted({int(p) for p in re.findall(r":(\d+) \(LISTEN\)", out)})
    for port in ports:
        base = f"http://127.0.0.1:{port}"
        try:
            CaptureOne(base).connect()
            return base
        except Exception:
            continue
    return None


class Access:
    """Who may rate and color-tag.

    This Mac can always rate (and is the only one that can change these settings). Other devices
    on the network follow the mode, saved in settings.json next to this script:
        "view": look only (the default)
        "pin":  rating unlocks after entering the PIN; the device then holds a cookie for 30 days.
                Changing the PIN signs every device out.
        "open": anyone can rate
    A wrong PIN counts against the device; after max_fails it must wait lockout seconds.

    Remote visitors (through the tunnel, see Remote) first need the viewing code, unless
    remote_view is "open". Its cookie is tied to the code (and view_secret), so changing the code
    signs them out; a new rating PIN doesn't. "Sign out all devices" replaces both secrets.
    """

    MODES = ("view", "pin", "open")
    REMOTE_VIEWS = ("code", "open")
    COOKIE, VIEW_COOKIE = "lfs_auth", "lfs_view"
    REMOTE_MAX, REMOTE_WINDOW = 20, 600  # wrong remote guesses from everyone together, per 10 minutes
    DEFAULTS = {"mode": "view", "pin": "", "max_fails": 5, "lockout": 60, "remote_view": "code", "remote_code": "",
                "operator": "the photographer"}  # how visitors' pages name whoever runs the viewer

    def __init__(self):
        self.lock = threading.Lock()
        self.fails = {}  # client ip -> [wrong attempts, locked until]
        self.remote_fails = []  # times of recent wrong remote guesses (all visitors)
        self.own_ips, self.own_ips_at = set(), 0.0
        # Two secrets, so a new rating PIN doesn't also sign remote visitors out of viewing.
        self.data = {**self.DEFAULTS, "secret": secrets.token_hex(16), "view_secret": secrets.token_hex(16),
                     "blocked": {},     # removed devices: device id -> {name, where, ip, email, blockedAt}
                     "no_rating": []}   # devices that may not rate, whatever the mode
        try:
            with open(SETTINGS) as f:
                saved = json.load(f)
            for key, value in self.data.items():
                if type(saved.get(key)) is type(value):
                    self.data[key] = saved[key]
        except (OSError, ValueError):
            pass
        if self.data["mode"] not in self.MODES:
            self.data["mode"] = "view"
        if self.data["remote_view"] not in self.REMOTE_VIEWS:
            self.data["remote_view"] = "code"
        self._save()

    @classmethod
    def mode_error(cls, mode, pin):
        if mode not in cls.MODES or (mode == "pin" and not re.fullmatch(r"\d{4,8}", pin)):
            return "Choose a mode, and a PIN of 4 to 8 digits."
        return None

    def settings(self):
        """Everything the LfS app shows and changes (PIN and code included)."""
        d = self.data
        return {"mode": d["mode"], "pin": d["pin"], "maxFails": d["max_fails"], "lockout": d["lockout"],
                "remoteView": d["remote_view"], "remoteCode": d["remote_code"], "operator": d["operator"]}

    def operator(self, capital=False, page=False):
        """Who runs the viewer, as visitors' pages say it: "the photographer" by default, or what's
        set in the LfS app ("the digi-tech", "Studio 4"...). capital: to start a sentence.
        page: made safe to put in a web page."""
        who = self.data["operator"]
        if capital:
            who = who[:1].upper() + who[1:]
        return html.escape(who) if page else who

    def fill(self, page):
        """A visitor's page (gate.html, the removed page) with the operator's name filled in."""
        return (page.replace(b"{{operator}}", self.operator(page=True).encode())
                    .replace(b"{{Operator}}", self.operator(capital=True, page=True).encode()))

    def _save(self):
        tmp = SETTINGS + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.data, f, indent=2)
        os.replace(tmp, SETTINGS)

    @property
    def mode(self):
        return self.data["mode"]

    def token(self):
        # Tied to the PIN, so changing the PIN invalidates every device's cookie.
        return hashlib.sha256(f"{self.data['secret']}:{self.data['pin']}".encode()).hexdigest()

    def is_owner(self, ip):
        """Requests from this Mac, by loopback or by any of its own network addresses."""
        ip = ip.removeprefix("::ffff:")
        if ip in ("127.0.0.1", "::1"):
            return True
        if time.time() - self.own_ips_at > 60:  # addresses can change (Wi-Fi on/off); refresh now and then
            self.own_ips, self.own_ips_at = {a for _, a in lan_addresses()}, time.time()
        return ip in self.own_ips

    def view_token(self):
        return hashlib.sha256(f"{self.data['view_secret']}:{self.data['remote_code']}".encode()).hexdigest()

    @staticmethod
    def same(a, b):
        return hmac.compare_digest((a or "").encode(), b.encode())

    def unlocked(self, cookie):
        return self.mode == "pin" and bool(self.data["pin"]) and self.same(cookie, self.token())

    def can_view_remote(self, cookie):
        if self.data["remote_view"] == "open":
            return True
        return bool(self.data["remote_code"]) and self.same(cookie, self.view_token())

    def can_rate(self, owner, cookie, device=""):
        if owner:
            return True
        if device in self.data["no_rating"]:
            return False
        return self.mode == "open" or self.unlocked(cookie)

    def rating_allowed(self, device):
        return device not in self.data["no_rating"]

    def is_blocked(self, device):
        return device in self.data["blocked"]

    def block(self, device, info):
        with self.lock:
            self.data["blocked"][device] = info
            self._save()

    def unblock(self, device):
        with self.lock:
            found = self.data["blocked"].pop(device, None) is not None
            self._save()
        return found

    def set_device_rating(self, device, allow):
        with self.lock:
            others = [d for d in self.data["no_rating"] if d != device]
            self.data["no_rating"] = others if allow else others + [device]
            self._save()

    def set_mode(self, mode, pin):
        with self.lock:
            if mode == "pin" and pin != self.data["pin"]:
                self.data["secret"] = secrets.token_hex(16)  # new PIN: sign everyone out
            self.data["mode"] = mode
            if mode == "pin":
                self.data["pin"] = pin
            self._save()

    def update(self, **values):
        """Change other settings (lockout, remote view); the caller has checked the values."""
        with self.lock:
            self.data.update(values)
            self._save()

    def sign_out_all(self):
        with self.lock:
            self.data["secret"], self.data["view_secret"] = secrets.token_hex(16), secrets.token_hex(16)
            self._save()

    def try_pin(self, ip, pin, remote=False):
        """Return (ok, seconds to wait before trying again)."""
        return self._attempt(ip, pin, self.data["pin"], remote)

    def try_code(self, ip, code):
        return self._attempt(ip, code, self.data["remote_code"], True)

    def _attempt(self, ip, guess, answer, remote):
        with self.lock:
            now = time.time()
            if remote:
                self.remote_fails = [t for t in self.remote_fails if now - t < self.REMOTE_WINDOW]
                if len(self.remote_fails) >= self.REMOTE_MAX:
                    return False, int(self.remote_fails[0] + self.REMOTE_WINDOW - now) + 1
                ip = "remote " + ip  # never shares a count with a device in the studio
            count, until = self.fails.get(ip, [0, 0.0])
            if now < until:
                return False, int(until - now) + 1
            if answer and self.same(guess, answer):
                self.fails.pop(ip, None)
                return True, 0
            if remote:
                self.remote_fails.append(now)
                if len(self.remote_fails) == self.REMOTE_MAX:
                    say(f"Many wrong viewing codes or PINs through the tunnel: remote unlocking paused "
                        f"for up to {self.REMOTE_WINDOW // 60} minutes.")
                    emit("guessing", wait=self.REMOTE_WINDOW)
            count += 1
            if count >= self.data["max_fails"]:
                self.fails[ip] = [0, now + self.data["lockout"]]
                return False, self.data["lockout"]
            self.fails[ip] = [count, 0.0]
            return False, 0


class Server(ThreadingHTTPServer):
    daemon_threads = True
    # Opening a folder can request dozens of thumbnails at once. The default queue of 5 waiting
    # connections makes the rest wait (or fail and be retried a second later); this is plenty.
    request_queue_size = 128

    def handle_error(self, request, client_address):
        # With keep-alive (see Handler), browsers drop idle connections whenever they like; that's
        # not an error worth a traceback in the log.
        if isinstance(sys.exc_info()[1], (ConnectionResetError, BrokenPipeError, TimeoutError)):
            return
        super().handle_error(request, client_address)


class Handler(BaseHTTPRequestHandler):
    # HTTP/1.1 keeps each browser connection open for the next request (keep-alive), so a folder's
    # dozens of thumbnails don't each wait for a new connection. That needs every response to say
    # how long it is (they all send Content-Length; a 304 has no body) and every request body to be
    # read in full (see do_POST). An idle connection is closed after `timeout` seconds.
    protocol_version = "HTTP/1.1"
    timeout = 120
    BODY_MAX = 10000  # bytes; a POST body bigger than this is not read, and its connection is closed

    c1 = None        # set in main()
    exposure = None  # set in main()
    pictures = None  # set in main()
    access = None    # set in main()
    latest = None    # set in main()
    counts = None    # set in main()
    feeds = None     # set in main()
    devices = None   # set in main()
    port = 0         # set in main()
    tunnel_port = 0  # set in main() with --tunnel-port
    remote = False   # True on the tunnel listener (RemoteHandler)

    def log_message(self, fmt, *args):
        pass  # keep the terminal quiet; errors are printed explicitly

    def device(self):
        """This browser's device id (see Devices): its cookie, or a new one sent with this response."""
        if getattr(self, "_device", None) is None:
            given = self.cookie(DEVICE_COOKIE)
            if DEVICE_FORMAT.fullmatch(given or ""):
                self._device = given
            else:
                self._device = self._new_device = secrets.token_hex(16)
        return self._device

    def end_headers(self):
        if getattr(self, "_new_device", None):
            self.send_header("Set-Cookie", f"{DEVICE_COOKIE}={self._new_device}; Max-Age=31536000; {self.cookie_flags()}")
            self._new_device = None
        super().end_headers()

    def admit(self, path):
        """Note which device is asking (see Devices), and turn a removed one away: its page says
        so, and the API answers 401, which makes an open page reload into that page.
        Returns True if the request was answered here."""
        device = self.device()
        self.devices.touch(device, self)
        if not self.access.is_blocked(device) or self.is_owner():
            return False
        if path in ("/", "/index.html"):
            self.send(200, self.access.fill(REMOVED_PAGE), "text/html; charset=utf-8")
        else:
            self.send_json(401, {"error": f"This device was removed by {self.access.operator()}."})
        return True

    def counted(self, body):
        """Write a response body, counting it for the device it goes to (see Devices)."""
        if getattr(self, "_device", None) and self.devices:
            self.devices.sent(self._device, len(body))
        self.wfile.write(body)

    def screen(self, path, post=False):
        """Answer requests that may not go further here. Returns True if it did.

        The main port refuses anything that came through Cloudflare: there, cloudflared's requests
        would come from this Mac and count as the owner. The tunnel port lets remote visitors in
        only with the viewing code (see Remote)."""
        if not self.remote:
            if self.headers.get("Cf-Connecting-Ip") or self.headers.get("Cf-Ray"):
                where = f"http://localhost:{self.tunnel_port}" if self.tunnel_port else "the viewer's tunnel port"
                self.send(403, f"This address is for your own network. Point the Cloudflare tunnel at {where}.".encode(),
                          "text/plain; charset=utf-8")
                return True
            return False
        if self.access.can_view_remote(self.cookie(Access.VIEW_COOKIE)) or (post and path == "/api/view"):
            return False
        if not post and path in ("/", "/index.html"):
            with open(GATE, "rb") as f:
                self.send(200, self.access.fill(f.read()), "text/html; charset=utf-8")
        else:
            self.send_json(401, {"error": "Enter the viewing code first."})
        return True

    def send(self, status, body=b"", ctype="application/json", cache=False):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "private, max-age=86400" if cache else "no-store")
        self.end_headers()
        self.counted(body)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        try:
            if self.screen(url.path) or self.admit(url.path):
                return
            if url.path in ("/", "/index.html"):
                with open(PAGE, "rb") as f:
                    self.send(200, f.read(), "text/html; charset=utf-8")
            elif url.path == "/api/state":
                # Capture One can take a while to answer while it imports a fresh capture.
                # With client and feed, this also starts the page's private change feed (see Feeds).
                if Feeds.valid(q.get("client")) and Feeds.valid(q.get("feed")):
                    self.devices.watching(self.device(), q.get("c", ""))
                    status, body = self.feeds.state(q["client"], q["feed"], q.get("c", ""), 60, self.remote, self.device())
                else:
                    status, body = self.c1.call("getServerStateForLive", {"collectionID": q.get("c", "")}, timeout=60)
                if status == 200 and body:
                    body = self.pictures.annotate(body, live=False)
                self.send(status, body)
            elif url.path == "/api/changes":
                try:
                    if Feeds.valid(q.get("feed")):
                        status, body = self.feeds.changes(q["feed"], q.get("c", ""), LONG_POLL_TIMEOUT)
                    else:  # an old page without feeds: the shared session, as before
                        status, body = self.c1.call(
                            "getServerChangesForLive", {"collectionID": q.get("c", "")}, timeout=LONG_POLL_TIMEOUT
                        )
                except Gone:
                    self.send(410, b"")  # the page should start a new feed
                    return
                except (TimeoutError, urllib.error.URLError) as e:
                    if not isinstance(getattr(e, "reason", e), TimeoutError):
                        raise
                    status, body = 204, b""  # idle long-poll; the page simply asks again
                if DEBUG and body:
                    say(f"changes for {q.get('c', '')}: {body[:4000].decode('utf-8', 'replace')}")
                if status == 200 and body:
                    body = self.pictures.annotate(body, live=True)
                self.send(status, body)
            elif url.path == "/api/latest":
                # The newest capture in any shared folder, for Follow. ?hint=FOLDER is searched first.
                self.send_json(200, self.latest.find(q.get("hint", "")))
            elif url.path == "/api/access":
                self.send_json(200, self.access_info())
            elif url.path == "/api/ping":
                self.send(200, b"{}")  # nothing to do: the page times how long this takes
            elif url.path == "/api/counts":
                # Photos per folder, for the folder list (see FolderCounts).
                self.send_json(200, self.counts.get())
            elif url.path == "/api/exposure":
                # The session's name (e.g. "TEST SESSION") identifies its database file.
                name = known_session(self.c1)
                self.send(200, self.exposure.read_json(name) if name else b"{}")
            elif url.path == "/api/image":
                # w/h: output size. l/t/r/b: optional crop rectangle in full-image pixels
                # (all 0 = whole image); a crop with r-l == w is a 1:1 view of that region.
                w, h = int(q.get("w", 1600)), int(q.get("h", 1600))
                l, t, r, b = (int(q.get(k, 0)) for k in ("l", "t", "r", "b"))
                vid, pics = q.get("id", ""), self.pictures
                counters = pics.counters()
                token = pics.token(vid, counters)
                key = (q.get("c", ""), Pictures.number(vid), vid, w, h, l, t, r, b, token)
                hit = pics.lookup(key)
                began = time.perf_counter()
                if hit:
                    etag, body = hit
                    timing = "memory"
                else:
                    status, body = self.c1.call(
                        "getImageForLive",
                        {"collectionID": q.get("c", ""), "id": vid,
                         "width": w, "height": h, "left": l, "top": t, "right": r, "bottom": b},
                        timeout=30,
                    )
                    if status != 200:
                        self.send(status, body, "text/plain")
                        return
                    etag = '"' + hashlib.md5(body).hexdigest() + '"'
                    pics.store(key, etag, body)
                    timing = "c1"
                # Server-Timing is how long Capture One took to draw this picture ("c1"), or that the viewer
                # had it in memory ("memory"); the page's Connection panel adds these up.
                timing = f"{timing};dur={(time.perf_counter() - began) * 1000:.1f}"
                # The page's address carries the photo's token (see Pictures): with the current
                # one, and the photo settled, this is the picture for good. Otherwise browsers may
                # keep a copy but must check it each time; the ETag lets them reuse it (304).
                final = (counters is not None and q.get("v", "").split(".")[0] == token
                         and pics.settled(Pictures.number(vid)))
                cache_control = "private, max-age=31536000, immutable" if final else "no-cache"
                if self.headers.get("If-None-Match") == etag:
                    self.send_response(304)
                    self.send_header("ETag", etag)
                    self.send_header("Cache-Control", cache_control)
                    self.send_header("Server-Timing", timing)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("ETag", etag)
                self.send_header("Cache-Control", cache_control)
                self.send_header("Server-Timing", timing)
                self.end_headers()
                self.counted(body)
            else:
                self.send(404, b"not found", "text/plain")
        except (BrokenPipeError, ConnectionResetError):
            pass  # browser navigated away mid-request
        except Exception as e:
            self.fail(url.path, e)

    # ---- access helpers ----

    def ip(self):
        if self.remote:  # every tunnel request comes from cloudflared; Cloudflare names the visitor
            return self.headers.get("Cf-Connecting-Ip") or self.client_address[0]
        return self.client_address[0]

    def is_owner(self):
        return not self.remote and self.access.is_owner(self.ip())

    def cookie(self, name=Access.COOKIE):
        jar = http.cookies.SimpleCookie(self.headers.get("Cookie", ""))
        return jar[name].value if name in jar else ""

    def cookie_flags(self):
        # Through Cloudflare the visitor is on HTTPS, so the cookie can insist on it.
        https = self.remote and "https" in (self.headers.get("X-Forwarded-Proto", "") + self.headers.get("Cf-Visitor", ""))
        return "Path=/; HttpOnly; SameSite=Strict" + ("; Secure" if https else "")

    def access_info(self):
        a, owner = self.access, self.is_owner()
        info = {
            "mode": a.mode,
            "isOwner": owner,
            "canRate": a.can_rate(owner, self.cookie(), self.device()),
            "unlocked": a.unlocked(self.cookie()),
            "managed": CONTROL,  # settings are in the LfS app, not in the page
            "remote": self.remote,
        }
        if owner and not CONTROL:  # only this Mac sees the PIN and the addresses to share
            info["pin"] = a.data["pin"]
            info["addresses"] = [u for _, u in network_urls(self.port)]
        return info

    def read_body(self):
        """Read this request's whole body (see do_POST). One that can't be read in full (too big, or
        of unknown length) is skipped, and the connection is closed after this response instead of
        being reused, so its leftover bytes are never taken for the next request."""
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = -1
        if self.headers.get("Transfer-Encoding") or not 0 <= n <= self.BODY_MAX:
            self.close_connection = True
            self._body = b""
        else:
            self._body = self.rfile.read(n) if n else b""

    def json_body(self):
        try:
            return json.loads(getattr(self, "_body", b"") or b"{}")
        except ValueError:
            return {}

    def send_json(self, status, data, cookie=None):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if cookie is not None:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.counted(body)

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        # First, whatever the answer will be: on a kept-alive connection, an unread body would be
        # mistaken for the next request.
        self.read_body()
        try:
            # The page sends this header with every change. A form or script on another website
            # can't add it without permission the viewer never grants, so such requests are refused.
            if self.headers.get("X-LfS") != "1":
                self.send(403, b"missing X-LfS header", "text/plain")
                return
            if self.screen(url.path, post=True) or self.admit(url.path):
                return
            if url.path == "/api/access":
                # Change the network mode. Only from this Mac, and only when the LfS app isn't in charge.
                if CONTROL:
                    self.send_json(403, {"error": "Change this in the LfS app."})
                    return
                if not self.is_owner():
                    self.send_json(403, {"error": "Only the Mac running the viewer can change this."})
                    return
                body = self.json_body()
                mode, pin = body.get("mode"), str(body.get("pin", ""))
                error = Access.mode_error(mode, pin)
                if error:
                    self.send_json(400, {"error": error})
                    return
                self.access.set_mode(mode, pin)
                say(f"Network access changed to: {ACCESS_LABELS[mode]}")
                self.send_json(200, self.access_info())
                return
            if url.path == "/api/unlock":
                if self.access.mode != "pin":
                    self.send_json(400, {"error": "PIN unlock is not turned on."})
                    return
                ok, wait = self.access.try_pin(self.ip(), str(self.json_body().get("pin", "")), self.remote)
                if not ok:
                    msg = f"Too many tries. Wait {wait} seconds." if wait else "Wrong PIN."
                    self.send_json(403, {"error": msg})
                    return
                cookie = f"{Access.COOKIE}={self.access.token()}; Max-Age=2592000; {self.cookie_flags()}"
                self.send_json(200, {"mode": "pin", "canRate": True, "unlocked": True,
                                     "isOwner": self.is_owner()}, cookie)
                return
            if url.path == "/api/lock":
                self.send_json(200, {"ok": True}, f"{Access.COOKIE}=; Max-Age=0; {self.cookie_flags()}")
                return
            if url.path == "/api/view" and self.remote:
                # The remote viewing code, from gate.html.
                if self.access.data["remote_view"] == "code" and not self.access.data["remote_code"]:
                    self.send_json(403, {"error": "Remote viewing isn't set up on the Mac yet."})
                    return
                ok, wait = self.access.try_code(self.ip(), str(self.json_body().get("code", "")))
                if not ok:
                    msg = f"Too many tries. Wait {wait} seconds." if wait else "Wrong code."
                    self.send_json(403, {"error": msg})
                    return
                cookie = f"{Access.VIEW_COOKIE}={self.access.view_token()}; Max-Age=2592000; {self.cookie_flags()}"
                self.send_json(200, {"ok": True}, cookie)
                return
            if url.path == "/api/looking":
                # The photo this page shows (a name, as the page has it), for the Viewers panel.
                body = self.json_body()
                photo = str(body.get("photo", "") if isinstance(body, dict) else "")[:200]
                self.devices.looking(self.device(), "".join(ch for ch in photo if ch.isprintable()))
                self.send_json(200, {"ok": True})
                return
            if url.path != "/api/set":
                self.send(404, b"not found", "text/plain")
                return
            if not self.access.can_rate(self.is_owner(), self.cookie(), self.device()):
                self.send_json(403, {"error": "View only"})
                return
            # Rate or color-tag one image: /api/set?c=FOLDER&id=VARIANT&prop=rating|tag&value=N
            prop = SETTABLE.get(q.get("prop", ""))
            try:
                value = int(q.get("value", ""))
            except ValueError:
                value = -1
            if not prop or not 0 <= value <= prop[1] or not q.get("id"):
                self.send(400, b"bad rating or tag request", "text/plain")
                return
            status, body = self.c1.call(
                "setPropertyForLive",
                {"collectionID": q.get("c", ""), "objectType": "kObjectType_ImageAdjustments",
                 "objectID": q["id"], "propertyID": prop[0], "propertyValue": value},
            )
            if status == 200:
                self.devices.rated(self.device(), q["prop"])
            self.send(status, body, "text/plain")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            self.fail(url.path, e)

    def fail(self, path, e):
        say(f"error on {path}: {e}")
        # The response may have been cut off half-way, so this connection can't carry another.
        self.close_connection = True
        try:
            self.send(502, str(e).encode(), "text/plain")
        except Exception:
            pass


class RemoteHandler(Handler):
    """The tunnel listener (see Remote)."""
    remote = True


class TunnelListener:
    """The tunnel port (see Remote): opened at start with --tunnel-port, or while running by the
    LfS app's "tunnel" command when remote sharing is turned on, and closed again when it's
    turned off. Changing it never disturbs the main port, so viewers in the studio stay connected."""
    server = None

    @classmethod
    def open(cls, port):
        """Listen on 127.0.0.1:port; raises OSError if the port is taken."""
        server = Server(("127.0.0.1", port), RemoteHandler)
        cls.close()
        threading.Thread(target=server.serve_forever, daemon=True).start()
        cls.server, Handler.tunnel_port = server, port
        STATUS["tunnelPort"] = port

    @classmethod
    def close(cls):
        server, cls.server = cls.server, None
        if server:
            server.shutdown()      # stops accepting; requests already running finish on their own
            server.server_close()
        Handler.tunnel_port = 0
        STATUS["tunnelPort"] = None


# What the LfS app is told about (see Control); kept up to date by main() and Monitor.
STATUS = {
    "c1": {"state": "waiting", "url": None, "session": ""},
    "port": None, "local": False, "urls": {}, "tunnelPort": None,
    "viewers": {"total": 0, "remote": 0},
    "devices": [],
}


def url_info(port, local):
    """The viewer's addresses, as the LfS app shows them."""
    info = {"local": f"http://localhost:{port}", "network": [], "bonjour": None}
    if not local:
        for name, url in network_urls(port):
            if name == "bonjour":
                info["bonjour"] = url
            else:
                info["network"].append({"interface": name, "url": url})
    return info


FOLDERS = {}  # folder id -> path, for the Viewers panel; kept up to date by Monitor


def known_session(c1):
    """The open session's name: as the Monitor last saw it (every few seconds), or asked now."""
    c = STATUS["c1"]
    if c.get("state") == "connected" and c.get("session") and c.get("url") == c1.base:
        return c["session"]
    try:
        return session_name(c1)
    except Exception:
        return ""


def session_name(c1, timeout=10):
    """The session's name; also refreshes FOLDERS from the same answer."""
    status, body = c1.call("getServerStateForLive", {"collectionID": ""}, timeout=timeout)
    if status != 200:
        raise RuntimeError(f"Capture One answered {status}")
    obj = (json.loads(body).get("objects") or [{}])[0]
    for c in obj.get("kObjectKey_Collections", []):
        FOLDERS[c.get("kObjectCollectionKey_id", "")] = (c.get("kObjectCollectionKey_relativePath")
                                                          or c.get("kObjectCollectionKey_name", ""))
    return obj.get("kObjectKey_ObjectName", "")


class Monitor:
    """Every few seconds: is Capture One still there, how many pages are open (and which devices,
    with the data sent to each), and have the network addresses changed? Changes are printed and
    sent to the LfS app as events."""

    EVERY = 5  # seconds

    def __init__(self, c1, feeds, port, local):
        self.c1, self.feeds, self.port, self.local = c1, feeds, port, local
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        tick = 0
        while True:
            time.sleep(self.EVERY)
            tick += 1
            self._check_c1()
            total, remote = self.feeds.viewers()
            if STATUS["viewers"] != {"total": total, "remote": remote}:
                STATUS["viewers"] = {"total": total, "remote": remote}
                emit("viewers", total=total, remote=remote)
            report_devices()
            if tick % 6 == 0:  # Wi-Fi switched, a cable plugged in...
                urls = url_info(self.port, self.local)
                if urls != STATUS["urls"]:
                    STATUS["urls"] = urls
                    emit("addresses", urls=urls)

    def _check_c1(self):
        c1 = STATUS["c1"]
        try:
            name = session_name(self.c1)
        except (TimeoutError, urllib.error.URLError) as e:
            if isinstance(getattr(e, "reason", e), TimeoutError):
                return  # slow (it can be, while importing a capture), but there
            name = None
        except Exception:
            name = None
        if name is None and c1["state"] == "connected":
            c1["state"] = "lost"
            say("Lost Capture One. Is it still open, with Live for Studio sharing? "
                "The viewer reconnects by itself when it's back.")
            emit("c1", **c1)
        elif name is not None and (c1["state"] != "connected" or c1["url"] != self.c1.base or c1["session"] != name):
            if c1["state"] == "lost":
                say("Capture One is back.")
            c1.update(state="connected", url=self.c1.base, session=name)
            emit("c1", **c1)


def report_devices(force=False):
    """Send the LfS app the device list (see Devices) when it has changed."""
    devices = Handler.devices.snapshot(FOLDERS)
    if force or devices != STATUS["devices"]:
        STATUS["devices"] = devices
        emit("devices", devices=devices)


def device_command(cmd, msg):
    """Remove (block) or unblock a device, or stop or allow its rating (see Devices)."""
    a, device = Handler.access, str(msg.get("device", ""))
    if not DEVICE_FORMAT.fullmatch(device):
        raise ValueError("Choose a device.")
    if cmd == "block":
        info = Handler.devices.info(device)
        if info is None:
            raise ValueError("That device isn't connected any more.")
        if info["owner"]:
            raise ValueError("This Mac can't be removed.")
        who = info["email"] or info["ip"]
        a.block(device, {"name": info["name"], "where": Devices.where(info), "ip": info["ip"],
                         "email": info["email"], "blockedAt": time.time()})
        Handler.feeds.retire_device(device)  # its open page is cut off now, not at its next request
        say(f"Removed {info['name']} ({who}).")
    elif cmd == "unblock":
        if not a.unblock(device):
            raise ValueError("That device isn't removed.")
        say("A removed device may watch again.")
    elif cmd == "rating":
        allow = msg.get("allow")
        if type(allow) is not bool:
            raise ValueError('Say "allow": true or false.')
        a.set_device_rating(device, allow)
    report_devices(force=True)


def command(msg):
    """Carry out one command from the LfS app (see Control). Returns the reply's extra fields;
    raises ValueError with a message the app can show."""
    a, cmd = Handler.access, msg.get("cmd")
    if cmd in ("block", "unblock", "rating"):
        device_command(cmd, msg)
        return {}
    if cmd == "access":
        mode, pin = msg.get("mode"), str(msg.get("pin", ""))
        error = Access.mode_error(mode, pin)
        if error:
            raise ValueError(error)
        a.set_mode(mode, pin)
        say(f"Network access changed to: {ACCESS_LABELS[mode]}")
    elif cmd == "lockout":
        tries, seconds = msg.get("maxFails"), msg.get("seconds")
        if type(tries) is not int or type(seconds) is not int or not 1 <= tries <= 20 or not 10 <= seconds <= 3600:
            raise ValueError("Allow 1 to 20 wrong tries, then a wait of 10 to 3600 seconds.")
        a.update(max_fails=tries, lockout=seconds)
    elif cmd == "remote":
        view, code = msg.get("view"), msg.get("code", a.data["remote_code"])
        if view not in Access.REMOTE_VIEWS:
            raise ValueError('Remote view must be "code" or "open".')
        if not isinstance(code, str) or (code and not re.fullmatch(r"\d{6,12}", code)):
            raise ValueError("Use a viewing code of 6 to 12 digits.")
        if view == "code" and not code:
            raise ValueError("Set a viewing code first.")
        a.update(remote_view=view, remote_code=code)
    elif cmd == "wording":
        who = " ".join(str(msg.get("operator", "")).split())  # one line, single spaces
        if not 1 <= len(who) <= 40 or not who.isprintable():
            raise ValueError("Use 1 to 40 characters, for example \"the digi-tech\".")
        a.update(operator=who)
        say(f"Visitors' pages now say: {who}.")
    elif cmd == "signout":
        a.sign_out_all()
        say("Signed out every device: PINs and viewing codes must be entered again.")
    elif cmd == "tunnel":
        port = msg.get("port")
        if port is None:
            if TunnelListener.server:
                TunnelListener.close()
                say("Tunnel port closed: remote sharing is off.")
        elif type(port) is not int or not 1024 <= port <= 65535:
            raise ValueError("Use a tunnel port from 1024 to 65535.")
        elif port != STATUS["tunnelPort"]:
            try:
                TunnelListener.open(port)
            except OSError:
                raise ValueError(f"Port {port} is in use. Choose another tunnel port in Settings.")
            say(f"  Tunnel:           http://localhost:{port}   (point cloudflared here)")
        emit("tunnel", port=STATUS["tunnelPort"])
        return {}
    else:
        raise ValueError(f"Unknown command: {cmd!r}")
    emit("settings", settings=a.settings())
    return {}


def listen_for_commands():
    """Read the LfS app's commands from stdin until it closes (see Control)."""
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
            if not isinstance(msg, dict):
                raise ValueError("Send one JSON object per line.")
        except ValueError:
            emit("reply", id=None, ok=False, error="Send one JSON object per line.")
            continue
        rid = msg.get("id")
        if msg.get("cmd") == "status":
            emit("status", id=rid, **STATUS, settings=Handler.access.settings())
            continue
        if msg.get("cmd") == "stop":
            emit("reply", id=rid, ok=True)
            break
        try:
            emit("reply", id=rid, ok=True, **command(msg))
        except ValueError as e:
            emit("reply", id=rid, ok=False, error=str(e))
    STOP.set()  # stdin closed (the app quit or crashed) or "stop": shut down


def main():
    ap = argparse.ArgumentParser(description="View a Capture One Live for Studio session in a browser.")
    ap.add_argument("--port", type=int, default=8787,
                    help="port for the web page (default 8787; if it's taken, the next free one, skipping the tunnel's)")
    ap.add_argument("--c1", help="Capture One Live server as host:port (default: auto-detect on this Mac)")
    ap.add_argument("--local", action="store_true",
                    help="only this Mac can open the viewer (default: anyone on your network can)")
    ap.add_argument("--lan", action="store_true", help=argparse.SUPPRESS)  # old flag; LAN is now the default
    ap.add_argument("--debug", action="store_true", help="print each change message from Capture One")
    ap.add_argument("--no-open", action="store_true", help="don't open the browser automatically")
    ap.add_argument("--session", help="path to the .cosessiondb file for exposure info (default: find it)")
    ap.add_argument("--tunnel-port", type=int, help="also listen on 127.0.0.1:PORT for a Cloudflare tunnel (see Remote)")
    ap.add_argument("--control", action="store_true", help="run by the LfS app: events on stdout, commands on stdin")
    ap.add_argument("--settings", help="where to keep settings.json (default: next to this script)")
    args = ap.parse_args()
    global DEBUG, CONTROL, SETTINGS
    DEBUG, CONTROL = args.debug, args.control
    if args.settings:
        SETTINGS = os.path.abspath(os.path.expanduser(args.settings))
        os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    Handler.exposure = Exposure(args.session)
    Handler.access = Access()
    Handler.devices = Devices(Handler.access)
    signal.signal(signal.SIGTERM, _terminate)  # the app's fallback Stop, or a logout
    if CONTROL:
        emit("settings", settings=Handler.access.settings())
        threading.Thread(target=listen_for_commands, daemon=True).start()

    try:
        # Wait for Capture One rather than giving up, so the viewer can be started first.
        base = f"http://{args.c1}" if args.c1 else find_capture_one()
        if not base:
            say("Waiting for Capture One... open it and turn on Live for Studio. (Ctrl-C to quit)")
            emit("c1", **STATUS["c1"])
            while not base:
                if wait_for_stop(3):
                    raise KeyboardInterrupt  # stopped before Capture One turned up: same tidy exit
                base = find_capture_one()
        c1 = CaptureOne(base, rediscover=not args.c1)
        sid = c1.connect()
        Handler.c1 = c1
        Handler.pictures = Pictures(c1, Handler.exposure)
        Handler.latest = Latest(c1, Handler.exposure)
        Handler.counts = FolderCounts(c1, Handler.exposure)
        Handler.feeds = Feeds(c1)
        try:
            name = session_name(c1, timeout=30)
        except Exception:
            name = ""  # the monitor fills it in
        STATUS["c1"].update(state="connected", url=base, session=name)
        emit("c1", **STATUS["c1"])

        # If the port is taken (for example the viewer is already running), use the next free one.
        host = "127.0.0.1" if args.local else "0.0.0.0"
        server = None
        # The tunnel's port is never taken for this: the Cloudflare tunnel is set up to reach it.
        for port in range(args.port, args.port + 10):
            if port == args.tunnel_port:
                continue
            try:
                server = Server((host, port), Handler)
                break
            except OSError:
                continue
        if server is None:
            message = f"Ports {args.port}-{args.port + 9} are all in use. Is the viewer already running?"
            emit("error", message=message)
            sys.exit(message)
        server.daemon_threads = True
        Handler.port = port
        if port != args.port:
            say(f"Port {args.port} is in use, so the viewer is on {port} instead. Addresses with "
                f"{args.port} won't work; choose a free port to keep them the same.")

        # The tunnel's port is fixed: the Cloudflare tunnel is set up to reach exactly this one.
        if args.tunnel_port:
            try:
                TunnelListener.open(args.tunnel_port)
            except OSError:
                message = f"Port {args.tunnel_port} for the tunnel is in use, so remote sharing is off."
                say(message)
                emit("error", message=message)
        tunnel = TunnelListener.server

        STATUS.update(port=port, local=args.local, urls=url_info(port, args.local))
        emit("listening", port=port, requestedPort=args.port, local=args.local, urls=STATUS["urls"],
             tunnelPort=STATUS["tunnelPort"])
        Monitor(c1, Handler.feeds, port, args.local)

        url = f"http://localhost:{port}"
        say(f"Connected to Capture One ({base}, session {sid}).\n")
        say(f"  On this Mac:      {url}")
        if not args.local:
            urls = STATUS["urls"]
            for n in urls["network"]:
                say(f"  On your network:  {n['url']}   ({n['interface']})")
            if urls["bonjour"]:
                say(f"  Apple devices:    {urls['bonjour']}")
            if not urls["network"]:
                say("  (No network connection found; only this Mac can open the viewer.)")
        if tunnel:
            say(f"  Tunnel:           http://localhost:{args.tunnel_port}   (point cloudflared here)")
        if not args.local or tunnel:
            say(f"\nRating and tagging: this Mac always can; {ACCESS_LABELS[Handler.access.mode]}.")
            say("  Change it in the LfS app." if CONTROL else "  Change it in the viewer on this Mac: ☰ menu > Network access.")
        say("\nLeave this window open while you use the viewer. Ctrl-C to stop.")
        if not args.no_open:
            webbrowser.open(url)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        wait_for_stop()  # Ctrl-C and SIGTERM interrupt this too
        raise KeyboardInterrupt  # stopped by the app: the same tidy exit as Ctrl-C
    except KeyboardInterrupt:
        say("\nStopped.")
    finally:
        if Handler.feeds:
            Handler.feeds.close_all()  # tidy up the change feeds' Capture One sessions
        emit("stopped")
        flush_out()


if __name__ == "__main__":
    main()
