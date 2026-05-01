#!/usr/bin/env bash
# ==============================================================================
# GRAPPL — scripts/setup-supabase.sh
#
# Implements local Supabase bootstrap per docs/GRAPPL_Build_Plan_v1.0.md (146–200):
#   1) Require Supabase CLI and jq.
#   2) supabase init in repo root when supabase/config.toml is missing.
#   3) Idempotent patch of supabase/config.toml for non-default ports (54331–54337).
#   4) supabase start when stack is not running (tee output); if already running, print status.
#   5) Parse supabase status --output json via jq; print API URL, keys, DB URL, Studio URL.
#   6) Merge SUPABASE_* and DATABASE_URL into .env.local (preserves other lines).
#   7) Print Studio availability line for port 54333.
#
# Idempotent: safe to re-run; skips start when local stack is already healthy.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_TOML="${REPO_ROOT}/supabase/config.toml"
ENV_LOCAL="${REPO_ROOT}/.env.local"

# Expected non-default ports (avoid clashes with other local Supabase projects).
PORT_API=54331
PORT_DB=54332
PORT_STUDIO=54333
PORT_INBUCKET=54334
PORT_ANALYTICS=54337

# ------------------------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------------------------
require_cmd() {
  local name="$1"
  local hint="$2"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "Error: '${name}' is not installed or not on PATH." >&2
    echo "  ${hint}" >&2
    exit 1
  fi
}

require_cmd supabase "Install: https://supabase.com/docs/guides/cli"
require_cmd jq "Install: https://jqlang.github.io/jq/download/ (needed to parse 'supabase status --output json')"

# ------------------------------------------------------------------------------
# Step 1 — supabase init (idempotent)
# ------------------------------------------------------------------------------
cd "${REPO_ROOT}"

if [[ ! -f "${CONFIG_TOML}" ]]; then
  echo "Initializing Supabase project (supabase init)..."
  supabase init
fi

if [[ ! -f "${CONFIG_TOML}" ]]; then
  echo "Error: expected ${CONFIG_TOML} after supabase init." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 2 — Patch config.toml ports (idempotent: only rewrite first port= in each section)
# ------------------------------------------------------------------------------
patch_supabase_ports() {
  local cfg="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v pa="${PORT_API}" -v pdb="${PORT_DB}" -v ps="${PORT_STUDIO}" \
    -v pi="${PORT_INBUCKET}" -v pan="${PORT_ANALYTICS}" '
    $0 == "[api]" { sec="api"; print; next }
    $0 == "[db]" { sec="db"; print; next }
    $0 == "[studio]" { sec="studio"; print; next }
    $0 == "[inbucket]" { sec="inbucket"; print; next }
    $0 == "[analytics]" { sec="analytics"; print; next }
    sec == "api" && /^port = / { print "port = " pa; sec=""; next }
    sec == "db" && /^port = / { print "port = " pdb; sec=""; next }
    sec == "studio" && /^port = / { print "port = " ps; sec=""; next }
    sec == "inbucket" && /^port = / { print "port = " pi; sec=""; next }
    sec == "analytics" && /^port = / { print "port = " pan; sec=""; next }
    { print }
  ' "${cfg}" >"${tmp}"
  mv "${tmp}" "${cfg}"
}

if grep -qE '^port = '"${PORT_API}"'$' "${CONFIG_TOML}" 2>/dev/null &&
  grep -qE '^port = '"${PORT_DB}"'$' "${CONFIG_TOML}" 2>/dev/null &&
  grep -qE '^port = '"${PORT_STUDIO}"'$' "${CONFIG_TOML}" 2>/dev/null &&
  grep -qE '^port = '"${PORT_INBUCKET}"'$' "${CONFIG_TOML}" 2>/dev/null &&
  grep -qE '^port = '"${PORT_ANALYTICS}"'$' "${CONFIG_TOML}" 2>/dev/null; then
  echo "Supabase config already uses GRAPPL ports; skipping TOML rewrite."
else
  echo "Patching ${CONFIG_TOML} for GRAPPL ports (${PORT_API}, ${PORT_DB}, ${PORT_STUDIO}, ${PORT_INBUCKET}, ${PORT_ANALYTICS})..."
  patch_supabase_ports "${CONFIG_TOML}"
fi

# ------------------------------------------------------------------------------
# Step 3 — Start stack if needed (idempotent)
# ------------------------------------------------------------------------------
START_LOG="$(mktemp)"
STATUS_JSON="$(mktemp)"
trap 'rm -f "${START_LOG}" "${STATUS_JSON}"' EXIT

is_stack_running() {
  supabase status --output json >/dev/null 2>&1
}

if is_stack_running; then
  echo "Supabase local stack is already running; skipping supabase start."
  echo ""
  supabase status || true
  echo ""
else
  echo "Starting Supabase (supabase start)..."
  if ! supabase start 2>&1 | tee "${START_LOG}"; then
    echo "Error: supabase start failed. Last lines of output:" >&2
    tail -n 40 "${START_LOG}" >&2 || true
    exit 1
  fi
fi

# ------------------------------------------------------------------------------
# Step 4 — Credentials from JSON status
# ------------------------------------------------------------------------------
if ! supabase status --output json >"${STATUS_JSON}" 2>/dev/null; then
  echo "Error: supabase status --output json failed." >&2
  exit 1
fi

API_URL="$(jq -r '.API_URL // empty' "${STATUS_JSON}")"
DB_URL="$(jq -r '.DB_URL // empty' "${STATUS_JSON}")"
STUDIO_URL="$(jq -r '.STUDIO_URL // empty' "${STATUS_JSON}")"
# Newer CLI uses PUBLISHABLE_KEY / SECRET_KEY; older uses ANON_KEY / SERVICE_ROLE_KEY
ANON_KEY="$(jq -r '(.ANON_KEY // .PUBLISHABLE_KEY // empty)' "${STATUS_JSON}")"
SERVICE_ROLE_KEY="$(jq -r '(.SERVICE_ROLE_KEY // .SECRET_KEY // empty)' "${STATUS_JSON}")"

if [[ -z "${API_URL}" || -z "${DB_URL}" || -z "${ANON_KEY}" || -z "${SERVICE_ROLE_KEY}" ]]; then
  echo "Error: could not read required fields from supabase status JSON." >&2
  echo "  API_URL='${API_URL}' DB_URL(set=$([[ -n "${DB_URL}" ]] && echo yes || echo no))" >&2
  echo "  ANON_KEY(set=$([[ -n "${ANON_KEY}" ]] && echo yes || echo no)) SERVICE_ROLE_KEY(set=$([[ -n "${SERVICE_ROLE_KEY}" ]] && echo yes || echo no))" >&2
  exit 1
fi

echo ""
echo "--- Supabase connection values ---"
echo "API URL:           ${API_URL}"
echo "anon key:          ${ANON_KEY}"
echo "service_role key:  ${SERVICE_ROLE_KEY}"
echo "DB URL:            ${DB_URL}"
echo "Studio URL:        ${STUDIO_URL:-http://127.0.0.1:${PORT_STUDIO}}"
echo "-----------------------------------"
echo ""

# ------------------------------------------------------------------------------
# Step 5 — Merge into .env.local
# ------------------------------------------------------------------------------
merge_env_local() {
  local f="$1"
  local keys_regex='^(SUPABASE_URL|SUPABASE_ANON_KEY|SUPABASE_SERVICE_ROLE_KEY|DATABASE_URL)='
  if [[ -f "${f}" ]]; then
    # grep exits 1 when every line is filtered out; still produce an empty file under set -e
    grep -Ev "${keys_regex}" "${f}" >"${f}.tmp" || true
    mv "${f}.tmp" "${f}"
  fi
  {
    echo "SUPABASE_URL=${API_URL}"
    echo "SUPABASE_ANON_KEY=${ANON_KEY}"
    echo "SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}"
    echo "DATABASE_URL=${DB_URL}"
  } >>"${f}"
}

merge_env_local "${ENV_LOCAL}"
echo "Wrote Supabase variables to ${ENV_LOCAL}"

echo "Supabase Studio is available at: http://localhost:${PORT_STUDIO}"
