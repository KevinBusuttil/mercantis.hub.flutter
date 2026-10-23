#!/usr/bin/env bash
# Real multi-device Team test: builds the Atlas Team backend, starts it on a
# fresh PostgreSQL database, and runs test/team_e2e against it (three hub
# devices, each with its own SQLite books, over real HTTP).
#
#   ATLAS_BACKEND_DIR=../neuradix-atlas-team-backend \
#   ATLAS_E2E_ADMIN_URL=postgres://atlas:atlas@localhost:5432/postgres \
#   tool/team_e2e.sh
#
# Needs cargo, psql and flutter on PATH. The database is dropped afterwards
# unless ATLAS_E2E_KEEP_DB=1. No credentials are written anywhere: the test
# creates throwaway companies and tokens in the throwaway database.
set -euo pipefail

backend_dir=${ATLAS_BACKEND_DIR:-../neuradix-atlas-team-backend}
admin_url=${ATLAS_E2E_ADMIN_URL:-postgres://atlas:atlas@localhost:5432/postgres}
port=${ATLAS_E2E_PORT:-18080}
db="atlas_e2e_$(date +%s)"
db_url="${admin_url%/*}/$db"
log=$(mktemp -t atlas-e2e-backend.XXXXXX)

(cd "$backend_dir" && cargo build --release --quiet)
psql "$admin_url" -qc "create database $db"

cleanup() {
  [[ -n ${backend_pid:-} ]] && kill "$backend_pid" 2>/dev/null || true
  wait "${backend_pid:-}" 2>/dev/null || true
  if [[ ${ATLAS_E2E_KEEP_DB:-0} != 1 ]]; then
    psql "$admin_url" -qc "drop database if exists $db" || true
  fi
}
trap cleanup EXIT

# Started WITHOUT ATLAS_BOOTSTRAP_TOKEN: the test creates its companies.
env -u ATLAS_BOOTSTRAP_TOKEN DATABASE_URL="$db_url" PORT="$port" \
  "$backend_dir/target/release/atlas-team-backend" >"$log" 2>&1 &
backend_pid=$!
for _ in $(seq 1 50); do
  curl -fsS "http://127.0.0.1:$port/ready" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -fsS "http://127.0.0.1:$port/ready" >/dev/null || { cat "$log"; exit 1; }

ATLAS_TEAM_E2E_URL="http://127.0.0.1:$port" flutter test test/team_e2e/ "$@"
echo "backend log: $log"
