#!/usr/bin/env node
const http = require('http');

const model = 'gemini-3.5-flash-lite';
const apiVersion = 'v1beta';
const port = Number(process.env.PORT || 8787);
const key = process.env.GEMINI_API_KEY;

function safeLog(message, meta = {}) {
  const clean = { ...meta };
  delete clean.authorization;
  delete clean.apiKey;
  delete clean.key;
  delete clean['x-goog-api-key'];
  console.error(JSON.stringify({ message, ...clean }));
}

function send(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}

function normalizeCategory(value) {
  const allowed = new Set(['documents','insurance','money','bills','subscriptions','car','home','health','travel','work','education','shopping','warranties','memberships','appointments','personal','family','other']);
  return allowed.has(value) ? value : 'other';
}

function buildPrompt(text, now = new Date()) {
  const today = now.toISOString().slice(0, 10);
  return `You extract structured Life Admin items. Return only JSON. Extract only facts present in the user text. Never invent prices, companies, or people. Today's date is ${today}. Always output complete dates as YYYY-MM-DD — never a partial date missing the year. When the user gives a recurring date without a year (for example "every March 18"), resolve it to the next future occurrence: use this year if that month/day has not yet passed relative to today, otherwise use next year. Use null when a date is missing entirely. Use null for other fields when missing. Preserve currency as ISO 4217. Mark ambiguous fields with lower confidence. Schema: {"title": string|null, "category": one of documents,insurance,money,bills,subscriptions,car,home,health,travel,work,education,shopping,warranties,memberships,appointments,personal,family,other|null, "amount": number|null, "currency": string|null, "date": string|null, "recurring": one of none,daily,weekly,biweekly,monthly,everyTwoMonths,quarterly,everySixMonths,yearly,custom|null, "reminderOffsets": number[]|null, "notes": string|null, "confidence": number}. User text: ${JSON.stringify(text)}`;
}

function normalizeDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}/.test(value) ? value : null;
}

function toExtraction(raw) {
  if (!raw || typeof raw !== 'object') throw new Error('invalid structured output');
  const confidence = Number(raw.confidence);
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) throw new Error('invalid confidence');
  return {
    title: typeof raw.title === 'string' ? raw.title.slice(0, 160) : null,
    category: typeof raw.category === 'string' ? normalizeCategory(raw.category) : null,
    amount: typeof raw.amount === 'number' && Number.isFinite(raw.amount) ? raw.amount : null,
    currency: typeof raw.currency === 'string' ? raw.currency.toUpperCase().slice(0, 3) : null,
    date: normalizeDate(raw.date),
    recurring: typeof raw.recurring === 'string' ? raw.recurring : null,
    reminderOffsets: Array.isArray(raw.reminderOffsets) ? raw.reminderOffsets.filter((n) => Number.isInteger(n) && n >= 0 && n <= 3650).slice(0, 8) : null,
    notes: typeof raw.notes === 'string' ? raw.notes.slice(0, 1000) : null,
    confidence
  };
}

function buildGeminiUrl() {
  return `https://generativelanguage.googleapis.com/${apiVersion}/models/${model}:generateContent`;
}

async function callGemini(text) {
  if (!key) return { status: 503, body: { error: 'missing_secure_environment_variable' } };
  const url = buildGeminiUrl();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(url, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': key
      },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: buildPrompt(text.slice(0, 4000)) }] }],
        generationConfig: { responseMimeType: 'application/json', temperature: 0.1, maxOutputTokens: 512 }
      })
    });
    if (!response.ok) {
      const errorBody = await response.text().catch(() => '');
      safeLog('Gemini API returned a non-ok response', { geminiStatus: response.status, geminiBody: errorBody.slice(0, 500) });
      if (response.status === 429) return { status: 429, body: { error: 'rate_limited' } };
      if (response.status === 401 || response.status === 403) return { status: 401, body: { error: 'authentication_failed' } };
      if (response.status >= 500) return { status: 503, body: { error: 'service_unavailable' } };
      return { status: 502, body: { error: 'gemini_request_failed' } };
    }
    const payload = await response.json();
    const textPart = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!textPart) return { status: 502, body: { error: 'empty_ai_response' } };
    let parsed;
    try { parsed = JSON.parse(textPart); } catch { return { status: 502, body: { error: 'malformed_ai_json' } }; }
    return { status: 200, body: toExtraction(parsed) };
  } catch (error) {
    if (error.name === 'AbortError') return { status: 408, body: { error: 'timeout' } };
    safeLog('Gemini proxy request failed', { code: error.code || 'network' });
    return { status: 503, body: { error: 'network_or_service_unavailable' } };
  } finally {
    clearTimeout(timer);
  }
}

const server = http.createServer(async (req, res) => {
  if (req.method !== 'POST' || req.url !== '/v1/extract') return send(res, 404, { error: 'not_found' });
  let body = '';
  req.on('data', (chunk) => { body += chunk; if (body.length > 12000) req.destroy(); });
  req.on('end', async () => {
    try {
      const parsed = JSON.parse(body || '{}');
      if (typeof parsed.text !== 'string' || parsed.text.trim().length === 0) return send(res, 400, { error: 'invalid_request' });
      const result = await callGemini(parsed.text);
      send(res, result.status, result.body);
    } catch {
      send(res, 400, { error: 'invalid_request' });
    }
  });
});

if (require.main === module) {
  server.listen(port, () => safeLog('Life Admin Gemini proxy listening', { port, model, apiVersion, keyConfigured: Boolean(key) }));
}

module.exports = { buildPrompt, toExtraction, normalizeDate, callGemini, buildGeminiUrl, model, apiVersion };
