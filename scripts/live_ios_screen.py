#!/usr/bin/env python3
"""Read-only, low-latency simulator preview for a manual GitHub Actions run."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import urlsplit


PAGE = """<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pipo simulator preview</title>
<style>
  body { margin: 0; background: #0f172a; color: white; font: 16px system-ui;
         text-align: center; }
  header { padding: 12px; }
  img { display: block; max-width: 100vw; max-height: calc(100vh - 65px);
        margin: auto; object-fit: contain; }
</style>
<header>Pipo simulator — read-only live preview</header>
<img id="screen" alt="Current Pipo simulator screen">
<script>
  const screen = document.getElementById("screen");
  async function refresh() {
    try {
      const response = await fetch("/frame.png?t=" + Date.now(), {cache: "no-store"});
      if (response.ok) {
        const next = URL.createObjectURL(await response.blob());
        const previous = screen.src;
        screen.onload = () => { if (previous.startsWith("blob:")) URL.revokeObjectURL(previous); };
        screen.src = next;
      }
    } catch (_) {}
    setTimeout(refresh, 900);
  }
  refresh();
</script>
</html>
""".encode("utf-8")


def simulator_frame(udid: str) -> bytes:
    with tempfile.TemporaryDirectory(prefix="pipo-preview-") as directory:
        path = Path(directory) / "screen.png"
        subprocess.run(
            ["xcrun", "simctl", "io", udid, "screenshot", str(path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
            timeout=10,
        )
        return path.read_bytes()


def handler_for(capture):
    class ScreenHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlsplit(self.path).path
            if path == "/":
                self.respond(200, "text/html; charset=utf-8", PAGE)
            elif path == "/health":
                self.respond(200, "text/plain; charset=utf-8", b"ok\n")
            elif path == "/frame.png":
                try:
                    frame = capture()
                except (OSError, subprocess.SubprocessError):
                    self.respond(503, "text/plain; charset=utf-8", b"Simulator unavailable\n")
                    return
                self.respond(200, "image/png", frame)
            else:
                self.respond(404, "text/plain; charset=utf-8", b"Not found\n")

        def do_POST(self):
            self.respond(405, "text/plain; charset=utf-8", b"Read only\n")

        do_PUT = do_POST
        do_PATCH = do_POST
        do_DELETE = do_POST

        def respond(self, status, content_type, body):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            # Cloudflare handles viewer authentication. Avoid logging URLs or tokens.
            pass

    return ScreenHandler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port),
        handler_for(lambda: simulator_frame(args.udid)),
    )
    server.serve_forever(poll_interval=0.2)


if __name__ == "__main__":
    main()
