"""The engine's test harness: a fake Capture One, and studio_viewer.py run the way the app runs it
(--control), driven over stdin/stdout and HTTP. Covers the control protocol, the viewing code and
PIN, lockouts, devices (remove, stop rating), visitors' wording, Capture One going away and coming
back, the tunnel port, unread output, a taken port, stopping, and plain script mode.

    python3 -I tests/test_engine.py                       # this Mac's Python
    App/Python/python/bin/python3 -I tests/test_engine.py  # the app's bundled one

Uses ports 8795, 8796 (viewer, tunnel) and 8799 (the fake Capture One) on 127.0.0.1, and a
settings file in a temporary folder. Takes about two minutes. Exits non-zero if anything fails.
"""
import json, os, queue, subprocess, sys, tempfile, threading, time, urllib.request, urllib.error, signal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ENGINE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "studio_viewer.py")
SETTINGS = os.path.join(tempfile.mkdtemp(prefix="studioviewer-test-"), "settings.json")
STUB_PORT, MAIN, TUNNEL = 8799, 8795, 8796
PREFIX = "@sv "  # the engine's event lines (see Control in studio_viewer.py)
SET_CALLS = []


class Stub(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/connectToServiceForLive": body = b"123"
        elif p == "/getServerStateForLive":
            body = json.dumps({"objects": [{"kObjectKey_ObjectName": "STUB SESSION", "kObjectKey_Collections": []}], "variants": []}).encode()
        elif p == "/getServerChangesForLive": time.sleep(2); body = b""
        elif p == "/setPropertyForLive": SET_CALLS.append(self.path); body = b""
        else: body = b""
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)


def start_stub():
    s = ThreadingHTTPServer(("127.0.0.1", STUB_PORT), Stub); s.daemon_threads = True
    threading.Thread(target=s.serve_forever, daemon=True).start(); return s


class Viewer:
    def __init__(self, *extra, ignore_sigint=False):
        # ignore_sigint: as when started in the background, where SIGINT is ignored
        self.p = subprocess.Popen([sys.executable, "-u", ENGINE, "--c1", f"127.0.0.1:{STUB_PORT}", "--port", str(MAIN),
                                   "--no-open", "--local", "--settings", SETTINGS, *extra],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                  preexec_fn=(lambda: signal.signal(signal.SIGINT, signal.SIG_IGN)) if ignore_sigint else None)
        self.events, self.log = queue.Queue(), []
        threading.Thread(target=self._read, daemon=True).start()
    def _read(self):
        for line in self.p.stdout:
            line = line.rstrip("\n")
            if line.startswith(PREFIX): self.events.put(json.loads(line[len(PREFIX):]))
            else: self.log.append(line)
    def send(self, **cmd):
        self.p.stdin.write(json.dumps(cmd) + "\n"); self.p.stdin.flush()
    def wait(self, event, timeout=15, **match):
        """Next matching event; events skipped over stay available for later waits."""
        end = time.time() + timeout
        if not hasattr(self, "backlog"): self.backlog = []
        while True:
            for e in self.backlog:
                if e["event"] == event and all(e.get(k) == v for k, v in match.items()):
                    self.backlog.remove(e); return e
            try: self.backlog.append(self.events.get(timeout=max(0.05, end - time.time())))
            except queue.Empty: pass
            if time.time() >= end: raise AssertionError(f"no {event} {match} within {timeout}s")


def http(method, port, path, data=None, headers=None):
    h = {"X-StudioViewer": "1", **(headers or {})}
    body = json.dumps(data).encode() if data is not None else None
    if body: h["Content-Type"] = "application/json"
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=body, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status, r.read().decode(), dict(r.headers)
    except urllib.error.HTTPError as e: return e.code, e.read().decode(), dict(e.headers)


results = []
def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS " if cond else "FAIL ") + name + (f"   [{detail}]" if not cond and detail else ""))


def cookie_of(headers, name):
    sc = headers.get("Set-Cookie", "")
    return sc.split(";")[0] if sc.startswith(name + "=") else None


stub = start_stub()
v = Viewer("--control", "--tunnel-port", str(TUNNEL))
e = v.wait("settings"); check("settings event at start", e["settings"]["mode"] == "view" and e["settings"]["remoteView"] == "code")
e = v.wait("c1", state="connected"); check("c1 connected with session name", e["session"] == "STUB SESSION", e)
e = v.wait("listening"); check("listening event", e["port"] == MAIN and e["tunnelPort"] == TUNNEL and e["urls"]["local"] == f"http://localhost:{MAIN}", e)

v.send(cmd="status", id=7); e = v.wait("status")
check("status reply carries id + everything", e["id"] == 7 and e["c1"]["state"] == "connected" and "settings" in e and e["port"] == MAIN, e)

s, b, _ = http("GET", MAIN, "/api/access"); a = json.loads(b)
check("main /api/access: owner, managed, no PIN/addresses", a["isOwner"] and a["managed"] and "pin" not in a and "addresses" not in a, a)
s, b, _ = http("POST", MAIN, "/api/access", {"mode": "open"})
check("main POST /api/access refused under control", s == 403 and "StudioViewer app" in b, (s, b))
s, b, _ = http("POST", MAIN, "/api/looking", {"photo": ""}, {"X-StudioViewer": ""})
s2, b2, _ = http("POST", MAIN, "/api/looking", {"photo": ""}, {"X-StudioViewer": "", "X-LfS": "1"})
check("POST without the X-StudioViewer header refused (the old X-LfS too)", s == 403 and s2 == 403, (s, s2))
s, b, _ = http("GET", MAIN, "/api/access", headers={"Cf-Ray": "abc"})
check("main port refuses Cloudflare traffic", s == 403 and f"localhost:{TUNNEL}" in b, (s, b))

s, b, _ = http("GET", TUNNEL, "/")
check("tunnel / without code -> gate page", s == 200 and "viewing code" in b and "<title>StudioViewer</title>" in b and "pRate" not in b, s)
s, b, _ = http("GET", TUNNEL, "/api/state?c=")
check("tunnel API without code -> 401", s == 401, s)
s, b, _ = http("POST", TUNNEL, "/api/set?c=&id=1/1&prop=rating&value=3")
check("tunnel POST without code -> 401", s == 401, s)
s, b, _ = http("POST", TUNNEL, "/api/view", {"code": "123456"})
check("view code before set up -> not set up", s == 403 and "set up" in b, (s, b))

v.send(cmd="remote", view="code", code="12345", id=1); e = v.wait("reply", id=1)
check("remote: 5-digit code rejected", not e["ok"] and "6 to 12" in e["error"], e)
v.send(cmd="remote", view="code", code="482916", id=2); e = v.wait("reply", id=2)
s2 = v.wait("settings"); check("remote: code set + settings event", e["ok"] and s2["settings"]["remoteCode"] == "482916", (e, s2))

s, b, _ = http("POST", TUNNEL, "/api/view", {"code": "000000"}, {"Cf-Connecting-Ip": "203.0.113.1"})
check("wrong view code", s == 403 and "Wrong code" in b, (s, b))
s, b, h = http("POST", TUNNEL, "/api/view", {"code": "482916"}, {"Cf-Connecting-Ip": "203.0.113.1", "X-Forwarded-Proto": "https"})
view = cookie_of(h, "lfs_view")
check("right view code -> lfs_view cookie, Secure over https", s == 200 and view and "Secure" in h.get("Set-Cookie", ""), h.get("Set-Cookie"))
s, b, _ = http("GET", TUNNEL, "/", headers={"Cookie": view})
check("tunnel / with cookie -> the viewer", s == 200 and "pRate" in b, s)
s, b, _ = http("GET", TUNNEL, "/api/access", headers={"Cookie": view})
a = json.loads(b); check("tunnel visitor is never owner, can't rate in view mode", not a["isOwner"] and a["remote"] and not a["canRate"], a)
s, b, _ = http("POST", TUNNEL, "/api/set?c=&id=1/1&prop=rating&value=3", headers={"Cookie": view})
check("tunnel rating refused in view mode", s == 403, s)

v.send(cmd="access", mode="pin", pin="1801", id=3); e = v.wait("reply", id=3)
check("access cmd -> pin mode", e["ok"])
s, b, _ = http("GET", TUNNEL, "/api/state?c=", headers={"Cookie": view})
check("a new rating PIN doesn't sign remote viewers out", s == 200, s)
s, b, h = http("POST", TUNNEL, "/api/unlock", {"pin": "1801"}, {"Cookie": view, "Cf-Connecting-Ip": "203.0.113.1"})
auth = cookie_of(h, "lfs_auth")
check("remote PIN unlock -> lfs_auth", s == 200 and auth, (s, b))
n = len(SET_CALLS)
s, b, _ = http("POST", TUNNEL, "/api/set?c=&id=1/1&prop=rating&value=3", headers={"Cookie": f"{view}; {auth}"})
check("remote rating after PIN reaches Capture One", s == 200 and len(SET_CALLS) == n + 1, s)
s, b, _ = http("POST", MAIN, "/api/set?c=&id=1/1&prop=rating&value=2")
check("owner on main port can rate", s == 200, s)

v.send(cmd="lockout", maxFails=0, seconds=60, id=4); e = v.wait("reply", id=4)
check("lockout: 0 tries rejected", not e["ok"], e)
v.send(cmd="lockout", maxFails=3, seconds=30, id=5); e = v.wait("reply", id=5)
check("lockout: 3 tries / 30 s accepted", e["ok"], e)
for i in range(3):
    s, b, _ = http("POST", TUNNEL, "/api/view", {"code": "111111"}, {"Cf-Connecting-Ip": "198.51.100.9"})
check("per-visitor lockout after 3 tries", s == 403 and "Wait 30" in b, b)
s, b, _ = http("POST", TUNNEL, "/api/view", {"code": "111111"}, {"Cf-Connecting-Ip": "198.51.100.10"})
check("another visitor isn't locked out", s == 403 and b.find("Wrong code") >= 0, b)

# viewers: open a feed through the tunnel
s, b, _ = http("GET", TUNNEL, "/api/state?c=&client=testclient01&feed=testfeed0001", headers={"Cookie": view})
e = v.wait("viewers", total=1, remote=1, timeout=12); check("viewers event counts the remote page", True)

v.send(cmd="bogus", id=6); e = v.wait("reply", id=6); check("unknown command -> error reply", not e["ok"], e)
v.p.stdin.write("not json\n"); v.p.stdin.flush(); e = v.wait("reply"); check("bad line -> error reply", not e["ok"], e)

v.send(cmd="signout", id=8); e = v.wait("reply", id=8)
s, b, _ = http("GET", TUNNEL, "/api/state?c=", headers={"Cookie": view})
check("sign out all -> old view cookie gets 401", e["ok"] and s == 401, s)
s, b, h = http("POST", TUNNEL, "/api/view", {"code": "482916"}, {"Cf-Connecting-Ip": "203.0.113.1"})
view2 = cookie_of(h, "lfs_view")
s, b, _ = http("GET", TUNNEL, "/api/access", headers={"Cookie": f"{view2}; {auth}"})
check("...and the old PIN unlock no longer works either", s == 200 and not json.loads(b)["unlocked"], b)

s, b, _ = http("GET", MAIN, "/api/counts")
check("folder counts endpoint answers (stub has no folders)", s == 200 and json.loads(b) == {}, (s, b))

# devices: the Viewers panel's list, data counts, removing, per-device rating
IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
def wait_devices(pred, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        e = v.wait("devices", timeout=max(0.5, end - time.time()))
        if pred(e["devices"]):
            return e["devices"]
    raise AssertionError("devices event never matched")
remote_h = {"Cookie": view2, "Cf-Connecting-Ip": "203.0.113.77", "X-Forwarded-Proto": "https", "User-Agent": IPHONE,
            "Cf-Access-Authenticated-User-Email": "client@agency.test", "Cf-Ipcountry": "GB"}
s1, b1, h1 = http("GET", TUNNEL, "/api/access", headers=remote_h)
dev = cookie_of(h1, "lfs_device")
check("first request gets a device cookie (Secure over https)", s1 == 200 and dev and len(dev.split("=")[1]) == 32
      and "Secure" in h1.get("Set-Cookie", ""), h1.get("Set-Cookie"))
dev_id = dev.split("=")[1]
remote_h["Cookie"] = f"{view2}; {dev}"
s2, b2, h2 = http("GET", TUNNEL, "/api/state?c=&client=devclient01&feed=devfeed0001", headers=remote_h)
check("known device gets no new cookie", cookie_of(h2, "lfs_device") is None)
devs = wait_devices(lambda ds: any(d["id"] == dev_id for d in ds))
d = next(d for d in devs if d["id"] == dev_id)
check("device listed: iPhone · Safari, remote, Access email, country, IP",
      d["name"] == "iPhone · Safari" and d["where"] == "remote" and d["email"] == "client@agency.test"
      and d["country"] == "GB" and d["ip"] == "203.0.113.77", d)
check("data sent is counted for the device, with when it connected",
      d["bytes"] >= len(b1) + len(b2) and d["since"] and not d["left"] and d["lastSeen"] is None, (d["bytes"], len(b1) + len(b2), d))
s, b, h = http("GET", MAIN, "/api/access")
own = cookie_of(h, "lfs_device").split("=")[1]
v.send(cmd="block", device=own, id=40); r = v.wait("reply", id=40)
check("this Mac can't be removed", not r["ok"] and "can't be removed" in r["error"], r)
v.send(cmd="block", device="nothex", id=41); r = v.wait("reply", id=41)
check("block with a bad id -> error", not r["ok"], r)

# per-device rating: in "open" mode the device may rate, until stopped
v.send(cmd="access", mode="open", pin="", id=42); v.wait("reply", id=42)
s, b, _ = http("POST", TUNNEL, "/api/set?c=&id=1/1&prop=rating&value=3", headers=remote_h)
check("remote device can rate in open mode", s == 200, s)
v.send(cmd="rating", device=dev_id, allow=False, id=43); r = v.wait("reply", id=43)
e = {"devices": wait_devices(lambda ds: any(x["id"] == dev_id and x.get("ratingBlocked") for x in ds))}
s, b, _ = http("POST", TUNNEL, "/api/set?c=&id=1/1&prop=rating&value=3", headers=remote_h)
s3, b3, _ = http("GET", TUNNEL, "/api/access", headers=remote_h)
dd = next(x for x in e["devices"] if x["id"] == dev_id)
check("stop rating on one device -> refused, shown in list", r["ok"] and s == 403 and not json.loads(b3)["canRate"]
      and dd["ratingBlocked"] and not dd["canRate"], (s, b3, dd))
v.send(cmd="rating", device=dev_id, allow=True, id=44); v.wait("reply", id=44)
s, b, _ = http("POST", TUNNEL, "/api/set?c=&id=1/1&prop=rating&value=3", headers=remote_h)
check("allow rating again -> accepted", s == 200, s)
v.send(cmd="access", mode="pin", pin="1801", id=45); v.wait("reply", id=45)

# removing
v.send(cmd="block", device=dev_id, id=46); r = v.wait("reply", id=46)
e = {"devices": wait_devices(lambda ds: any(x["blocked"] for x in ds))}
s, b, _ = http("GET", TUNNEL, "/api/state?c=", headers=remote_h)
s4, b4, _ = http("GET", TUNNEL, "/", headers=remote_h)
blocked = [x for x in e["devices"] if x["blocked"]]
check("removed device: API 401, page says removed", r["ok"] and s == 401 and s4 == 200 and "This device was removed" in b4, (s, s4))
check("removed list keeps name and email", blocked and blocked[0]["name"] == "iPhone · Safari"
      and blocked[0]["email"] == "client@agency.test" and blocked[0]["id"] == dev_id, blocked)
s, b, _ = http("GET", TUNNEL, "/api/access", headers={**remote_h, "Cookie": view2})
check("another device (no cookie) still gets in", s == 200, s)
v.send(cmd="unblock", device=dev_id, id=47); r = v.wait("reply", id=47)
s, b, _ = http("GET", TUNNEL, "/api/state?c=", headers=remote_h)
check("unblock -> device watches again", r["ok"] and s == 200, (r, s))
v.send(cmd="unblock", device=dev_id, id=48); r = v.wait("reply", id=48)
check("unblock a device that isn't removed -> error", not r["ok"], r)
v.send(cmd="block", device=dev_id, id=49); v.wait("reply", id=49)  # stays removed: checked after a restart below

# wording: how visitors' pages name whoever runs the viewer
s, b, _ = http("GET", TUNNEL, "/", headers={"Cf-Connecting-Ip": "198.51.100.77"})
check("gate page says 'the photographer' by default", "Enter the viewing code the photographer gave you." in b, b[-400:])
v.send(cmd="wording", operator="the digi-tech", id=60); r = v.wait("reply", id=60)
s, b, _ = http("GET", TUNNEL, "/", headers={"Cf-Connecting-Ip": "198.51.100.77"})
s2, b2, _ = http("GET", TUNNEL, "/", headers=remote_h)          # dev_id is removed
s3, b3, _ = http("GET", TUNNEL, "/api/state?c=", headers=remote_h)
check("wording reaches the gate page, the removed page and the API error",
      r["ok"] and "the viewing code the digi-tech gave you" in b and "The digi-tech has removed this device" in b2
      and "removed by the digi-tech" in b3, (r, b2[-300:], b3))
v.send(cmd="wording", operator="<b>Bo & Co</b>", id=61); v.wait("reply", id=61)
s, b, _ = http("GET", TUNNEL, "/", headers={"Cf-Connecting-Ip": "198.51.100.77"})
check("a name with HTML is shown as text, not run", "&lt;b&gt;Bo &amp; Co&lt;/b&gt;" in b and "<b>Bo" not in b, b[-300:])
for bad in ["", "x" * 41, "   "]:
    v.send(cmd="wording", operator=bad, id=62); r = v.wait("reply", id=62)
    check(f"wording {bad[:12]!r} rejected", not r["ok"], r)
v.send(cmd="wording", operator="  two\n  lines ", id=65); v.wait("reply", id=65)
v.send(cmd="status", id=63); e = v.wait("status", id=63)
check("pasted line breaks and spaces are tidied", e["settings"]["operator"] == "two lines", e["settings"])
v.send(cmd="wording", operator="the photographer", id=64); v.wait("reply", id=64)

# Capture One goes away and comes back
stub.shutdown(); stub.server_close()
e = v.wait("c1", state="lost", timeout=15); check("c1 lost event", True)
check("lost message in log", any("Lost Capture One" in l for l in v.log))
stub = start_stub()
e = v.wait("c1", state="connected", timeout=15); check("c1 back event", e["session"] == "STUB SESSION")

# global remote cap (last: it lasts 10 minutes)
v.send(cmd="lockout", maxFails=20, seconds=60, id=9); v.wait("reply", id=9)
v.send(cmd="remote", view="code", code="482916", id=10); v.wait("reply", id=10)
for i in range(25):
    http("POST", TUNNEL, "/api/view", {"code": "999999"}, {"Cf-Connecting-Ip": f"192.0.2.{i}"})
e = v.wait("guessing", timeout=5); check("guessing event after 20 wrong remote guesses", e["wait"] == 600)
s, b, _ = http("POST", TUNNEL, "/api/view", {"code": "482916"}, {"Cf-Connecting-Ip": "192.0.2.200"})
check("right code from a new address is paused too", s == 403 and "Too many" in b, b)
s, b, _ = http("POST", MAIN, "/api/unlock", {"pin": "1801"})
check("devices in the studio aren't affected by the remote pause", s == 200, (s, b))

# the tunnel port, opened and closed while running
v.send(cmd="tunnel", port=None, id=20); e = v.wait("tunnel"); v.wait("reply", id=20)
check("tunnel close -> event with null port", e["port"] is None)
try:
    http("GET", TUNNEL, "/"); closed = False
except Exception:
    closed = True
check("closed tunnel port refuses connections", closed)
s, b, _ = http("GET", MAIN, "/api/access")
check("main port unaffected by closing the tunnel", s == 200)
v.send(cmd="tunnel", port=TUNNEL, id=21); e = v.wait("tunnel"); r = v.wait("reply", id=21)
s, b, _ = http("GET", TUNNEL, "/")
check("tunnel reopen -> gate page served", r["ok"] and e["port"] == TUNNEL and s == 200 and "viewing code" in b, (r, e, s))
v.send(cmd="tunnel", port=MAIN, id=22); r = v.wait("reply", id=22)
check("tunnel on a port in use -> clear error", not r["ok"] and "in use" in r["error"], r)
v.send(cmd="tunnel", port=80, id=23); r = v.wait("reply", id=23)
check("tunnel on a privileged port -> rejected", not r["ok"], r)
v.send(cmd="status", id=24); e = v.wait("status", id=24)
check("status reports the open tunnel port", e["tunnelPort"] == TUNNEL, e["tunnelPort"])

v.send(cmd="stop", id=11); e = v.wait("reply", id=11); v.wait("stopped")
check("stop -> exits", v.p.wait(timeout=10) is not None)

# stdin closing stops it; SIGTERM stops it
v = Viewer("--control"); v.wait("listening"); v.p.stdin.close(); v.wait("stopped")
check("stdin EOF -> exits", v.p.wait(timeout=10) is not None)
v = Viewer("--control"); v.wait("listening"); v.p.send_signal(signal.SIGTERM); v.wait("stopped")
check("SIGTERM -> exits", v.p.wait(timeout=10) is not None)
v = Viewer("--control", ignore_sigint=True); v.wait("listening"); v.p.send_signal(signal.SIGTERM)
check("started in the background (SIGINT ignored): SIGTERM still stops it", v.p.wait(timeout=10) is not None)

# SIGTERM at random moments (and twice in a row) must always end the viewer, never deadlock it
import random
ends = []
for i in range(5):
    w = Viewer("--control", ignore_sigint=True); w.wait("listening")
    time.sleep(random.uniform(0, 1.2))
    w.p.send_signal(signal.SIGTERM)
    if i % 2:
        time.sleep(0.05); w.p.send_signal(signal.SIGTERM)
    try:
        ends.append(w.p.wait(timeout=10))
    except subprocess.TimeoutExpired:
        w.p.kill(); ends.append("HUNG")
check("SIGTERM x5 at random moments: always exits", "HUNG" not in ends, ends)

# nobody reading the viewer's output: it must keep serving and taking commands, not freeze
q = subprocess.Popen([sys.executable, "-u", ENGINE, "--c1", f"127.0.0.1:{STUB_PORT}", "--port", str(MAIN), "--no-open",
                      "--local", "--settings", SETTINGS, "--control", "--tunnel-port", str(TUNNEL)],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
time.sleep(2.5)
for i in range(4000):  # each answer is a line on stdout, which nobody reads: the pipe fills up
    q.stdin.write(json.dumps({"cmd": "status", "id": i}) + "\n")
q.stdin.flush()
time.sleep(1.5)
t = time.time()
answers = [http("GET", MAIN, "/api/access")[0] for _ in range(3)]
for i in range(22):  # wrong remote codes: past the cap the viewer logs a line and emits an event
    http("POST", TUNNEL, "/api/view", {"code": "000000"}, {"Cf-Connecting-Ip": f"192.0.2.{100 + i}"})
answers.append(http("GET", MAIN, "/api/access")[0])
check("output unread: requests still answered promptly", all(a == 200 for a in answers) and time.time() - t < 10, (answers, time.time() - t))
q.stdin.write(json.dumps({"cmd": "wording", "operator": "the operator"}) + "\n"); q.stdin.flush()
time.sleep(1)
s, b, _ = http("GET", TUNNEL, "/", headers={"Cf-Connecting-Ip": "198.51.100.88"})
check("output unread: commands still carried out", "the operator gave you" in b, b[-200:])
q.stdin.write(json.dumps({"cmd": "wording", "operator": "the photographer"}) + "\n"); q.stdin.write(json.dumps({"cmd": "stop"}) + "\n"); q.stdin.flush()
check("output unread: still stops when asked", q.wait(timeout=15) is not None)

# the viewer's port is taken: it moves to the next free one, never onto the tunnel's, and says so
import socket
blocker = socket.socket(); blocker.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)  # past TIME_WAIT, like the viewer
blocker.bind(("127.0.0.1", MAIN)); blocker.listen()  # the same address the --local viewer wants
w = Viewer("--control", "--tunnel-port", str(TUNNEL))   # TUNNEL is MAIN + 1
e = w.wait("listening")
check("port taken: viewer skips the tunnel port and reports the move",
      e["requestedPort"] == MAIN and e["port"] > TUNNEL and e["tunnelPort"] == TUNNEL, e)  # next free after the tunnel's
time.sleep(0.5)
check("port taken: the window says so", any(f"Port {MAIN} is in use, so the viewer is on {e['port']}" in l for l in w.log), w.log[-6:])
w.send(cmd="stop"); w.wait("stopped"); w.p.wait(timeout=10); blocker.close()
w = Viewer("--control"); e = w.wait("listening")
check("port free: requested and actual port match", e["requestedPort"] == e["port"] == MAIN, e)
w.send(cmd="stop"); w.wait("stopped"); w.p.wait(timeout=10)

# script mode (no --control): unchanged behaviour, no events
v = Viewer("--tunnel-port", str(TUNNEL)); time.sleep(2.5)
s, b, _ = http("GET", MAIN, "/api/access"); a = json.loads(b)
check("script mode: owner sees PIN, not managed", a["pin"] == "1801" and not a["managed"], a)
s, b, _ = http("POST", MAIN, "/api/access", {"mode": "pin", "pin": "1801"})
check("script mode: web dialog still saves", s == 200, (s, b))
s, b, _ = http("GET", TUNNEL, "/api/state?c=", headers=remote_h)
check("a removed device stays removed after a restart", s == 401, s)
check("script mode: no event lines, tunnel line printed", v.events.empty() and not getattr(v, "backlog", []) and any("Tunnel:" in l for l in v.log), v.log)
v.p.terminate(); v.p.wait(timeout=10)

print(f"\n{sum(ok for _, ok in results)}/{len(results)} passed")
sys.exit(0 if all(ok for _, ok in results) else 1)
