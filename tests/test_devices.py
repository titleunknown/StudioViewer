"""The Viewers panel's device list (Devices in studio_viewer.py) on its own, with short time limits:
a browser that stops asking is listed as left, comes back as a new visit with its ratings kept,
and is forgotten in the end. A removed device is never listed as left.

    python3 -I tests/test_devices.py      # a few seconds; exits non-zero if anything fails
"""
import importlib.util, os, sys, threading, time

ENGINE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "studio_viewer.py")
spec = importlib.util.spec_from_file_location("studio_viewer", ENGINE)
sv = importlib.util.module_from_spec(spec); spec.loader.exec_module(sv)


class Access:
    lock = threading.Lock(); data = {"blocked": {}}
    can_rate = lambda *a: False; unlocked = lambda *a: False; rating_allowed = lambda *a: True


class Handler:
    def __init__(self, ip): self.remote = False; self.headers = {"User-Agent": "x"}; self._ip = ip
    ip = lambda self: self._ip; is_owner = lambda self: False; cookie = lambda self: ""


results = []
def check(name, cond):
    results.append(bool(cond))
    print(("PASS " if cond else "FAIL ") + name)


sv.Devices.ACTIVE, sv.Devices.FORGET = 0.3, 1.0
d = sv.Devices(Access())
d.touch("a" * 32, Handler("10.0.0.2")); d.rated("a" * 32, "rating"); d.touch("b" * 32, Handler("10.0.0.3"))
s = d.snapshot({}); check("both connected", [x["left"] for x in s] == [False, False])
time.sleep(0.4); d.touch("b" * 32, Handler("10.0.0.3"))
s = d.snapshot({}); check("a left, b still here", [(x["id"][0], x["left"]) for x in s] == [("b", False), ("a", True)])
first_b = s[0]["since"]
time.sleep(0.4); d.touch("a" * 32, Handler("10.0.0.2"))
s = {x["id"][0]: x for x in d.snapshot({})}
check("a back: connected again, new visit, rating kept",
      s["a"]["left"] is False and s["a"]["ratings"] == 1 and s["a"]["since"] > first_b)
Access.data["blocked"]["b" * 32] = {"name": "x"}
time.sleep(0.4)
s = d.snapshot({}); check("a removed device isn't listed as left", [x for x in s if x["id"][0] == "b" and not x["blocked"]] == [])
Access.data["blocked"].clear(); time.sleep(1.1)
check("forgotten after FORGET", d.snapshot({}) == [])

print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
