#!/usr/bin/env node
// Renders index.html to social-preview.png at 1280x640 (GitHub's size).
import { chromium } from 'playwright';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 640 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(join(here, 'index.html')).href, { waitUntil: 'networkidle' });
await page.screenshot({ path: join(here, 'social-preview.png'), omitBackground: false });
await browser.close();
console.log('wrote docs/social-preview/social-preview.png');
