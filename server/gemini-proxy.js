#!/usr/bin/env node
const http = require('http');

const model = 'gemini-3.5-flash-lite';
const apiVersion = 'v1beta';
const port = Number(process.env.PORT || 8787);
const key = process.env.GEMINI_API_KEY;
const sharedSecret = process.env.APP_SHARED_SECRET;

// This endpoint is public (its URL ships inside the iOS app binary, trivially recoverable with
// `strings`), forwards every request to a paid Gemini API key, and otherwise had no limit on who
// could call it or how often — anyone who found the URL could run up the owner's AI bill or exhaust
// their quota. Neither check below is a real secret boundary (a shared value baked into the app can
// always be extracted from the binary; the rate limiter is in-memory and resets on every cold
// start), but together they block casual/scripted abuse, which is the realistic threat here.
const rateLimitWindowMs = 60_000;
const rateLimitMaxPerWindow = 20;
const requestTimestampsByIP = new Map();

function checkSharedSecret(headerValue) {
  if (!sharedSecret) return true; // not configured yet: opt-in, so this can't break existing deployments
  return headerValue === sharedSecret;
}

function checkRateLimit(ip) {
  const key = ip || 'unknown';
  const now = Date.now();
  const recent = (requestTimestampsByIP.get(key) || []).filter((t) => now - t < rateLimitWindowMs);
  if (recent.length >= rateLimitMaxPerWindow) {
    requestTimestampsByIP.set(key, recent);
    return false;
  }
  recent.push(now);
  requestTimestampsByIP.set(key, recent);
  if (requestTimestampsByIP.size > 5000) requestTimestampsByIP.clear(); // bound memory on a long-lived warm instance
  return true;
}

// The X-Forwarded-For chain is built as `client, proxy1, proxy2, ...` — each hop APPENDS the
// peer address it observed to the end. A client can set (or prepend anything to) this header
// freely, but cannot control what the nearest trusted hop (Vercel's own edge, or this server's
// own socket peer when run standalone) appends after receiving the request. Keying the rate
// limiter off the FIRST entry — as this used to — let anyone bypass it entirely by sending a
// fresh spoofed value on every request; verified with a script sending 25 requests each with a
// distinct fake first entry, all 25 got through. The LAST entry is the one that isn't
// attacker-controlled.
function clientIP(headers, socketAddress) {
  const forwarded = headers['x-forwarded-for'];
  const value = Array.isArray(forwarded) ? forwarded[forwarded.length - 1] : forwarded;
  const parts = value?.split(',').map((p) => p.trim()).filter(Boolean);
  return (parts && parts[parts.length - 1]) || socketAddress || 'unknown';
}

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
  return `You extract structured Life Admin items. Return only JSON. Extract only facts present in the user text. Never invent prices, companies, or people. Today's date is ${today}. Always output complete dates as YYYY-MM-DD — never a partial date missing the year. When the user gives a recurring date without a year (for example "every March 18"), resolve it to the next future occurrence: use this year if that month/day has not yet passed relative to today, otherwise use next year. Use null when a date is missing entirely. Use null for other fields when missing. Preserve currency as ISO 4217. Mark ambiguous fields with lower confidence. If the text is (or looks like) OCR output from a scanned identity document, payment card, or similar official document (a passport, ID card, driver's license, insurance card, credit/debit card, vehicle registration, etc.), also populate documentFields with every other specific, labeled detail actually present that isn't already covered by the fields above — for example a passport number, full name, nationality, date of birth, issuing authority, or a card's bank/issuer name, cardholder name, card number, and expiry month/year. Each entry is {"label": a short human-readable field name, "value": the exact value as written}. CRITICAL SAFETY RULE: NEVER include a card verification code (CVV, CVC, CID, or any "security code") in documentFields, even if it appears in the text — omit it entirely, no exceptions. If nothing beyond the fields above applies, or the text isn't from such a document, return an empty array. Schema: {"title": string|null, "category": one of documents,insurance,money,bills,subscriptions,car,home,health,travel,work,education,shopping,warranties,memberships,appointments,personal,family,other|null, "amount": number|null, "currency": string|null, "date": string|null, "recurring": one of none,daily,weekly,biweekly,monthly,everyTwoMonths,quarterly,everySixMonths,yearly,custom|null, "reminderOffsets": number[]|null, "notes": string|null, "documentFields": [{"label": string, "value": string}], "confidence": number}. User text: ${JSON.stringify(text)}`;
}

// Defense in depth, independent of the prompt instruction above (which a model can still get
// wrong): a card verification code must never leave this proxy under any label naming it, no
// matter what Gemini actually returns. The client (AIJSONValidator.decode, in Core) repeats this
// same filter for the same reason — neither side should have to fully trust the other.
// The original pattern only caught the handful of names spelled out here — verified it let
// through several other names real card issuers actually use for the same field: "CSC" (Card
// Security Code), "CVN" (Card Verification Number), "Card Identification Number" (Amex's own
// full name for what "CID" abbreviates), "Card Security Value", "Sec Code", and phrasing like
// "3-digit code on back" or "Verification No." — all of which a reasonable person would
// recognize as "the CVV field" but none of which matched. Kept in sync with
// DocumentFieldSafety.forbiddenLabelPattern in Swift (Sources/LifeAdminCore/NaturalLanguage.swift)
// — this is defense in depth, not a single point of trust, so both layers need the same coverage.
const FORBIDDEN_DOCUMENT_FIELD_LABEL = /\b(cvv2?|cvc2?|cvn|csc|cid)\b|card\s*identification\s*number|security\s*(code|value|number)|verification\s*(code|number|value|no\.?)|card\s*verification|\bsec\.?\s*code\b|\d\s*-?\s*digit\s*(security\s*)?code/i;

function sanitizeDocumentFields(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((f) => f && typeof f.label === 'string' && typeof f.value === 'string')
    .filter((f) => f.label.trim().length > 0 && f.value.trim().length > 0)
    .filter((f) => !FORBIDDEN_DOCUMENT_FIELD_LABEL.test(f.label))
    .slice(0, 20)
    .map((f) => ({ label: f.label.slice(0, 60), value: f.value.slice(0, 200) }));
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
    documentFields: sanitizeDocumentFields(raw.documentFields),
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
      // Google's error body can quote back part of the request on a validation-style 4xx, which
      // itself embeds the user's original free text (amounts, insurance/medical details, per
      // buildPrompt above) — so only its length is logged, never its content.
      const errorBody = await response.text().catch(() => '');
      safeLog('Gemini API returned a non-ok response', { geminiStatus: response.status, geminiBodyLength: errorBody.length });
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
    // A separate try/catch from the outer one below: `toExtraction`'s own validation throws
    // (invalid confidence, wrong types) were previously falling through to the generic `catch
    // (error)` at the bottom of this function, which logs and reports them as `code: 'network'` /
    // `network_or_service_unavailable` — a genuine data-validation failure misreported as a
    // network outage, verified by mocking a `confidence: 1.5` response. This keeps it alongside
    // the identical `malformed_ai_json` handling just above instead.
    try {
      return { status: 200, body: toExtraction(parsed) };
    } catch (error) {
      safeLog('Gemini returned invalid structured output', { message: error.message });
      return { status: 502, body: { error: 'invalid_structured_output' } };
    }
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
  if (!checkSharedSecret(req.headers['x-app-secret'])) return send(res, 401, { error: 'authentication_failed' });
  if (!checkRateLimit(clientIP(req.headers, req.socket?.remoteAddress))) return send(res, 429, { error: 'rate_limited' });
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

module.exports = { buildPrompt, toExtraction, normalizeDate, sanitizeDocumentFields, callGemini, buildGeminiUrl, model, apiVersion, checkSharedSecret, checkRateLimit, clientIP };
