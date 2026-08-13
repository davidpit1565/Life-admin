#!/usr/bin/env bash
set -euo pipefail
swift test
swift run lifeadmin-qa
if rg -n "AIza|GEMINI_API_KEY|TODO|Lorem ipsum|Coming soon" . --glob '!/.git/**' --glob '!scripts/qa.sh'; then echo "QA secret/placeholder scan failed"; exit 1; fi
echo "QA complete"
