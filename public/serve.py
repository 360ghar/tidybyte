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
    "/blog": "/blog/index.html",
}

# Consolidated posts (F8): 301 to their keeper, mirroring netlify.toml.
MOVED_PERMANENTLY = {
    "/blog/how-to-clean-up-blurry-shaky-photos": "/blog/find-blurry-photos-iphone",
    "/blog/how-to-find-blurry-photos-in-camera-roll": "/blog/find-blurry-photos-iphone",
    "/blog/how-to-remove-blurry-photos-iphone": "/blog/find-blurry-photos-iphone",
    "/blog/how-to-free-up-iphone-storage-without-deleting": "/blog/how-to-clean-iphone-storage-without-deleting-photos",
    "/blog/how-to-reduce-photo-library-size-iphone": "/blog/how-to-clean-iphone-storage-without-deleting-photos",
    "/blog/photo-cleaner-app-no-subscription": "/blog/best-iphone-cleaner-app-no-subscription",
    "/blog/photo-cleaner-app-no-ads-no-in-app-purchase": "/blog/best-iphone-cleaner-app-no-subscription",
    "/blog/how-to-free-up-icloud-storage-photos": "/blog/free-up-icloud-storage-without-deleting-photos",
    "/blog/swipe-to-clean-photos-iphone": "/blog/how-to-organize-thousands-of-photos-iphone",
}


class RedirectHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        new_path = self._rewrite(self.path)
        if new_path is None:
            return
        self.path = new_path
        return super().do_GET()

    # Parity with Netlify: HEAD requests must resolve through the same
    # rewrites (link checkers and CDNs use HEAD).
    def do_HEAD(self):
        new_path = self._rewrite(self.path)
        if new_path is None:
            return
        self.path = new_path
        return super().do_HEAD()

    def handle(self):
        # A client that hangs up mid-response is not a server error; swallow
        # the transport noise instead of printing tracebacks.
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def _rewrite(self, path):
        """Return the path to serve, or None if a response was already sent."""
        parsed = urlparse(path)
        suffix = ("?" + parsed.query) if parsed.query else ""
        route = parsed.path.rstrip("/") if parsed.path != "/" else parsed.path
        if route in REDIRECTS:
            return REDIRECTS[route] + suffix
        # Consolidated posts: permanent redirect to the keeper.
        if route in MOVED_PERMANENTLY:
            self.send_response(301)
            self.send_header("Location", MOVED_PERMANENTLY[route] + suffix)
            self.end_headers()
            return None
        if route.startswith("/blog/") and route != "/blog":
            # Mirror netlify.toml: a trailing slash is 301'd away BEFORE the
            # extensionless rewrite (otherwise /blog/<slug>/ would resolve to
            # /blog/<slug>/.html and 404).
            if parsed.path.endswith("/") and route != parsed.path:
                self.send_response(301)
                self.send_header("Location", route + suffix)
                self.end_headers()
                return None
            if not route.endswith(".html") and not route.endswith(".md"):
                return route + ".html" + suffix
        return path


if __name__ == "__main__":
    dist = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dist"))
    if not os.path.isdir(dist):
        sys.exit("dist/ not found — run `npm run build` first.")
    os.chdir(dist)
    with socketserver.TCPServer(("", PORT), RedirectHandler) as httpd:
        print(f"Serving dist/ at http://localhost:{PORT}/")
        print(f"  /          → index.html")
        print(f"  /support   → support.html")
        print(f"  /privacy   → privacy.html")
        print(f"  /changelog → changelog.html")
        print(f"  /blog      → blog/index.html")
        print(f"  /blog/<slug> → blog/<slug>.html")
        print("Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
