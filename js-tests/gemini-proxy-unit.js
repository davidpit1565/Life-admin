#!/usr/bin/env node
const assert = require('node:assert/strict');
const { buildPrompt, toExtraction, normalizeDate } = require('../server/gemini-proxy');

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

console.log('Gemini proxy unit tests passed');
