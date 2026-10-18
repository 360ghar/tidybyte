#!/usr/bin/env node
/**
 * App Store Connect API client. No dependencies — node:crypto and fetch only.
 *
 * Auth is a JWT signed with an App Store Connect API key (ES256 / P-256).
 * Apple caps a token's lifetime at 20 minutes, so this mints a fresh one every
 * 15 and caches it.
 *
 * Create a key at App Store Connect -> Users and Access -> Integrations ->
 * App Store Connect API. Three values are needed, and the private key is read
 * from disk rather than passed through the environment:
 *
 *   ASC_KEY_ID     the Key ID shown beside the key
 *   ASC_ISSUER_ID  the Issuer ID shown above the key list
 *   ASC_KEY_PATH   path to the downloaded AuthKey_<KEYID>.p8
 *
 * The .p8 is a credential. It is read, used to sign, and never logged; this
 * module deliberately has no code path that prints it or the token it produces.
 */

import { createPrivateKey, sign as signPayload } from 'node:crypto';
import { closeSync, openSync, readFileSync, readSync, statSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const BASE = 'https://api.appstoreconnect.apple.com';
const AUDIENCE = 'appstoreconnect-v1';
/** Apple rejects anything over 20 minutes. Stay clear of the boundary. */
const TOKEN_LIFETIME_SECONDS = 15 * 60;

function base64url(value) {
  return Buffer.from(value).toString('base64url');
}

/**
 * Signs a JWT the way App Store Connect expects.
 *
 * The one non-obvious part: JOSE requires the ECDSA signature as raw R||S, and
 * Node defaults to DER for ECDSA. Without `dsaEncoding: 'ieee-p1363'` the
 * signature is well-formed DER and Apple rejects it with a 401 that says
 * nothing about encoding.
 *
 * Exported so the encoding can be tested without a live account — see
 * scripts/publish/selftest.mjs.
 */
export function createToken({ keyId, issuerId, privateKey }) {
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const payload = {
    iss: issuerId,
    iat: issuedAt,
    exp: issuedAt + TOKEN_LIFETIME_SECONDS,
    aud: AUDIENCE,
  };

  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = signPayload('sha256', Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363',
  });

  return `${signingInput}.${signature.toString('base64url')}`;
}

/**
 * Loads a gitignored `.env` from the repo root, without a dependency.
 *
 * This exists for a specific reason: each command this repo runs gets a fresh
 * shell, so `export ASC_KEY_ID=...` in one terminal does not reach the next
 * command. A file on disk does. Values already present in the real environment
 * always win, so exporting a variable for one command still overrides the file.
 *
 * Only the three names below are read. Nothing is written back, and no value is
 * ever logged or echoed — `redact` exists so callers can report *that* a
 * credential is set without reporting what it is.
 */
const ENV_FILE = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '.env');

export function loadEnvFile(path = ENV_FILE, env = process.env) {
  let contents;
  try {
    contents = readFileSync(path, 'utf8');
  } catch {
    return env; // No file is a normal state, not an error.
  }

  for (const line of contents.split('\n')) {
    const trimmed = line.trim();
    if (trimmed === '' || trimmed.startsWith('#')) continue;
    const equals = trimmed.indexOf('=');
    if (equals === -1) continue;

    const name = trimmed.slice(0, equals).trim();
    let value = trimmed.slice(equals + 1).trim();
    // Strip one layer of matching quotes, so a path with spaces can be quoted.
    if (value.length >= 2
      && ((value.startsWith('"') && value.endsWith('"'))
        || (value.startsWith("'") && value.endsWith("'")))) {
      value = value.slice(1, -1);
    }
    // A real environment variable wins over the file.
    if (!env[name]) env[name] = value;
  }

  return env;
}

/** Shows enough of a value to confirm it is the right one, never the whole. */
export function redact(value) {
  if (!value) return '(unset)';
  if (value.length <= 8) return '*'.repeat(value.length);
  return `${value.slice(0, 4)}${'*'.repeat(Math.max(4, value.length - 8))}${value.slice(-4)}`;
}

/** Reads credentials from the environment, failing loudly when one is absent. */
export function credentialsFromEnv(env = process.env) {
  loadEnvFile(ENV_FILE, env);

  const keyId = env.ASC_KEY_ID;
  const issuerId = env.ASC_ISSUER_ID;
  const keyPath = env.ASC_KEY_PATH;

  const missing = Object.entries({ ASC_KEY_ID: keyId, ASC_ISSUER_ID: issuerId, ASC_KEY_PATH: keyPath })
    .filter(([, value]) => !value)
    .map(([name]) => name);

  if (missing.length > 0) {
    throw new Error(
      `Missing ${missing.join(', ')}. Create an App Store Connect API key at\n`
      + '  App Store Connect -> Users and Access -> Integrations -> App Store Connect API\n'
      + 'then either export ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file),\n'
      + `or put them in ${ENV_FILE} (gitignored).`,
    );
  }

  return { keyId, issuerId, keyPath };
}

/** An API error carrying the status and Apple's own error payload. */
export class AscError extends Error {
  constructor(status, payload, method, path) {
    const detail = Array.isArray(payload?.errors)
      ? payload.errors.map((e) => `${e.code ?? e.status}: ${e.detail ?? e.title}`).join('; ')
      : JSON.stringify(payload ?? {});
    super(`${method} ${path} -> HTTP ${status}\n  ${detail}`);
    this.name = 'AscError';
    this.status = status;
    this.payload = payload;
    this.details = payload?.errors ?? [];
  }
}

export function createClient({ keyId, issuerId, keyPath, log = () => {} }) {
  const privateKey = createPrivateKey(readFileSync(keyPath, 'utf8'));
  let cached = null;
  let cachedUntil = 0;

  function token() {
    const now = Date.now();
    if (!cached || now >= cachedUntil) {
      cached = createToken({ keyId, issuerId, privateKey });
      // Refresh a minute early so a request never races the expiry.
      cachedUntil = now + (TOKEN_LIFETIME_SECONDS - 60) * 1000;
      log('  minted a new API token');
    }
    return cached;
  }

  /**
   * One API call, with retries for the two failures worth retrying.
   *
   * 429 and 5xx are transient, and Apple returns `Retry-After` on the former.
   * Everything else — a bad placement group, a parent that is not editable, a
   * missing relationship — is a real error and retrying it just burns quota, so
   * those surface immediately with Apple's own detail text attached.
   */
  async function request(method, path, body, { retries = 4 } = {}) {
    let attempt = 0;
    for (;;) {
      const response = await fetch(`${BASE}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${token()}`,
          ...(body ? { 'Content-Type': 'application/json' } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });

      if (response.status === 204) return null;

      const text = await response.text();
      let payload = null;
      if (text) {
        try {
          payload = JSON.parse(text);
        } catch {
          payload = { raw: text };
        }
      }

      if (response.ok) return payload;

      const retryable = response.status === 429 || response.status >= 500;
      if (retryable && attempt < retries) {
        const retryAfter = Number(response.headers.get('retry-after'));
        const waitMs = Number.isFinite(retryAfter) && retryAfter > 0
          ? retryAfter * 1000
          : Math.min(2 ** attempt * 1000, 30_000);
        log(`  HTTP ${response.status} on ${method} ${path}; retrying in ${Math.round(waitMs / 1000)}s`);
        attempt += 1;
        await new Promise((resolve) => setTimeout(resolve, waitMs));
        continue;
      }

      throw new AscError(response.status, payload, method, path);
    }
  }

  const get = (path, options) => request('GET', path, null, options);
  const post = (path, body, options) => request('POST', path, body, options);
  const patch = (path, body, options) => request('PATCH', path, body, options);
  const del = (path, options) => request('DELETE', path, null, options);

  /** Follows `links.next` until the collection is exhausted. */
  async function getAll(path) {
    const items = [];
    let next = path;
    while (next) {
      const page = await get(next);
      items.push(...(page?.data ?? []));
      const link = page?.links?.next;
      // Apple returns an absolute URL in `next`; strip the host so the same
      // token handling and base URL apply.
      next = link ? link.replace(BASE, '') : null;
    }
    return items;
  }

  /**
   * Uploads one file through Apple's reserve -> upload parts -> commit flow.
   *
   * Two things differ from the old set-based flow and are easy to get wrong:
   * the commit takes `uploaded` alone (no checksum), and the asset relates to
   * the app's asset library rather than to a screenshot set.
   */
  async function uploadAsset({ type, libraryId, filePath, category, referenceName }) {
    const fileName = basename(filePath);
    const fileSize = statSync(filePath).size;

    const reservation = await post(`/v1/${type}`, {
      data: {
        type,
        attributes: {
          fileName,
          fileSize,
          ...(category ? { category } : {}),
          ...(referenceName ? { referenceName } : {}),
        },
        relationships: {
          assetLibrary: { data: { type: 'appAssetLibraries', id: libraryId } },
        },
      },
    });

    const assetId = reservation.data.id;
    const operations = reservation.data.attributes?.uploadOperations ?? [];
    if (operations.length === 0) {
      throw new Error(`Reservation for ${fileName} returned no upload operations.`);
    }

    const descriptor = openSync(filePath, 'r');
    try {
      for (const operation of operations) {
        const { method, url, length, offset, requestHeaders } = operation;
        const chunk = Buffer.alloc(length);
        readSync(descriptor, chunk, 0, length, offset);

        const headers = Object.fromEntries(
          (requestHeaders ?? []).map((header) => [header.name, header.value]),
        );
        const response = await fetch(url, { method, headers, body: chunk });
        if (!response.ok) {
          throw new Error(
            `Uploading ${fileName} part at offset ${offset} failed: HTTP ${response.status}`,
          );
        }
      }
    } finally {
      closeSync(descriptor);
    }

    await patch(`/v1/${type}/${assetId}`, {
      data: { type, id: assetId, attributes: { uploaded: true } },
    });

    return { assetId, fileName, fileSize };
  }

  /**
   * Polls an asset until App Store Connect finishes processing it.
   *
   * Processing is asynchronous and reports `COMPLETE` or `FAILED`. `FAILED` is
   * terminal — the asset record has to be deleted and re-uploaded — so it is
   * raised rather than retried.
   */
  async function waitForAsset({ type, assetId, timeoutMs = 180_000 }) {
    const deadline = Date.now() + timeoutMs;
    let delay = 1000;

    for (;;) {
      const response = await get(`/v1/${type}/${assetId}`);
      const state = response?.data?.attributes?.assetDeliveryState?.state;
      if (state === 'COMPLETE') return response.data;

      if (state === 'FAILED') {
        const errors = response.data.attributes.assetDeliveryState.errors ?? [];
        const detail = errors.map((e) => e.description ?? e.code).join('; ') || 'no detail given';
        throw new Error(`Asset ${assetId} failed processing: ${detail}`);
      }

      if (Date.now() >= deadline) {
        throw new Error(`Asset ${assetId} still ${state ?? 'unknown'} after ${timeoutMs / 1000}s.`);
      }

      await new Promise((resolve) => setTimeout(resolve, delay));
      delay = Math.min(delay * 1.5, 5000);
    }
  }

  return { get, post, patch, del, getAll, uploadAsset, waitForAsset, request };
}

/**
 * Resolves the app record by bundle ID.
 *
 * `filter[bundleId]` is an exact match, but Apple has been known to return
 * near-matches, so this verifies rather than trusting the first row.
 */
export async function findApp(client, bundleId) {
  const apps = await client.getAll(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&limit=200`);
  const exact = apps.filter((app) => app.attributes?.bundleId === bundleId);
  if (exact.length === 0) {
    throw new Error(`No app record for bundle ID ${bundleId}. Create it in App Store Connect first.`);
  }
  if (exact.length > 1) {
    throw new Error(
      `Found ${exact.length} app records for ${bundleId}: ${exact.map((a) => a.id).join(', ')}`,
    );
  }
  return exact[0];
}
