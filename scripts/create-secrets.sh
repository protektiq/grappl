#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly ENV_FILE=".env.local"
readonly NAMESPACE="grappl"
readonly SECRET_NAME="grappl-secrets"
readonly MAX_VALUE_LENGTH=8192
readonly REQUIRED_KEYS=(
  "ROBOFLOW_API_KEY"
  "ANTHROPIC_API_KEY"
  "SUPABASE_URL"
  "SUPABASE_SERVICE_ROLE_KEY"
  "DATABASE_URL"
)

log_error() {
  echo "[$SCRIPT_NAME] ERROR: $1" >&2
}

validate_file_state() {
  if [[ ! -f "$ENV_FILE" ]]; then
    log_error "Missing required file: $ENV_FILE"
    exit 1
  fi

  if [[ ! -s "$ENV_FILE" ]]; then
    log_error "File exists but is empty: $ENV_FILE"
    exit 1
  fi
}

validate_dependencies() {
  if ! command -v kubectl >/dev/null 2>&1; then
    log_error "kubectl is required but was not found in PATH"
    exit 1
  fi
}

validate_namespace() {
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Namespace '$NAMESPACE' does not exist. Create it first."
    exit 1
  fi
}

get_env_value() {
  local key="$1"
  local line
  line="$(awk -F= -v key="$key" '$1 == key {print substr($0, index($0, "=") + 1)}' "$ENV_FILE" | sed -n '$p')"
  if [[ -z "$line" ]]; then
    echo ""
    return 0
  fi

  echo "${line#*=}"
}

validate_key_name() {
  local key="$1"
  if [[ ! "$key" =~ ^[A-Z0-9_]{3,64}$ ]]; then
    log_error "Invalid key name format: $key"
    exit 1
  fi
}

validate_required_values() {
  local key
  local value

  for key in "${REQUIRED_KEYS[@]}"; do
    validate_key_name "$key"
    value="$(get_env_value "$key")"

    if [[ -z "$value" ]]; then
      log_error "Required key '$key' is missing or empty in $ENV_FILE"
      exit 1
    fi

    if (( ${#value} > MAX_VALUE_LENGTH )); then
      log_error "Value for '$key' exceeds ${MAX_VALUE_LENGTH} characters"
      exit 1
    fi

    if [[ "$value" =~ [[:cntrl:]] ]]; then
      log_error "Value for '$key' contains control characters"
      exit 1
    fi
  done
}

validate_required_formats() {
  local supabase_url
  local database_url

  supabase_url="$(get_env_value "SUPABASE_URL")"
  database_url="$(get_env_value "DATABASE_URL")"

  if [[ ! "$supabase_url" =~ ^https?://[^[:space:]]+$ ]]; then
    log_error "SUPABASE_URL must be an http(s) URL"
    exit 1
  fi

  if [[ "$supabase_url" =~ ^http:// ]] && [[ ! "$supabase_url" =~ ^http://(localhost|127\.0\.0\.1|0\.0\.0\.0)(:[0-9]{1,5})?(/|$) ]]; then
    log_error "SUPABASE_URL over http:// is only allowed for local development endpoints"
    exit 1
  fi

  if [[ ! "$database_url" =~ ^postgres(ql)?://[^[:space:]]+$ ]]; then
    log_error "DATABASE_URL must be a postgres:// or postgresql:// URL"
    exit 1
  fi
}

apply_secret() {
  kubectl create secret generic "$SECRET_NAME" \
    --from-env-file="$ENV_FILE" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
}

main() {
  validate_file_state
  validate_dependencies
  validate_namespace
  validate_required_values
  validate_required_formats
  apply_secret
  echo "[$SCRIPT_NAME] Secret '$SECRET_NAME' applied in namespace '$NAMESPACE'."
}

main "$@"
