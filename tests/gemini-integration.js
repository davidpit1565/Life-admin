#!/usr/bin/env node
const { callGemini, model } = require('../server/gemini-proxy');

async function callDeployedProxy(endpoint) {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ text: 'Remind me tomorrow to call the dentist' })
  });
  return { status: response.status, body: await response.json() };
}

(async () => {
  const endpoint = process.env.LIFE_ADMIN_PROXY_URL;
  if (!endpoint && !process.env.GEMINI_API_KEY) {
    console.error('Gemini integration: missing LIFE_ADMIN_PROXY_URL or secure server-side GEMINI_API_KEY');
    process.exit(2);
  }
  const result = endpoint ? await callDeployedProxy(endpoint) : await callGemini('My car insurance costs €840 and renews every March 18.');
  if (result.status !== 200) {
    console.error(`Gemini integration failed with status ${result.status}`);
    process.exit(1);
  }
  const body = result.body;
  if (!body || body.title == null || body.category == null || typeof body.confidence !== 'number') {
    console.error('Gemini integration failed structured extraction validation');
    process.exit(1);
  }
  const leaked = JSON.stringify(body).includes('AI' + 'za') || JSON.stringify(body).includes('GEMINI' + '_API' + '_KEY');
  if (leaked) {
    console.error('Gemini integration failed secret isolation validation');
    process.exit(1);
  }
  console.log(`Gemini integration passed using ${model}`);
})();
