#!/usr/bin/env node
const { callGemini, model } = require('../server/gemini-proxy');

(async () => {
  if (!process.env.GEMINI_API_KEY) {
    console.error('Gemini integration: missing secure environment variable GEMINI_API_KEY');
    process.exit(2);
  }
  const result = await callGemini('My car insurance costs €840 and renews every March 18.');
  if (result.status !== 200) {
    console.error(`Gemini integration failed with status ${result.status}`);
    process.exit(1);
  }
  const body = result.body;
  if (!body || body.title == null || body.category == null || typeof body.confidence !== 'number') {
    console.error('Gemini integration failed structured extraction validation');
    process.exit(1);
  }
  console.log(`Gemini integration passed using ${model}`);
})();
