#!/usr/bin/env bash

set -euo pipefail

readonly PROFILE="grappl"
readonly HOSTNAME="grappl.local"

if ! command -v minikube >/dev/null 2>&1; then
  echo "[add-hosts.sh] ERROR: minikube is required but was not found in PATH." >&2
  exit 1
fi

ip="$(minikube ip -p "$PROFILE" 2>/dev/null || true)"
if [[ -z "$ip" ]]; then
  echo "[add-hosts.sh] ERROR: could not resolve Minikube IP for profile '$PROFILE'." >&2
  exit 1
fi

if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "[add-hosts.sh] ERROR: minikube returned an invalid IPv4 address: '$ip'." >&2
  exit 1
fi

echo "Add this entry to /etc/hosts:"
echo "$ip  $HOSTNAME"
