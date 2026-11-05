#!/usr/bin/env bash
# Fails when the hub's copy of the shared contracts has drifted from the
# Team backend (the source of truth):
#   * the accounting fixtures: backend tests/fixtures
#     -> test/fixtures/accounting_contract
#   * the protocol contract (C6): backend contract/team_protocol.json
#     -> test/fixtures/team_protocol.json
#
#   ATLAS_BACKEND_DIR=../neuradix-atlas-team-backend tool/check_accounting_contract.sh
#   tool/check_accounting_contract.sh --sync     # copy the backend's files in
set -euo pipefail
backend_dir=${ATLAS_BACKEND_DIR:-../neuradix-atlas-team-backend}
src="$backend_dir/tests/fixtures"
dst=test/fixtures/accounting_contract
protocol_src="$backend_dir/contract/team_protocol.json"
protocol_dst=test/fixtures/team_protocol.json
if [[ ${1:-} == --sync ]]; then
  rm -f "$dst"/*.json && cp "$src"/*.json "$dst"/
  cp "$protocol_src" "$protocol_dst"
  echo "synced from $backend_dir"
  exit 0
fi
diff -r "$src" "$dst" && echo "accounting contract in sync with $src"
diff "$protocol_src" "$protocol_dst" && echo "protocol contract in sync with $protocol_src"
