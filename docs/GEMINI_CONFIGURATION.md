# Gemini Configuration

Life Admin uses Gemini only through the server-side proxy in `server/gemini-proxy.js`. The iOS app calls the proxy endpoint (`POST /v1/extract`) and never receives or stores the Gemini secret.

## Required secret

Configure `GEMINI_API_KEY` as a server-side environment variable in local development and in the deployment platform's secret manager. Do not place the value in Swift source, Info.plist, app resources, JavaScript bundles sent to clients, or Git.

## Model

The proxy uses `gemini-3.5-flash-lite` for structured Life Admin extraction. Google
periodically retires older model IDs; if the proxy starts returning
`gemini_request_failed`, check the deployment's runtime logs for a
`"Gemini API returned a non-ok response"` entry — Google's 404 error message names
the exact replacement model ID to switch to.

## Abuse protection

`/v1/extract` is a public endpoint (its URL ships inside the app binary, trivially recoverable),
and it forwards every request to a paid Gemini API key. Two independent, best-effort protections
are built in:

- **Per-IP rate limit** — always on, no configuration needed. In-memory, so it resets on every
  cold start; this blunts a sustained scripted attacker but is not a hard guarantee.
- **Shared-secret header** — off by default. Set `APP_SHARED_SECRET` to a long random value in
  the Vercel project's environment variables, and set the identical value as
  `geminiProxySharedSecret` in `LifeAdminApp/AppConfig.swift`, then rebuild the app. This is not a
  real secret (anything shipped in the app binary can be extracted with `strings`), but it stops
  the endpoint from answering requests that were never sent by this app at all.

Neither measure replaces watching actual spend: set a budget alert on the Gemini API key itself
in Google AI Studio / Cloud Console so a determined abuser can't run up an unbounded bill even if
both of the above are bypassed.

## Local verification

Run:

```bash
GEMINI_API_KEY=<secure value from your secret manager> node js-tests/gemini-integration.js
```

The script verifies the secret is present server-side, sends a minimal structured extraction request, and does not print the secret.

## Vercel deployment

The production serverless endpoint is `POST /v1/extract`, routed by `vercel.json` to `api/extract.js`. The function calls the shared server-side Gemini proxy module and reads `GEMINI_API_KEY` only from the Vercel server environment.

To verify a deployed proxy without exposing the secret, set only the public endpoint URL locally:

```bash
LIFE_ADMIN_PROXY_URL=https://<deployment-host>/v1/extract node js-tests/gemini-integration.js
```
