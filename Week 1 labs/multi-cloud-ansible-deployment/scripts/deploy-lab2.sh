#!/usr/bin/env bash
# Week 1 Lab 2 end to end from one laptop: DigitalOcean controller, GCP client, Azure client, passwordless
# SSH, inventory, ping, NGINX playbook twice (second run must say changed=0), curl both pages.
# Needs: doctl (auth init), gcloud (auth login), az (login), an SSH key uploaded to DigitalOcean.
#   deploy-lab2.sh <GCP_PROJECT_ID>
#   env: DO_SSH_KEY_NAME (DigitalOcean key name, default it360-lab-mac)  LOCAL_KEY (its private key, default ~/.ssh/id_ed25519)
#        DO_CONTEXT DO_REGION (nyc1) DO_SIZE (s-1vcpu-1gb)  ZONE (us-central1-a)  AZ_RG (ansible-lab-rg) AZ_LOCATION (eastus) AZ_SIZE (Standard_B1s)
set -euo pipefail
PROJECT="${1:?usage: $0 <GCP_PROJECT_ID>}"; D=$(cd "$(dirname "$0")/.." && pwd)
DO_SSH_KEY_NAME="${DO_SSH_KEY_NAME:-it360-lab-mac}"; LOCAL_KEY="${LOCAL_KEY:-$HOME/.ssh/id_ed25519}"
CTX=${DO_CONTEXT:+--context $DO_CONTEXT}; DO_REGION="${DO_REGION:-nyc1}"; DO_SIZE="${DO_SIZE:-s-1vcpu-1gb}"
ZONE="${ZONE:-us-central1-a}"; AZ_RG="${AZ_RG:-ansible-lab-rg}"; AZ_LOCATION="${AZ_LOCATION:-eastus}"; AZ_SIZE="${AZ_SIZE:-Standard_B1s}"
STATE="${STATE:-$HOME/lab2-state.env}"
doctl account get $CTX >/dev/null || { echo "run: doctl auth init"; exit 1; }
gcloud auth print-access-token >/dev/null 2>&1 || { echo "run: gcloud auth login"; exit 1; }
az account show -o none 2>/dev/null || { echo "run: az login"; exit 1; }
KEY_ID=$(doctl compute ssh-key list $CTX --format ID,Name --no-header | awk -v n="$DO_SSH_KEY_NAME" '$2==n{print $1}')
[ -n "$KEY_ID" ] || { echo "DigitalOcean has no SSH key named $DO_SSH_KEY_NAME (doctl compute ssh-key import ...)"; exit 1; }
T0=$(date +%s)

echo "== Part 1: controller droplet on DigitalOcean ($DO_REGION, $DO_SIZE)"
CIP=$(doctl compute droplet list $CTX --format Name,PublicIPv4 --no-header | awk '$1=="ansible-controller"{print $2}')
if [ -z "$CIP" ]; then
  doctl compute droplet create ansible-controller $CTX --region "$DO_REGION" --size "$DO_SIZE" --image ubuntu-22-04-x64 --ssh-keys "$KEY_ID" --wait --format ID,Name,PublicIPv4,Status
fi
# --wait returns "active" a few seconds before the public IPv4 is assigned: poll for it
for i in $(seq 1 30); do
  CIP=$(doctl compute droplet list $CTX --format Name,PublicIPv4 --no-header | awk '$1=="ansible-controller"{print $2}')
  [ -n "$CIP" ] && break; sleep 5
done
[ -n "$CIP" ] || { echo "ansible-controller has no public IPv4 after 150 s"; exit 1; }
echo "CONTROLLER_IP=$CIP"
C() { ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$LOCAL_KEY" "root@$CIP" "$@"; }
for i in $(seq 1 30); do C true 2>/dev/null && break; sleep 10; done
C 'bash -s' < "$D/scripts/01-controller-bootstrap.sh" 2>&1 | grep -E "ansible \[|ssh-rsa" | sed 's/^/  /'
C 'cat ~/.ssh/id_rsa.pub' > /tmp/controller_id_rsa.pub
C 'mkdir -p ~/lab2 && printf "[defaults]\ninventory = inventory.ini\ninterpreter_python = auto_silent\nhost_key_checking = False\n" > ~/lab2/ansible.cfg'; scp -q -o StrictHostKeyChecking=no -i "$LOCAL_KEY" "$D/ansible/nginx.yml" "$D/ansible/nginx-idempotent.yml" "root@$CIP:~/lab2/"

echo "== Part 2a: GCP client in project $PROJECT"
gcloud config set project "$PROJECT" >/dev/null
gcloud compute instances describe ansible-client-gcp --zone "$ZONE" >/dev/null 2>&1 || gcloud compute instances create ansible-client-gcp \
  --zone="$ZONE" --machine-type=e2-micro --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud --tags=http-server,ansible-client --quiet >/dev/null
if ! gcloud compute firewall-rules describe default-allow-ssh >/dev/null 2>&1; then
  gcloud compute firewall-rules describe allow-ssh-ansible >/dev/null 2>&1 || gcloud compute firewall-rules create allow-ssh-ansible \
    --network=default --direction=INGRESS --action=ALLOW --rules=tcp:22 --source-ranges="$CIP/32" --target-tags=ansible-client --quiet >/dev/null
fi
gcloud compute firewall-rules describe default-allow-http >/dev/null 2>&1 || gcloud compute firewall-rules create default-allow-http \
  --network=default --direction=INGRESS --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=http-server --quiet >/dev/null
printf 'ubuntu:%s\n' "$(cat /tmp/controller_id_rsa.pub)" > /tmp/gcp-ssh-keys.txt
gcloud compute instances add-metadata ansible-client-gcp --zone "$ZONE" --metadata-from-file ssh-keys=/tmp/gcp-ssh-keys.txt >/dev/null
GIP=$(gcloud compute instances describe ansible-client-gcp --zone "$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
echo "GCP_CLIENT_IP=$GIP"

echo "== Part 2b: Azure client in $AZ_RG ($AZ_LOCATION, $AZ_SIZE; SSH only from the controller)"
az group create -n "$AZ_RG" -l "$AZ_LOCATION" -o none
if ! az vm show -g "$AZ_RG" -n ansible-client-azure -o none 2>/dev/null; then
  for SIZE in "$AZ_SIZE" Standard_B2s Standard_D2s_v4; do
    if az vm create -g "$AZ_RG" -n ansible-client-azure -l "$AZ_LOCATION" --image Ubuntu2204 --size "$SIZE" --admin-username ubuntu \
         --ssh-key-values /tmp/controller_id_rsa.pub --public-ip-sku Standard --nsg-rule NONE -o none 2>/tmp/azvm.err; then echo "  size $SIZE"; break; fi
    echo "  $SIZE failed: $(grep -oE 'SkuNotAvailable|QuotaExceeded|[A-Za-z]+Error' /tmp/azvm.err | sort -u | tr '\n' ' ')"
  done
fi
az network nsg rule create -g "$AZ_RG" --nsg-name ansible-client-azureNSG -n allow-ssh-from-controller --priority 1000 --protocol Tcp \
  --source-address-prefixes "$CIP/32" --destination-port-ranges 22 --access Allow -o none
az network nsg rule create -g "$AZ_RG" --nsg-name ansible-client-azureNSG -n allow-http --priority 1010 --protocol Tcp --destination-port-ranges 80 --access Allow -o none
AIP=$(az vm show -d -g "$AZ_RG" -n ansible-client-azure --query publicIps -o tsv)
echo "AZURE_CLIENT_IP=$AIP"
printf 'CONTROLLER_IP=%s\nGCP_CLIENT_IP=%s\nAZURE_CLIENT_IP=%s\nPROJECT=%s\nAZ_RG=%s\n' "$CIP" "$GIP" "$AIP" "$PROJECT" "$AZ_RG" > "$STATE"

echo "== Part 3: passwordless SSH from the controller"
for h in "$GIP" "$AIP"; do for i in $(seq 1 18); do C "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 ubuntu@$h hostname" 2>/dev/null && break; sleep 10; done; done

echo "== Parts 4-5: inventory, ping, playbook twice, curl"
# the inventory documented in the README and the handout (ansible/inventory.example.ini with the IPs substituted)
C "cd ~/lab2 && printf '[azure]\n$AIP ansible_user=ubuntu\n\n[gcp]\n$GIP ansible_user=ubuntu\n\n[all:vars]\nansible_ssh_private_key_file=~/.ssh/id_rsa\nansible_ssh_common_args=-o StrictHostKeyChecking=accept-new\n' > inventory.ini && cat inventory.ini"
C 'cd ~/lab2 && ansible -i inventory.ini all -m ping' | grep -E "SUCCESS|UNREACHABLE|FAILED|pong"
C 'cd ~/lab2 && ansible-playbook -i inventory.ini nginx.yml' | grep -A3 "PLAY RECAP"
C 'cd ~/lab2 && ansible-playbook -i inventory.ini nginx-idempotent.yml' | grep -A3 "PLAY RECAP"
for h in "$GIP" "$AIP"; do echo "http://$h/ -> $(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$h/") $(curl -s -m 8 "http://$h/" | grep -o '<title>.*</title>')"; done
echo; echo "Done in $(( ($(date +%s)-T0)/60 )) minutes. Controller: ssh -i $LOCAL_KEY root@$CIP   state: $STATE"
echo "LAB2_DEPLOY_DONE"
