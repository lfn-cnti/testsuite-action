"""A stand-in for a model API in the self-test: records every request and
answers with the reply in reply.json (status, body), for the analysis step.
A reply with "then" answers once, and the next request gets "then"."""
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

state = sys.argv[1]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        n = len([f for f in os.listdir(state) if f.startswith("request-")])
        with open(os.path.join(state, f"request-{n}.json"), "w") as f:
            json.dump({"path": self.path, "headers": dict(self.headers), "body": body}, f)
        with open(os.path.join(state, "reply.json")) as f:
            reply = json.load(f)
        if "then" in reply:
            with open(os.path.join(state, "reply.json"), "w") as f:
                json.dump(reply["then"], f)
        payload = json.dumps(reply["body"]).encode()
        self.send_response(reply["status"])
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
