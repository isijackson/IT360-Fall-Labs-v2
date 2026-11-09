#!/usr/bin/env bash
# destroy.sh <aws|azure|gcp> [extra -var flags]
set -euo pipefail
C="${1:?usage: $0 <aws|azure|gcp> [-var ...]}"; shift; D=$(cd "$(dirname "$0")/.." && pwd)
T=$(command -v tofu || command -v terraform); cd "$D/$C"; $T destroy -auto-approve -input=false "$@"; echo "DESTROYED $C"
