#!/usr/bin/env bash
# Week 1 Lab 2 verification from the laptop: resources on each cloud, ping, idempotent playbook, both pages.
#   verify-lab2.sh [<GCP_PROJECT_ID>]      reads ~/lab2-state.env written by deploy-lab2.sh when present
set -uo pipefail
STATE="${STATE:-$HOME/lab2-state.env}"; [ -f "$STATE" ] && . "$STATE"
PROJECT="${1:-${PROJECT:-$(gcloud config get-value project 2>/dev/null)}}"; AZ_RG="${AZ_RG:-ansible-lab-rg}"; LOCAL_KEY="${LOCAL_KEY:-$HOME/.ssh/id_ed25519}"; CTX=${DO_CONTEXT:+--context $DO_CONTEXT}
echo "== DigitalOcean"; doctl compute droplet list $CTX --format Name,Region,PublicIPv4,Status --no-header | awk '$1=="ansible-controller"' || true
CIP="${CONTROLLER_IP:-$(doctl compute droplet list $CTX --format Name,PublicIPv4 --no-header | awk '$1=="ansible-controller"{print $2}')}"
echo "== GCP ($PROJECT)"; [ -n "$PROJECT" ] && gcloud compute instances list --project "$PROJECT" --filter="name=ansible-client-gcp" --format="table(name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)"
echo "== Azure ($AZ_RG)"; az vm show -d -g "$AZ_RG" -n ansible-client-azure --query "{vm:name,state:powerState,ip:publicIps,size:hardwareProfile.vmSize}" -o table 2>/dev/null || echo "no Azure client"
[ -n "$CIP" ] || { echo "no controller"; exit 1; }
C() { ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$LOCAL_KEY" "root@$CIP" "$@"; }
echo "== Controller $CIP: inventory"; C 'cat ~/lab2/inventory.ini'
echo "== ping"; C 'cd ~/lab2 && ansible -i inventory.ini all -m ping' | grep -E "SUCCESS|UNREACHABLE|FAILED"
echo "== idempotent run (expect changed=0 on every host; changed=1 on Update APT only if the apt cache is older than cache_valid_time, 3600 s)"; C 'cd ~/lab2 && ansible-playbook -i inventory.ini nginx-idempotent.yml' | grep -A3 "PLAY RECAP"
echo "== web pages"; for h in $(C "grep -oE '^[0-9.]+' ~/lab2/inventory.ini"); do echo "http://$h/ -> $(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$h/") $(curl -s -m 8 "http://$h/" | grep -o '<title>.*</title>')"; done
