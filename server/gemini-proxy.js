#!/usr/bin/env node
const http = require('http');

const model = 'gemini-2.5-flash-lite-latest';
const port = Number(process.env.PORT || 8787);
const key = process.env.GEMINI_API_KEY;

function safeLog(message, meta = {}) {
  const clean = { ...meta };
  delete clean.authorization;
  delete clean.apiKey;
  delete clean.key;
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

function buildPrompt(text) {
  return `You extract structured Life Admin items. Return only JSON. Extract only facts present in the user text. Never invent dates, prices, companies, people, or currencies. Use ISO 8601 dates. Use null when missing. Preserve currency as ISO 4217. Mark ambiguous fields with lower confidence. Schema: {"title": string|null, "category": one of documents,insurance,money,bills,subscriptions,car,home,health,travel,work,education,shopping,warranties,memberships,appointments,personal,family,other|null, "amount": number|null, "currency": string|null, "date": string|null, "recurring": one of none,daily,weekly,biweekly,monthly,everyTwoMonths,quarterly,everySixMonths,yearly,custom|null, "reminderOffsets": number[]|null, "notes": string|null, "confidence": number}. User text: ${JSON.stringify(text)}`;
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
    date: typeof raw.date === 'string' ? raw.date : null,
    recurring: typeof raw.recurring === 'string' ? raw.recurring : null,
    reminderOffsets: Array.isArray(raw.reminderOffsets) ? raw.reminderOffsets.filter((n) => Number.isInteger(n) && n >= 0 && n <= 3650).slice(0, 8) : null,
    notes: typeof raw.notes === 'string' ? raw.notes.slice(0, 1000) : null,
    confidence
  };
}

async function callGemini(text) {
  if (!key) return { status: 503, body: { error: 'missing_secure_environment_variable' } };
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(key)}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(url, {
      method: 'POST',
      signal: controller.signal,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: buildPrompt(text.slice(0, 4000)) }] }],
        generationConfig: { responseMimeType: 'application/json', temperature: 0.1, maxOutputTokens: 512 }
      })
    });
    if (response.status === 429) return { status: 429, body: { error: 'rate_limited' } };
    if (response.status === 401 || response.status === 403) return { status: 401, body: { error: 'authentication_failed' } };
    if (response.status >= 500) return { status: 503, body: { error: 'service_unavailable' } };
    if (!response.ok) {
  let upstreamError = null;
  try {
    const errorPayload = await response.json();
    upstreamError = {
      status: errorPayload?.error?.status || null,
      message: errorPayload?.error?.message || null
    };
  } catch {}
  return {
    status: 502,
    body: {
      error: 'gemini_request_failed',
      upstream_status: response.status,
      upstream_error: upstreamError
    }
  };
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
  server.listen(port, () => safeLog('Life Admin Gemini proxy listening', { port, model, keyConfigured: Boolean(key) }));
}

module.exports = { buildPrompt, toExtraction, callGemini, model };
