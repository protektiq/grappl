#!/usr/bin/env bash

set -euo pipefail

readonly NAMESPACE="grappl"
readonly K8S_DIR="infra/k8s"

validate_dependency() {
  local dependency="$1"
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "[deploy.sh] ERROR: $dependency is required but was not found in PATH." >&2
    exit 1
  fi
}

validate_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "[deploy.sh] ERROR: required manifest not found: $file_path" >&2
    exit 1
  fi
}

apply_namespaced_file() {
  local file_path="$1"
  validate_file "$file_path"
  echo "[deploy.sh] Applying $file_path in namespace $NAMESPACE"
  kubectl apply --namespace="$NAMESPACE" -f "$file_path"
}

apply_namespace_file() {
  local file_path="$1"
  validate_file "$file_path"
  echo "[deploy.sh] Applying $file_path"
  kubectl apply -f "$file_path"
}

apply_directory_files() {
  local directory_path="$1"
  if [[ ! -d "$directory_path" ]]; then
    echo "[deploy.sh] ERROR: required directory not found: $directory_path" >&2
    exit 1
  fi

  local manifests=()
  mapfile -t manifests < <(printf '%s\n' "$directory_path"/*.yaml 2>/dev/null | sort)

  if [[ "${#manifests[@]}" -eq 0 ]]; then
    echo "[deploy.sh] WARNING: no manifests found in $directory_path"
    return 0
  fi

  local manifest
  for manifest in "${manifests[@]}"; do
    if [[ -f "$manifest" ]]; then
      apply_namespaced_file "$manifest"
    fi
  done
}

list_deployment_manifests() {
  local deployments_path="$1"
  local manifests=()
  mapfile -t manifests < <(printf '%s\n' "$deployments_path"/*.yaml 2>/dev/null | sort)

  local manifest
  for manifest in "${manifests[@]}"; do
    if [[ -f "$manifest" ]]; then
      echo "$manifest"
    fi
  done
}

extract_deployment_name() {
  local deployment_file="$1"
  local deployment_name
  deployment_name="$(awk '/^metadata:/{in_metadata=1; next} in_metadata && /^  name: /{print $2; exit}' "$deployment_file")"
  if [[ -z "$deployment_name" ]]; then
    echo "[deploy.sh] ERROR: unable to parse deployment name from $deployment_file" >&2
    exit 1
  fi

  if [[ ! "$deployment_name" =~ ^[a-z0-9]([-.a-z0-9]*[a-z0-9])?$ ]]; then
    echo "[deploy.sh] ERROR: deployment name has invalid format: $deployment_name" >&2
    exit 1
  fi

  echo "$deployment_name"
}

print_rollout_statuses() {
  local deployments_path="$K8S_DIR/deployments"
  if [[ ! -d "$deployments_path" ]]; then
    echo "[deploy.sh] ERROR: deployments directory not found: $deployments_path" >&2
    exit 1
  fi

  local deployment_files=()
  mapfile -t deployment_files < <(list_deployment_manifests "$deployments_path")

  if [[ "${#deployment_files[@]}" -eq 0 ]]; then
    echo "[deploy.sh] WARNING: no deployment manifests found in $deployments_path"
    return 0
  fi

  local deployment_file
  for deployment_file in "${deployment_files[@]}"; do
    local deployment_name
    deployment_name="$(extract_deployment_name "$deployment_file")"
    echo "[deploy.sh] Waiting for deployment/$deployment_name rollout..."
    kubectl rollout status "deployment/$deployment_name" --namespace="$NAMESPACE"
  done
}

main() {
  validate_dependency kubectl
  validate_dependency sort

  apply_namespace_file "$K8S_DIR/namespace.yaml"
  apply_namespaced_file "$K8S_DIR/pvc.yaml"
  apply_namespaced_file "$K8S_DIR/configmap.yaml"
  apply_directory_files "$K8S_DIR/secrets"
  apply_directory_files "$K8S_DIR/deployments"
  apply_namespaced_file "$K8S_DIR/ingress.yaml"

  print_rollout_statuses
  echo "[deploy.sh] Deployment apply complete."
}

main "$@"
