"""Serve Godot Web export locally with required COOP/COEP headers."""
from __future__ import annotations

import argparse
import os
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path


class GodotWebHandler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        if self.path.endswith(".wasm"):
            self.send_header("Content-Type", "application/wasm")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description="Preview Godot Web export")
    parser.add_argument("--port", type=int, default=8060)
    args = parser.parse_args()

    web_dir = Path(__file__).resolve().parent.parent / "build" / "web"
    if not (web_dir / "index.html").is_file():
        raise SystemExit(f"Missing export: {web_dir / 'index.html'}\nRun tools\\export_web.bat first.")

    os.chdir(web_dir)
    host = "127.0.0.1"
    server = HTTPServer((host, args.port), GodotWebHandler)
    url = f"http://{host}:{args.port}/"
    print(f"Serving {web_dir}")
    print(f"Open in browser: {url}")
    print("Press Ctrl+C to stop.")
    server.serve_forever()


if __name__ == "__main__":
    main()
