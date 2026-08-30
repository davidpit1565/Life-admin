const { callGemini, checkSharedSecret, checkRateLimit, clientIP } = require('../server/gemini-proxy');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('allow', 'POST');
    return res.status(405).json({ error: 'method_not_allowed' });
  }

  if (!checkSharedSecret(req.headers['x-app-secret'])) {
    return res.status(401).json({ error: 'authentication_failed' });
  }
  if (!checkRateLimit(clientIP(req.headers, req.socket?.remoteAddress))) {
    return res.status(429).json({ error: 'rate_limited' });
  }

  const text = req.body && typeof req.body.text === 'string' ? req.body.text : null;
  if (!text || text.trim().length === 0) {
    return res.status(400).json({ error: 'invalid_request' });
  }

  const result = await callGemini(text);
  return res.status(result.status).json(result.body);
};
