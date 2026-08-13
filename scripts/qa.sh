#!/usr/bin/env bash
set -euo pipefail
swift test
swift run lifeadmin-qa
./scripts/security_scan.sh
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  node tests/gemini-integration.js
else
  echo "Gemini integration warning: missing secure environment variable GEMINI_API_KEY"
fi
echo "QA complete"
