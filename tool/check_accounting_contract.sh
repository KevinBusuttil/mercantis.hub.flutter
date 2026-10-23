#!/usr/bin/env bash
# Fails when the hub's copy of the shared accounting contract has drifted
# from the Team backend's tests/fixtures (the source of truth).
#
#   ATLAS_BACKEND_DIR=../neuradix-atlas-team-backend tool/check_accounting_contract.sh
#   tool/check_accounting_contract.sh --sync     # copy the backend's fixtures in
set -euo pipefail
backend_dir=${ATLAS_BACKEND_DIR:-../neuradix-atlas-team-backend}
src="$backend_dir/tests/fixtures"
dst=test/fixtures/accounting_contract
if [[ ${1:-} == --sync ]]; then
  rm -f "$dst"/*.json && cp "$src"/*.json "$dst"/ && echo "synced from $src"
  exit 0
fi
diff -r "$src" "$dst" && echo "accounting contract in sync with $src"
