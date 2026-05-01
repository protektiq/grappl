#!/usr/bin/env bash
# ==============================================================================
# GRAPPL — scripts/setup-minikube.sh
#
# Implements local Minikube bootstrap per docs/GRAPPL_Build_Plan_v1.0.md:
#   1) Verify minikube, kubectl, and docker are installed.
#   2) Start minikube (docker driver, 4 CPUs, 8192 MB RAM, 40000 MB disk, stable k8s)
#      using the dedicated 'grappl' profile — isolated from any other minikube
#      clusters on this machine.
#   3) Enable addons: ingress, metrics-server, dashboard, registry.
#   4) Print the in-cluster registry host:port for image pushes.
#   5) eval minikube docker-env in this process; remind user for new shells.
#   6) kubectl apply the grappl namespace manifest.
#   7) Print status summary (minikube status, nodes, enabled addons only).
#
# Idempotent: safe to run repeatedly; uses kubectl apply (not create).
#
# Profile isolation: GRAPPL runs as the 'grappl' minikube profile so it never
# interferes with other applications using the default 'minikube' profile.
# Switch between profiles with: minikube profile <name>
# ==============================================================================
set -euo pipefail

MINIKUBE_PROFILE="grappl"

# Resolve repo paths so the script works from any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE_MANIFEST="${REPO_ROOT}/infra/k8s/namespace.yaml"

# ------------------------------------------------------------------------------
# Step 1 — Prerequisites
# Fail fast with actionable messages if any required CLI is missing.
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

require_cmd minikube "Install: https://minikube.sigs.k8s.io/docs/start/"
require_cmd kubectl "Install: https://kubernetes.io/docs/tasks/tools/"
require_cmd docker "Install: https://docs.docker.com/get-docker/"

# ------------------------------------------------------------------------------
# Step 2 — Minikube cluster (dedicated 'grappl' profile)
# Using a named profile keeps GRAPPL's cluster isolated from other local apps.
# Resource flags (--cpus, --memory, --disk-size) are applied only on first
# creation; re-running this script on an existing profile is safe and idempotent.
# To change resources on an existing profile: minikube delete -p grappl, then
# re-run this script.
# ------------------------------------------------------------------------------
echo "Starting Minikube (profile: ${MINIKUBE_PROFILE}, driver: docker)..."
minikube start \
  --profile="${MINIKUBE_PROFILE}" \
  --driver=docker \
  --cpus=4 \
  --memory=8192 \
  --disk-size=40000mb \
  --kubernetes-version=stable

# ------------------------------------------------------------------------------
# Step 3 — Addons (ingress for HTTP routing, metrics-server for HPA/metrics,
# dashboard for optional UI).
# The registry addon is intentionally omitted: GRAPPL builds images directly
# into the cluster's Docker daemon via eval $(minikube docker-env -p grappl),
# so no registry push step is needed.
# ------------------------------------------------------------------------------
for addon in ingress metrics-server dashboard; do
  echo "Ensuring addon '${addon}' is enabled..."
  minikube addons enable "${addon}" --profile="${MINIKUBE_PROFILE}"
done

# ------------------------------------------------------------------------------
# Step 4 — Image build strategy note.
# ------------------------------------------------------------------------------
echo ""
echo "Image build strategy: eval \$(minikube docker-env -p ${MINIKUBE_PROFILE})"
echo "then: docker build -t grappl/<service>:local services/<service>/"
echo ""

# ------------------------------------------------------------------------------
# Step 5 — Docker client → Minikube's Docker daemon
# eval only affects this script's shell unless the user sources this file.
# ------------------------------------------------------------------------------
eval "$(minikube docker-env --profile="${MINIKUBE_PROFILE}")"

echo "------------------------------------------------------------------------"
echo "Docker in this script's shell now targets Minikube's Docker daemon."
echo "In any NEW terminal before docker build/push to Minikube, run:"
echo "  eval \$(minikube docker-env -p ${MINIKUBE_PROFILE})"
echo "------------------------------------------------------------------------"
echo ""

# ------------------------------------------------------------------------------
# Step 6 — Kubernetes namespace (declarative apply, not imperative create).
# ------------------------------------------------------------------------------
if [[ ! -f "${NAMESPACE_MANIFEST}" ]]; then
  echo "Error: namespace manifest not found: ${NAMESPACE_MANIFEST}" >&2
  exit 1
fi
echo "Applying namespace manifest..."
kubectl apply -f "${NAMESPACE_MANIFEST}" --context="${MINIKUBE_PROFILE}"

# ------------------------------------------------------------------------------
# Step 7 — Summary (grep filters addon list to enabled entries only).
# ------------------------------------------------------------------------------
echo ""
echo "==================== GRAPPL Minikube setup complete ===================="
echo ""
echo "--- minikube status (profile: ${MINIKUBE_PROFILE}) ---"
minikube status --profile="${MINIKUBE_PROFILE}" || true
echo ""
echo "--- kubectl get nodes ---"
kubectl get nodes --context="${MINIKUBE_PROFILE}"
echo ""
echo "--- enabled minikube addons ---"
minikube addons list --profile="${MINIKUBE_PROFILE}" | grep -E 'enabled|true' || true
echo ""
echo "To switch to this cluster in any terminal:"
echo "  minikube profile ${MINIKUBE_PROFILE}"
echo "  # or use the context directly:"
echo "  kubectl config use-context ${MINIKUBE_PROFILE}"
echo "======================================================================="
