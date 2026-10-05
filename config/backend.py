#!/usr/bin/env python3
"""Tiny REST backend for the CN project. Python standard library only.

Environment:
  BACKEND_ID   "A" or "B" – returned in JSON and in the X-Backend header
  PORT         TCP port to listen on (3001 for A, 3002 for B)

Endpoints:
  GET /             service info                     (Cache-Control: no-store)
  GET /api/status   {"backend": "A", "status": "ok"} (Cache-Control: public, max-age=60 + ETag)
  GET /api/cached   identical on both backends, with Cache-Control + ETag,
                    and answers If-None-Match with 304 Not Modified (Task F)
"""
import hashlib
import json
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BACKEND = os.environ.get("BACKEND_ID", "?")
PORT = int(os.environ.get("PORT", "3001"))
HOST = socket.gethostname()

# The cacheable body must be byte-identical on A and B. If it contained the
# backend name, A and B would produce different ETags and a conditional
# request load-balanced to the "other" backend could never return 304.
CACHED_BODY = (json.dumps({
    "message": "This response is cacheable for 60 seconds",
    "version": 1,
}, indent=2) + "\n").encode()


class Handler(BaseHTTPRequestHandler):
    server_version = "cn-backend/1.0"
    protocol_version = "HTTP/1.1"  # keep-alive; every response carries Content-Length

    def _send(self, code, body=b"", headers=None):
        self.send_response(code)
        self.send_header("X-Backend", BACKEND)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        if code != 304:  # a 304 never has a body
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body and code != 304 and self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, code, obj, headers=None):
        self._send(code, (json.dumps(obj, indent=2) + "\n").encode(), headers)

    def _conditional(self, body, cache_control):
        """200 + body + ETag, or 304 Not Modified if the client already has this version."""
        etag = '"' + hashlib.sha256(body).hexdigest()[:16] + '"'
        cache = {"Cache-Control": cache_control, "ETag": etag}
        if etag in (self.headers.get("If-None-Match") or ""):
            self._send(304, headers=cache)    # conditional request: still valid, no body
        else:
            self._send(200, body, cache)      # full response

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        no_store = {"Cache-Control": "no-store"}

        if path == "/":
            self._json(200, {
                "service": "cn-project",
                "backend": BACKEND,
                "status": "running",
                "endpoints": ["/", "/api/status", "/api/cached"],
            }, no_store)

        elif path == "/api/status":
            # Cacheable for 60 s, with an ETag (Task F). The body is stable for a given
            # backend + client, so the ETag only changes when the content changes.
            # A and B return different bodies, so their ETags differ too.
            body = (json.dumps({
                "backend": BACKEND,
                "status": "ok",
                "host": HOST,
                "port": PORT,
                # The TCP peer is the edge (nginx), not the real client:
                "tcp_peer": self.client_address[0],
                "x_forwarded_for": self.headers.get("X-Forwarded-For"),
            }, indent=2) + "\n").encode()
            self._conditional(body, "public, max-age=60")

        elif path == "/api/cached":
            self._conditional(CACHED_BODY, "public, max-age=60")

        else:
            self._json(404, {"error": "not found", "path": path, "backend": BACKEND})

    do_HEAD = do_GET

    def log_message(self, fmt, *args):
        headers = getattr(self, "headers", None)
        xff = headers.get("X-Forwarded-For", "-") if headers else "-"
        print(f"{time.strftime('%H:%M:%S')} [backend {BACKEND}] "
              f"from {self.client_address[0]}:{self.client_address[1]} "
              f"(client {xff}) {fmt % args}", flush=True)


if __name__ == "__main__":
    # 0.0.0.0 = every interface, so the edge on another machine can reach us.
    # Binding to 127.0.0.1 would make the backend unreachable from node-2.
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"backend {BACKEND} listening on 0.0.0.0:{PORT} (host {HOST})", flush=True)
    server.serve_forever()
