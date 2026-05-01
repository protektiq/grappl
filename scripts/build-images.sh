#!/usr/bin/env bash

set -euo pipefail

for cmd in minikube docker; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: required command '${cmd}' is not installed or not in PATH."
    exit 1
  fi
done

eval "$(minikube docker-env -p grappl)"

declare -a services=("ingest" "inference" "clip" "analysis" "gateway" "ui")
declare -A dockerfiles=(
  ["ingest"]="services/ingest/Dockerfile"
  ["inference"]="services/inference/Dockerfile"
  ["clip"]="services/clip/Dockerfile"
  ["analysis"]="services/analysis/Dockerfile"
  ["gateway"]="services/gateway/Dockerfile"
  ["ui"]="ui/Dockerfile"
)

build_failed=0

for service in "${services[@]}"; do
  image_tag="grappl/${service}:local"
  dockerfile_path="${dockerfiles[$service]}"

  echo "Building ${image_tag}..."
  if docker build -f "${dockerfile_path}" -t "${image_tag}" .; then
    echo "SUCCESS: ${image_tag}"
  else
    echo "FAILED: ${image_tag}"
    build_failed=1
  fi
done

if [[ "${build_failed}" -ne 0 ]]; then
  echo "One or more image builds failed."
  exit 1
fi

echo "All image builds completed successfully."
