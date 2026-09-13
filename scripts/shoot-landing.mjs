#!/usr/bin/env node
// Capture landing-page screenshots (light+dark, 3 viewports) into
// .preview-shots/ for human review. One-off visual-QA helper.
import { createServer } from "node:http";
import { existsSync, mkdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { join, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DIST = join(ROOT, "dist");
const OUT = join(ROOT, ".preview-shots");
const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".png": "image/png", ".webp": "image/webp", ".avif": "image/avif", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".woff2": "font/woff2" };

const srv = createServer((req, resp) => {
  let p = decodeURIComponent(req.url.split("?")[0]);
  let file = join(DIST, p === "/" ? "index.html" : p.replace(/^\//, ""));
  if (!existsSync(file) && existsSync(`${file}.html`)) file += ".html";
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, "index.html");
  if (!existsSync(file)) { resp.writeHead(404); resp.end(); return; }
  resp.writeHead(200, { "content-type": MIME[extname(file)] ?? "application/octet-stream" });
  resp.end(readFileSync(file));
});
await new Promise((r) => srv.listen(4179, "127.0.0.1", r));

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
const { chromium } = await import("playwright");
console.error("launching browser");
const browser = await chromium.launch();
const page = await browser.newPage();
const withTimeout = (p, ms, label) =>
  Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(`timeout after ${ms}ms: ${label}`)), ms))]);
for (const [w, h] of [[375, 812], [768, 1024], [1280, 800]]) {
  await page.setViewportSize({ width: w, height: h });
  for (const scheme of ["light", "dark"]) {
    console.error(`capturing ${w} ${scheme}`);
    await page.goto("http://127.0.0.1:4179/", { waitUntil: "networkidle" });
    await withTimeout(page.evaluate(async (s) => {
      document.documentElement.classList.toggle("dark", s === "dark");
      document.documentElement.style.colorScheme = s;
      // Reveal everything (donut draw-in included) for the still capture.
      for (const el of document.querySelectorAll("[data-reveal]")) el.classList.add("is-revealed");
      const step = window.innerHeight;
      for (let y = 0; y < document.body.scrollHeight; y += step) {
        window.scrollTo(0, y);
        await new Promise((r) => setTimeout(r, 30));
      }
      window.scrollTo(0, 0);
      // Bound each decode: a lazy image whose load was cancelled leaves
      // decode() pending forever, which previously hung this script.
      await Promise.allSettled(
        [...document.querySelectorAll("img")].filter((i) => i.offsetParent !== null).map((i) =>
          Promise.race([i.decode(), new Promise((r) => setTimeout(r, 3000))]),
        ),
      );
    }, scheme), 20000, "evaluate");
    await page.waitForTimeout(1200);
    await withTimeout(page.screenshot({ path: join(OUT, `landing-${w}-${scheme}.png`), fullPage: true }), 30000, "screenshot");
    console.log(`saved landing-${w}-${scheme}.png`);
  }
}
await browser.close();
srv.close();
