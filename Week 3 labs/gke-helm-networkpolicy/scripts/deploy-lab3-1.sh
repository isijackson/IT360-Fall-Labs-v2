#!/usr/bin/env bash
# Week 3 Lab 3.2 deploy: GKE Autopilot cluster, NGINX by kubectl, the same app as a Helm release with
# upgrade and rollback, then a NetworkPolicy proven with a blocked and an allowed probe.
#   deploy-lab3-1.sh <PROJECT_ID>        (REGION, CLUSTER env vars optional)
set -uo pipefail
PROJECT="${1:?usage: $0 <PROJECT_ID>}"; REGION="${REGION:-us-central1}"; CLUSTER="${CLUSTER:-silverlake-public}"
D=$(cd "$(dirname "$0")/.." && pwd); W=$(mktemp -d)
g() { gcloud "$@" --project="$PROJECT" --quiet; }
echo "== Part 1: cluster $CLUSTER ($REGION, Autopilot)"
g container clusters describe "$CLUSTER" --region="$REGION" --format="value(status)" 2>/dev/null | grep -q RUNNING || \
  g container clusters create-auto "$CLUSTER" --region="$REGION"
g container clusters get-credentials "$CLUSTER" --region="$REGION"
kubectl get nodes 2>/dev/null || echo "(Autopilot shows no nodes until a workload is scheduled)"
echo "== Part 2: deploy with kubectl"
kubectl apply -f "$D/k8s/nginx-deployment.yaml"
kubectl rollout status deployment/loan-calc --timeout=300s
kubectl get deployments; kubectl get pods -l app=loan-calc
P=$(kubectl get pods -l app=loan-calc -o jsonpath='{.items[0].metadata.name}')
echo "-- checkpoint: delete pod $P by hand"; kubectl delete pod "$P" --wait=false >/dev/null; sleep 8; kubectl get pods -l app=loan-calc
echo "== Part 3: Helm release"
helm version --short
cd "$W" && helm create loan-calc-chart >/dev/null
sed -i.bak 's/^replicaCount: .*/replicaCount: 2/' loan-calc-chart/values.yaml
sed -i.bak 's/^  tag: .*/  tag: "1.27"/' loan-calc-chart/values.yaml
# a rerun starts the release over, so helm history reads revisions 1, 2 and 3 as Validation 3 expects
helm status loan-calc >/dev/null 2>&1 && { echo "-- existing release loan-calc: uninstalling it first"; helm uninstall loan-calc --wait >/dev/null; }
helm install loan-calc ./loan-calc-chart >/dev/null
helm list
sed -i.bak 's/^replicaCount: .*/replicaCount: 3/' loan-calc-chart/values.yaml
helm upgrade loan-calc ./loan-calc-chart >/dev/null
helm rollback loan-calc 1 >/dev/null
helm history loan-calc
kubectl rollout status deployment/loan-calc-loan-calc-chart --timeout=300s
echo "== Part 4: NetworkPolicy with proof"
kubectl apply -f "$D/k8s/network-policy.yaml"; kubectl get networkpolicy
SVC=$(kubectl get svc -l app.kubernetes.io/instance=loan-calc -o jsonpath='{.items[0].metadata.name}')
echo "-- probe WITHOUT role=frontend (must time out)"
kubectl run probe --rm -i --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=5 "http://$SVC" 2>&1 | tail -3
echo "-- probe WITH role=frontend (must print nginx HTML)"
kubectl run probe-ok --rm -i --image=busybox:1.36 --restart=Never --labels=role=frontend -- wget -qO- --timeout=5 "http://$SVC" 2>&1 | grep -o '<title>.*</title>'
echo "LAB3_1_DEPLOY_DONE"
