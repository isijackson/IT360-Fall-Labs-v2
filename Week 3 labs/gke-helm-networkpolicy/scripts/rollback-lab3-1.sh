#!/usr/bin/env bash
# Week 3 Lab 3.2 rollback: Helm release, policy, deployment, then the cluster.
#   rollback-lab3-1.sh <PROJECT_ID> [-n] [-y] [--keep-cluster]
set -uo pipefail
PROJECT="${1:?usage: $0 <PROJECT_ID> [-n] [-y] [--keep-cluster]}"; shift; DRY=0; YES=0; KEEP=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; --keep-cluster) KEEP=1;; *) echo "usage: $0 <PROJECT_ID> [-n] [-y] [--keep-cluster]"; exit 2;; esac; done
REGION="${REGION:-us-central1}"; CLUSTER="${CLUSTER:-silverlake-public}"
g() { gcloud "$@" --project="$PROJECT" --quiet 2>/dev/null; }
C=$(g container clusters list --filter="name=$CLUSTER" --format="value(name,location)")
echo "Lab 3.2 resources in $PROJECT:"; printf '  cluster (name location): %s\n' "${C:-none}"
[ -z "$C" ] && { echo "Nothing to delete."; exit 0; }
g container clusters get-credentials "$CLUSTER" --region="$REGION" >/dev/null 2>&1 && {
  printf '  helm releases: %s\n  policies: %s\n  deployments: %s\n' "$(helm list -q | tr '\n' ' ')" "$(kubectl get networkpolicy -o name | tr '\n' ' ')" "$(kubectl get deploy -o name | tr '\n' ' ')"; }
[ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi
helm uninstall loan-calc 2>/dev/null && echo "helm release removed"
kubectl delete networkpolicy loan-calc-frontend-only --ignore-not-found; kubectl delete deployment loan-calc --ignore-not-found; kubectl delete svc loan-calc-public --ignore-not-found
if [ "$KEEP" = 1 ]; then echo "cluster kept"; else g container clusters delete "$CLUSTER" --region="$REGION" && echo "deleted cluster $CLUSTER"; fi
echo "Remaining lab clusters: $(g container clusters list --filter="name=$CLUSTER" --format="value(name)" | grep -c .)"
echo "LAB3_1_ROLLBACK_DONE"
