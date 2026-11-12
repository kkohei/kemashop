import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { verifyWebhook, parseDateToMs } from '../src/webhook.js';
import { safeEqual, redactKey } from '../src/util.js';

const SECRET = 'sig-secret';
const NOW = Date.UTC(2026, 0, 1, 12, 0, 0);
const sign = (date, body, secret = SECRET) =>
  `date=${date},v1=${crypto.createHmac('sha256', secret).update(`${date}.${body}`).digest('hex')}`;
const cfg = { signingSecret: SECRET, sharedSecret: '', maxAgeSec: 300 };
const body = '{"event_id":"e1"}';
const unix = Math.floor(NOW / 1000);

test('HMAC success', () => {
  const r = verifyWebhook({ signatureHeader: sign(unix, body), rawBody: body }, cfg, NOW);
  assert.equal(r.ok, true);
});

test('HMAC mismatch (tampered body / wrong secret)', () => {
  assert.equal(verifyWebhook({ signatureHeader: sign(unix, body), rawBody: body + 'x' }, cfg, NOW).reason, 'signature-mismatch');
  assert.equal(verifyWebhook({ signatureHeader: sign(unix, body, 'other'), rawBody: body }, cfg, NOW).ok, false);
});

test('missing signature header', () => {
  const r = verifyWebhook({ rawBody: body }, cfg, NOW);
  assert.deepEqual([r.ok, r.reason], [false, 'no-signature']);
});

test('no secrets configured => fail closed', () => {
  const r = verifyWebhook({ signatureHeader: sign(unix, body), rawBody: body }, { signingSecret: '', sharedSecret: '' }, NOW);
  assert.deepEqual([r.ok, r.reason], [false, 'no-secret-configured']);
});

test('shared secret success / fail / missing', () => {
  const c = { signingSecret: '', sharedSecret: 'tok-123' };
  assert.equal(verifyWebhook({ token: 'tok-123' }, c, NOW).ok, true);
  assert.equal(verifyWebhook({ token: 'tok-124' }, c, NOW).ok, false);
  assert.equal(verifyWebhook({ token: 'short' }, c, NOW).ok, false);
  assert.equal(verifyWebhook({}, c, NOW).ok, false);
});

test('shared secret still works when signing secret is also configured', () => {
  const c = { ...cfg, sharedSecret: 'tok-123' };
  assert.equal(verifyWebhook({ token: 'tok-123', rawBody: body }, c, NOW).ok, true);
});

test('date too old / too new rejected, fresh accepted', () => {
  const old = unix - 3600;
  assert.equal(verifyWebhook({ signatureHeader: sign(old, body), rawBody: body }, cfg, NOW).reason, 'date-out-of-range');
  const future = unix + 3600;
  assert.equal(verifyWebhook({ signatureHeader: sign(future, body), rawBody: body }, cfg, NOW).ok, false);
  assert.equal(verifyWebhook({ signatureHeader: sign(unix - 60, body), rawBody: body }, cfg, NOW).ok, true);
});

test('date formats: ISO, HTTP-date, ms; unparsable rejected; maxAge=0 disables', () => {
  const iso = new Date(NOW).toISOString();
  assert.equal(verifyWebhook({ signatureHeader: sign(iso, body), rawBody: body }, cfg, NOW).ok, true);
  assert.equal(verifyWebhook({ signatureHeader: sign(new Date(NOW).toUTCString(), body), rawBody: body }, cfg, NOW).ok, true);
  assert.equal(verifyWebhook({ signatureHeader: sign(NOW, body), rawBody: body }, cfg, NOW).ok, true);
  assert.equal(verifyWebhook({ signatureHeader: sign('garbage', body), rawBody: body }, cfg, NOW).reason, 'date-unparsable');
  assert.equal(verifyWebhook({ signatureHeader: sign('garbage', body), rawBody: body }, { ...cfg, maxAgeSec: 0 }, NOW).ok, true);
  assert.equal(parseDateToMs(''), null);
});

test('safeEqual length mismatch does not throw', () => {
  assert.equal(safeEqual('a', 'abcdef'), false);
  assert.equal(safeEqual('', 'x'), false);
  assert.equal(safeEqual(undefined, 'x'), false);
  assert.equal(safeEqual('same', 'same'), true);
});

test('redactKey hides local part of emails', () => {
  assert.equal(redactKey('taro@example.com'), 't***@example.com');
  assert.equal(redactKey('1001'), '1001');
});

// strict 既定 / 明示 false は config を再評価して確認(別プロセスで import)
async function strictFor(value) {
  const { execFileSync } = await import('node:child_process');
  const env = { PATH: process.env.PATH, RELAY_DB_PATH: ':memory:' };
  if (value !== undefined) env.WEBHOOK_VERIFY_STRICT = value;
  const out = execFileSync(
    process.execPath,
    ['--input-type=module', '-e', "import {config} from './src/config.js'; console.log(config.webhook.strict, config.webhook.capture, config.devices.allowLegacy)"],
    { env, cwd: new URL('..', import.meta.url).pathname, stdio: ['ignore', 'pipe', 'ignore'] }
  );
  return out.toString().trim();
}

test('strict defaults true; only explicit "false" relaxes; capture default false; legacy default true', async () => {
  assert.equal(await strictFor(undefined), 'true false true');
  assert.equal(await strictFor(''), 'true false true');
  assert.equal(await strictFor('true'), 'true false true');
  assert.equal(await strictFor('false'), 'false false true');
});
