#!/usr/bin/env bash
set -euo pipefail
swift test
swift run lifeadmin-qa
./scripts/security_scan.sh
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  node js-tests/gemini-integration.js
else
  echo "Gemini integration warning: missing secure environment variable GEMINI_API_KEY"
fi
if rg -n "AIza|GEMINI_API_KEY|TODO|Lorem ipsum|Coming soon" . --glob '!/.git/**' --glob '!scripts/qa.sh'; then echo "QA secret/placeholder scan failed"; exit 1; fi
echo "QA complete"
