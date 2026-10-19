#!/usr/bin/env node
/**
 * Self-test for the parts of the publish pipeline that do not need an account.
 *
 * Two things here are easy to get wrong and expensive to debug against a live
 * API, so they are pinned by a test that runs offline:
 *
 *   1. The JWT signature encoding. JOSE wants raw R||S; Node emits DER by
 *      default. A DER signature is a valid ECDSA signature, so the only symptom
 *      is a 401 from Apple that never mentions encoding.
 *   2. The plan. Every file it names has to exist, every language has to map to
 *      a real storefront locale, and the placement types have to come from the
 *      catalog rather than a guess.
 *
 * Usage: node scripts/publish/selftest.mjs
 */

import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, verify as verifySignature } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createToken } from './asc.mjs';
import { loadPlan, LOCALE_BY_LANGUAGE } from './plan.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

let failures = 0;
function check(label, condition, detail = '') {
  if (condition) {
    console.log(`  PASS  ${label}`);
  } else {
    failures += 1;
    console.log(`  FAIL  ${label}${detail ? `  ${detail}` : ''}`);
  }
}

console.log('\nJWT signing');
{
  // A throwaway key, so the test never touches a real credential.
  const { privateKey, publicKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    publicKeyEncoding: { type: 'spki', format: 'pem' },
  });

  const token = createToken({
    keyId: 'TESTKEYID',
    issuerId: '00000000-0000-0000-0000-000000000000',
    privateKey: createPrivateKey(privateKey),
  });

  const parts = token.split('.');
  check('token has three segments', parts.length === 3, `got ${parts.length}`);

  const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
  const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());

  check('header alg is ES256', header.alg === 'ES256', `got ${header.alg}`);
  check('header typ is JWT', header.typ === 'JWT', `got ${header.typ}`);
  check('header carries the key id', header.kid === 'TESTKEYID', `got ${header.kid}`);
  check('audience is appstoreconnect-v1', payload.aud === 'appstoreconnect-v1', `got ${payload.aud}`);
  check('issuer is set', typeof payload.iss === 'string' && payload.iss.length > 0);
  check('expiry is in the future', payload.exp > Math.floor(Date.now() / 1000));
  check(
    'lifetime is within Apple\'s 20-minute cap',
    payload.exp - payload.iat <= 1200,
    `got ${payload.exp - payload.iat}s`,
  );

  // The real assertion: the signature must be raw R||S, and must verify.
  const signature = Buffer.from(parts[2], 'base64url');
  check('signature is 64 bytes (raw R||S), not DER', signature.length === 64, `got ${signature.length} bytes`);

  const valid = verifySignature(
    'sha256',
    Buffer.from(`${parts[0]}.${parts[1]}`),
    { key: createPublicKey(publicKey), dsaEncoding: 'ieee-p1363' },
    signature,
  );
  check('signature verifies against the public key', valid);
}

console.log('\nPlan');
{
  const plan = await loadPlan();
  check('plan is not empty', plan.length > 0, `got ${plan.length}`);

  const missing = plan.filter((item) => !existsSync(item.file));
  check('every planned file exists', missing.length === 0, `${missing.length} missing`);

  const empty = plan.filter((item) => existsSync(item.file) && statSync(item.file).size === 0);
  check('no planned file is empty', empty.length === 0, `${empty.length} empty`);

  const noLocale = plan.filter((item) => !item.locale);
  check('every item maps to a storefront locale', noLocale.length === 0, `${noLocale.length} unmapped`);

  const noCandidates = plan.filter(
    (item) => !Array.isArray(item.placementTypeCandidates) || item.placementTypeCandidates.length === 0,
  );
  check('every item names at least one placement type', noCandidates.length === 0, `${noCandidates.length} bare`);

  const byHash = new Map();
  for (const item of plan) {
    const hash = createHash('sha256').update(readFileSync(item.file)).digest('hex');
    if (!byHash.has(hash)) byHash.set(hash, []);
    byHash.get(hash).push(item);
  }
  const shared = [...byHash.values()].filter((group) => group.length > 1);
  check(
    'identical files on two surfaces are detected as one upload',
    shared.length > 0,
    `expected the header/search creatives to be shared; got ${shared.length} shared group(s)`,
  );
  check(
    'content dedup saves uploads',
    byHash.size < plan.length,
    `${byHash.size} distinct files back ${plan.length} placements`,
  );
  // Every shared group must be the same bytes on different surfaces, not the
  // same surface twice, which would mean the manifest is wrong.
  const sameSurface = shared.filter((group) => new Set(group.map((i) => i.surface)).size < group.length);
  check(
    'no surface lists the same file twice',
    sameSurface.length === 0,
    `${sameSurface.length} group(s) repeat within one surface`,
  );
}

console.log('\nLocale mapping');
{
  const listings = JSON.parse(readFileSync(join(ROOT, 'docs', 'appstore', 'listings.json'), 'utf8'));
  const languages = Object.keys(listings).filter((key) => !key.startsWith('_'));

  const unmapped = languages.filter((language) => !LOCALE_BY_LANGUAGE[language]);
  check('every listing language has a storefront locale', unmapped.length === 0, unmapped.join(', '));

  // App Store Connect accepts a fixed set. These are the ones the app ships.
  const expected = [
    'ar-SA', 'bn-BD', 'de-DE', 'en-US', 'es-ES', 'fr-FR', 'gu-IN', 'he', 'hi', 'it', 'ja',
    'kn-IN', 'ko', 'ml-IN', 'mr-IN', 'pa-IN', 'pt-BR', 'ru', 'ta-IN', 'te-IN', 'zh-Hans',
  ];
  const actual = [...new Set(Object.values(LOCALE_BY_LANGUAGE))].sort();
  check(
    'the storefront list matches the 21 locales the app ships',
    actual.length === expected.length && expected.every((locale) => actual.includes(locale)),
    `got ${actual.length}: ${actual.join(', ')}`,
  );
}

console.log('\nPlacement types are read from the catalog, not guessed');
{
  const source = readFileSync(join(ROOT, 'scripts', 'publish', 'publish.mjs'), 'utf8');
  check(
    'no placement type is hard-coded in the upload path',
    !/attributes:\s*\{\s*placementType:\s*['"]/.test(source),
    'found a literal placementType in a request body',
  );
  check(
    'the resolver checks candidates against the live catalog',
    source.includes('available.has(name)'),
  );
}

console.log('\nCredential hygiene');
{
  // A .p8 is the entire credential: it uploads builds, rewrites store copy, and
  // submits for review. If it can be committed, it eventually will be, and it
  // cannot be un-leaked by deleting a file from git history.
  const gitignore = readFileSync(join(ROOT, '.gitignore'), 'utf8');
  check(
    '.p8 files are gitignored',
    /^\*\.p8\s*$/m.test(gitignore),
    'add `*.p8` to .gitignore',
  );

  // Belt and braces: the ignore rule is the guard, this is the assertion.
  try {
    execFileSync('git', ['check-ignore', '-q', 'AuthKey_PROBE.p8'], { cwd: ROOT });
    check('a probe key is actually ignored by git', true);
  } catch {
    check('a probe key is actually ignored by git', false, 'git does not ignore AuthKey_PROBE.p8');
  }

  const asc = readFileSync(join(ROOT, 'scripts', 'publish', 'asc.mjs'), 'utf8');
  check(
    'the client never logs the key or the token',
    !/console\.log\([^)]*(privateKey|token\(\)|cached)/.test(asc),
    'found a log statement that could print a credential',
  );
  check(
    'the private key is read from a path, not an inline value',
    asc.includes('readFileSync(keyPath'),
  );
}

console.log(`\n${failures === 0 ? 'All checks passed.' : `${failures} check(s) FAILED.`}`);
process.exit(failures === 0 ? 0 : 1);
