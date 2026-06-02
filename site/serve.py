#!/usr/bin/env python3
"""
Local development server for the TidyByte marketing site.
Mirrors the pretty-URL redirects from netlify.toml so the site behaves
the same locally as it will on Netlify.

Usage:
    python3 serve.py [port]    # default port 3000
"""

import http.server
import socketserver
import sys
import os
from urllib.parse import urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 3000

# Mirror of the [[redirects]] blocks in netlify.toml (200 = internal rewrite).
REDIRECTS = {
    "/support": "/support.html",
    "/privacy": "/privacy.html",
    "/changelog": "/changelog.html",
}


class RedirectHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path in REDIRECTS:
            target = REDIRECTS[parsed.path]
            suffix = ("?" + parsed.query) if parsed.query else ""
            self.path = target + suffix
        return super().do_GET()


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    with socketserver.TCPServer(("", PORT), RedirectHandler) as httpd:
        print(f"Serving site/ at http://localhost:{PORT}/")
        print(f"  /          → index.html")
        print(f"  /support   → support.html")
        print(f"  /privacy   → privacy.html")
        print(f"  /changelog → changelog.html")
        print("Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
