# Gemini Configuration

Life Admin uses Gemini only through the server-side proxy in `server/gemini-proxy.js`. The iOS app calls the proxy endpoint (`POST /v1/extract`) and never receives or stores the Gemini secret.

## Required secret

Configure `GEMINI_API_KEY` as a server-side environment variable in local development and in the deployment platform's secret manager. Do not place the value in Swift source, Info.plist, app resources, JavaScript bundles sent to clients, or Git.

## Model

The proxy uses `gemini-2.5-flash-lite` for structured Life Admin extraction.

## Local verification

Run:

```bash
GEMINI_API_KEY=<secure value from your secret manager> node tests/gemini-integration.js
```

The script verifies the secret is present server-side, sends a minimal structured extraction request, and does not print the secret.

## Vercel deployment

The production serverless endpoint is `POST /v1/extract`, routed by `vercel.json` to `api/extract.js`. The function calls the shared server-side Gemini proxy module and reads `GEMINI_API_KEY` only from the Vercel server environment.

To verify a deployed proxy without exposing the secret, set only the public endpoint URL locally:

```bash
LIFE_ADMIN_PROXY_URL=https://<deployment-host>/v1/extract node tests/gemini-integration.js
```
