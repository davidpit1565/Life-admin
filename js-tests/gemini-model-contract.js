#!/usr/bin/env node
const assert = require('node:assert/strict');
const { buildGeminiUrl, model, apiVersion } = require('../server/gemini-proxy');

assert.equal(model, 'gemini-3.5-flash-lite');
assert.equal(apiVersion, 'v1beta');
assert.equal(buildGeminiUrl(), 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent');
assert.ok(!buildGeminiUrl().includes('-latest'));
console.log(`Gemini request contract passed: ${apiVersion}/${model}`);
