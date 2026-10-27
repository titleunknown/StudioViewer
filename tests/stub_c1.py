"""A fake Capture One Live for Studio server, for trying the app without Capture One (no photos):

    python3 -I tests/stub_c1.py [port]          # default 8799
    defaults write Faini-Made.StudioViewer captureOneAddress 127.0.0.1:8799   # then start the viewer
    defaults delete Faini-Made.StudioViewer captureOneAddress                 # back to the real one

test_engine.py has its own copy built in."""
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8799
STATE = {"objects": [{"kObjectKey_ObjectName": "STUB SESSION", "kObjectKey_Collections": []}], "variants": []}


class Stub(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/connectToServiceForLive":
            body = b"123"
        elif p == "/getServerStateForLive":
            body = json.dumps(STATE).encode()
        elif p == "/getServerChangesForLive":
            time.sleep(20)
            body = b""
        else:
            body = b""
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


s = ThreadingHTTPServer(("127.0.0.1", PORT), Stub)
s.daemon_threads = True
print(f"stub Capture One on 127.0.0.1:{PORT}", flush=True)
s.serve_forever()
