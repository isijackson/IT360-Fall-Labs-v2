#!/usr/bin/env bash
# apply.sh <aws|azure|gcp> [extra -var flags]   init + apply, print the IP, wait for HTTP 200.
set -euo pipefail
C="${1:?usage: $0 <aws|azure|gcp> [-var ...]}"; shift; D=$(cd "$(dirname "$0")/.." && pwd)
T=$(command -v tofu || command -v terraform || { echo "install OpenTofu: curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method standalone"; exit 1; })
cd "$D/$C"; $T init -input=false >/dev/null; $T apply -auto-approve -input=false "$@"
IP=$($T output -raw public_ip); echo "PUBLIC_IP=$IP"
for i in $(seq 1 30); do curl -sf -m 5 "http://$IP/" && break; sleep 10; done
