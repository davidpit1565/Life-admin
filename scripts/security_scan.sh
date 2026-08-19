#!/usr/bin/env bash
set -euo pipefail
command -v rg >/dev/null 2>&1 || { echo "ripgrep (rg) is required but not installed"; exit 1; }
fail=0
if rg -n "AIza|placeholder API key|fake secret|Authorization: Bearer|key=[A-Za-z0-9_-]{20,}|TODO|Lorem ipsum|Coming soon" . --glob '!/.git/**' --glob '!.build/**' --glob '!scripts/security_scan.sh' --glob '!scripts/qa.sh'; then fail=1; fi
if rg -n "GEMINI_API_KEY" . --glob '!/.git/**' --glob '!.build/**' | rg -v 'docs/GEMINI_CONFIGURATION.md|docs/BUILD_AND_TESTING.md|server/gemini-proxy.js|js-tests/gemini-integration.js|scripts/qa.sh|scripts/security_scan.sh|.env.example'; then fail=1; fi
if [[ $fail -ne 0 ]]; then echo "Security scan failed"; exit 1; fi
echo "Security scan passed"
