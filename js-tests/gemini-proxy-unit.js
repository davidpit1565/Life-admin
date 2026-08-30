#!/usr/bin/env node
const assert = require('node:assert/strict');
const { buildPrompt, toExtraction, normalizeDate, checkSharedSecret, checkRateLimit, clientIP } = require('../server/gemini-proxy');

// normalizeDate: the defense-in-depth check that stops a partial date (e.g. Gemini
// omitting the year) from ever reaching the client, where Swift's strict ISO-8601
// decoder would fail on it and silently discard the whole AI extraction.
assert.equal(normalizeDate('2027-03-18'), '2027-03-18');
assert.equal(normalizeDate('2027-03-18T00:00:00Z'), '2027-03-18T00:00:00Z');
assert.equal(normalizeDate('--03-18'), null);
assert.equal(normalizeDate('03-18'), null);
assert.equal(normalizeDate(null), null);
assert.equal(normalizeDate(42), null);

// toExtraction should apply that same defense-in-depth check.
const withPartialDate = toExtraction({ title: 'Car insurance', category: 'insurance', amount: 840, date: '--03-18', confidence: 0.9 });
assert.equal(withPartialDate.date, null);

const withFullDate = toExtraction({ title: 'Car insurance', category: 'insurance', amount: 840, date: '2027-03-18', confidence: 0.9 });
assert.equal(withFullDate.date, '2027-03-18');

// buildPrompt should tell the model today's date and require complete dates.
const prompt = buildPrompt('renews every March 18', new Date('2026-08-20T00:00:00Z'));
assert.ok(prompt.includes('2026-08-20'), 'prompt should embed the provided date');
assert.ok(prompt.includes('YYYY-MM-DD'), 'prompt should require complete dates');
assert.ok(prompt.includes('next future occurrence'), 'prompt should explain year inference');

// checkSharedSecret: with no APP_SHARED_SECRET configured in this process's env (the default,
// pre-opt-in state), every request must be allowed through regardless of header — this proves
// the abuse-protection change can't break existing deployments that haven't set the env var yet.
assert.equal(checkSharedSecret(undefined), true);
assert.equal(checkSharedSecret('anything'), true);

// clientIP: prefers the first x-forwarded-for entry (as Vercel/most proxies set it), falls back
// to the raw socket address when the header is absent.
assert.equal(clientIP({ 'x-forwarded-for': '203.0.113.5, 10.0.0.1' }, '127.0.0.1'), '203.0.113.5');
assert.equal(clientIP({}, '198.51.100.9'), '198.51.100.9');
assert.equal(clientIP({}, undefined), 'unknown');

// checkRateLimit: a single IP can make up to the per-window cap of requests, then the next one
// is rejected — this is the actual defense against a scripted loop hammering the public endpoint.
const testIP = 'rate-limit-test-ip';
let allowed = 0;
for (let i = 0; i < 25; i += 1) {
  if (checkRateLimit(testIP)) allowed += 1;
}
assert.equal(allowed, 20, 'exactly the configured per-window cap should be allowed, the rest rejected');
// A different IP has its own independent budget, unaffected by the first IP's usage.
assert.equal(checkRateLimit('a-different-ip'), true);

console.log('Gemini proxy unit tests passed');
