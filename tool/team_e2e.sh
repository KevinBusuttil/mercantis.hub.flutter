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
# The auth rate limit is per client address, and every device here is
# 127.0.0.1: the full suite creates more companies and invitations a minute
# than one real client would, so it is off for this throwaway backend.
env -u ATLAS_BOOTSTRAP_TOKEN DATABASE_URL="$db_url" PORT="$port" ATLAS_RL_AUTH_PER_MIN=0 \
  "$backend_dir/target/release/atlas-team-backend" >"$log" 2>&1 &
backend_pid=$!
for _ in $(seq 1 50); do
  curl -fsS "http://127.0.0.1:$port/ready" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -fsS "http://127.0.0.1:$port/ready" >/dev/null || { cat "$log"; exit 1; }

export ATLAS_TEAM_E2E_URL="http://127.0.0.1:$port"
# The restore scenarios rewind the whole database with pg_restore, so they
# run on their own, after every other file.
export ATLAS_E2E_DB_URL="$db_url"
if [[ $# -gt 0 ]]; then
  flutter test "$@"
else
  flutter test test/team_e2e/ --exclude-tags team-restore
  flutter test test/team_e2e/team_restore_e2e_test.dart
fi
echo "backend log: $log"
