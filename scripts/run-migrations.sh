#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MIGRATIONS_DIR="${REPO_ROOT}/infra/supabase/migrations"
SUPABASE_MIGRATIONS_DIR="${REPO_ROOT}/supabase/migrations"
ENV_LOCAL="${REPO_ROOT}/.env.local"

readonly EXPECTED_MIGRATION_FILES=(
  "001_enable_extensions.sql"
  "002_create_practitioners.sql"
  "003_create_event_types.sql"
  "004_create_sessions.sql"
  "005_create_events.sql"
  "006_create_clips.sql"
  "007_create_coaching_notes.sql"
  "008_create_session_summaries.sql"
  "009_row_level_security.sql"
  "010_updated_at_trigger.sql"
)

require_cmd() {
  local command_name="$1"
  local install_hint="$2"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "[run-migrations.sh] ERROR: '${command_name}' was not found in PATH." >&2
    echo "[run-migrations.sh] ${install_hint}" >&2
    exit 1
  fi
}

validate_file_exists() {
  local file_path="$1"
  if [[ ! -f "${file_path}" ]]; then
    echo "[run-migrations.sh] ERROR: missing required file: ${file_path}" >&2
    exit 1
  fi
}

validate_directory_exists() {
  local directory_path="$1"
  if [[ ! -d "${directory_path}" ]]; then
    echo "[run-migrations.sh] ERROR: missing required directory: ${directory_path}" >&2
    exit 1
  fi
}

validate_url_format() {
  local name="$1"
  local value="$2"
  local regex="$3"
  if [[ ! "${value}" =~ ${regex} ]]; then
    echo "[run-migrations.sh] ERROR: ${name} has an invalid format." >&2
    exit 1
  fi
}

read_env_value() {
  local key="$1"
  local env_file="$2"
  awk -F '=' -v k="${key}" '$1 == k {print substr($0, index($0, "=") + 1); exit}' "${env_file}"
}

validate_migration_files() {
  local migration_file
  for migration_file in "${EXPECTED_MIGRATION_FILES[@]}"; do
    validate_file_exists "${MIGRATIONS_DIR}/${migration_file}"
  done
}

sync_migrations_for_supabase_cli() {
  mkdir -p "${SUPABASE_MIGRATIONS_DIR}"

  local migration_file
  for migration_file in "${EXPECTED_MIGRATION_FILES[@]}"; do
    cp "${MIGRATIONS_DIR}/${migration_file}" "${SUPABASE_MIGRATIONS_DIR}/${migration_file}"
  done
}

print_row_counts() {
  local database_url="$1"
  psql "${database_url}" -v ON_ERROR_STOP=1 <<'SQL'
SELECT
  'practitioners' AS table_name,
  COUNT(*)::BIGINT AS row_count
FROM public.practitioners
UNION ALL
SELECT 'event_types', COUNT(*)::BIGINT FROM public.event_types
UNION ALL
SELECT 'sessions', COUNT(*)::BIGINT FROM public.sessions
UNION ALL
SELECT 'events', COUNT(*)::BIGINT FROM public.events
UNION ALL
SELECT 'clips', COUNT(*)::BIGINT FROM public.clips
UNION ALL
SELECT 'coaching_notes', COUNT(*)::BIGINT FROM public.coaching_notes
UNION ALL
SELECT 'session_summaries', COUNT(*)::BIGINT FROM public.session_summaries
ORDER BY table_name;
SQL
}

main() {
  require_cmd supabase "Install Supabase CLI: https://supabase.com/docs/guides/cli"
  require_cmd psql "Install PostgreSQL client tools for the 'psql' command."
  require_cmd awk "Install awk (required for .env.local parsing)."

  validate_directory_exists "${MIGRATIONS_DIR}"
  validate_migration_files
  validate_file_exists "${ENV_LOCAL}"
  sync_migrations_for_supabase_cli

  local supabase_url
  supabase_url="$(read_env_value "SUPABASE_URL" "${ENV_LOCAL}")"
  if [[ -z "${supabase_url}" || "${#supabase_url}" -gt 2048 ]]; then
    echo "[run-migrations.sh] ERROR: SUPABASE_URL missing or invalid length in ${ENV_LOCAL}." >&2
    exit 1
  fi

  local database_url
  database_url="$(read_env_value "DATABASE_URL" "${ENV_LOCAL}")"
  if [[ -z "${database_url}" || "${#database_url}" -gt 4096 ]]; then
    echo "[run-migrations.sh] ERROR: DATABASE_URL missing or invalid length in ${ENV_LOCAL}." >&2
    exit 1
  fi

  validate_url_format "SUPABASE_URL" "${supabase_url}" '^https?://[^[:space:]]+$'
  validate_url_format "DATABASE_URL" "${database_url}" '^(postgres|postgresql)://[^[:space:]]+$'

  echo "[run-migrations.sh] Applying migrations with supabase db push --local --yes..."
  (
    cd "${REPO_ROOT}"
    supabase db push --local --yes
  )

  echo "[run-migrations.sh] Migration apply complete. Current table row counts:"
  print_row_counts "${database_url}"
}

main "$@"
