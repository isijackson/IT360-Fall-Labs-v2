#!/usr/bin/env bash
# Week 1 Lab 1 (Azure variant), Azure side, steps 1-8 in one run. Run on a laptop where `az login` is done
# or in the portal's Cloud Shell (Bash). Creates a resource group (or uses RG if set, as on the Vocareum
# sandbox), an Ubuntu 22.04 VM (SSH open only to the machine running this script, HTTP open to all),
# installs Apache, attaches a 10 GB scratch disk, captures the OS disk as a compressed qcow2 and
# publishes it at http://<PUBLIC_IP>/disk.qcow2.
#   bash 00-azure-all-in-one.sh                              (own subscription: creates apacheserver1-rg)
#   RG=<existing group> bash 00-azure-all-in-one.sh          (Vocareum sandbox: use its pre-created group)
#   LOCATION, SIZE, NAME env vars optional (defaults eastus, Standard_D2s_v4, apacheserver1)
set -euo pipefail
NAME="${NAME:-apacheserver1}"; LOCATION="${LOCATION:-eastus}"; SIZE="${SIZE:-Standard_D2s_v4}"
mkdir -p ~/.ssh; chmod 700 ~/.ssh; KEY="$HOME/.ssh/${NAME}-key"
[ -f "$KEY" ] || ssh-keygen -t rsa -b 2048 -N "" -f "$KEY" -q
if [ -z "${RG:-}" ]; then RG="${NAME}-rg"; az group show -n "$RG" -o none 2>/dev/null || az group create -n "$RG" -l "$LOCATION" -o none; fi
MY_IP=$(curl -s -4 --max-time 10 https://api.ipify.org || curl -s -4 --max-time 10 https://ifconfig.me)
echo "RG=$RG LOCATION=$LOCATION SIZE=$SIZE ADMIN_IP=$MY_IP"; echo "T_START=$(date +%s)"   # T_ lines feed the step-timing table in deploy-lab1.sh
echo "== Steps 1-2: VM with SSH open to this machine and HTTP open to everyone"
az vm show -g "$RG" -n "$NAME" -o none 2>/dev/null || az vm create -g "$RG" -n "$NAME" -l "$LOCATION" --image Ubuntu2204 --size "$SIZE" \
  --admin-username ubuntu --ssh-key-values "$KEY.pub" --public-ip-sku Standard --nsg-rule NONE -o none
az network nsg rule create -g "$RG" --nsg-name "${NAME}NSG" -n allow-ssh-admin --priority 1000 --protocol Tcp \
  --source-address-prefixes "$MY_IP/32" --destination-port-ranges 22 --access Allow -o none
az network nsg rule create -g "$RG" --nsg-name "${NAME}NSG" -n allow-http --priority 1010 --protocol Tcp \
  --destination-port-ranges 80 --access Allow -o none
IP=$(az vm show -d -g "$RG" -n "$NAME" --query publicIps -o tsv); echo "VM=$NAME IP=$IP"; echo "T_VM_READY=$(date +%s)"
echo "== Step 5: 10 GB scratch disk at LUN 0"
az vm disk attach -g "$RG" --vm-name "$NAME" --name "${NAME}-scratch" --new --size-gb 10 --sku Standard_LRS --lun 0 -o none 2>/dev/null || echo "scratch disk already attached"
echo "== Steps 3-4: Apache"
S="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $KEY ubuntu@$IP"
for i in $(seq 1 30); do
  $S true 2>/dev/null && break; sleep 10
  # Laptops on carrier NAT or VPNs change public IP mid-run; refresh the admin rule if that happened.
  NOW_IP=$(curl -s -4 --max-time 10 https://api.ipify.org || curl -s -4 --max-time 10 https://ifconfig.me)
  if [ -n "$NOW_IP" ] && [ "$NOW_IP" != "$MY_IP" ]; then
    echo "public IP changed $MY_IP -> $NOW_IP; updating allow-ssh-admin"; MY_IP=$NOW_IP
    az network nsg rule update -g "$RG" --nsg-name "${NAME}NSG" -n allow-ssh-admin --source-address-prefixes "$MY_IP/32" -o none
  fi
done
$S 'sudo apt-get update -qq >/dev/null; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2 >/dev/null;
    sudo systemctl enable apache2 >/dev/null 2>&1; sudo systemctl start apache2; echo "APACHE=$(systemctl is-active apache2)"; hostname; lsb_release -ds'
echo "HTTP=$(curl -s -o /dev/null -w '%{http_code}' http://$IP/)"; curl -s "http://$IP/" | grep -o '<title>.*</title>'; echo "T_APACHE_OK=$(date +%s)"
echo "== Step 6 on the VM: prepare the OS for Google Cloud (cloud-init datasource, netplan, fstab, agent)"
# An Azure Ubuntu image boots on GCE but (1) cloud-init waits forever for the Azure metadata service,
# (2) netplan pins eth0 to the Azure NIC's MAC, (3) the boot-time fsck fails on a copied root (see the capture
# step). These edits make the captured disk cloud-neutral.
$S 'set -e
    printf "datasource_list: [ GCE, Azure, None ]\n" | sudo tee /etc/cloud/cloud.cfg.d/99-multicloud.cfg >/dev/null
    printf "network:\n  version: 2\n  ethernets:\n    any:\n      match:\n        name: \"e*\"\n      dhcp4: true\n" | sudo tee /etc/netplan/60-any-nic.yaml >/dev/null
    sudo chmod 600 /etc/netplan/60-any-nic.yaml
    sudo sed -i -E "s/(\s)0 1\s*$/\10 0/" /etc/fstab        # no fsck at boot: the capture is crash-consistent, the journal replays
    sudo systemctl disable walinuxagent.service >/dev/null 2>&1 || true
    sudo cloud-init clean --logs >/dev/null 2>&1 || true   # next boot (on GCE) is a fresh instance: new host keys, network, metadata
    printf "migrated-from: Azure VM %s (%s) captured %s\n" "$(hostname)" "$(curl -s -4 --max-time 5 https://api.ipify.org)" "$(date -u +%Y-%m-%dT%H:%MZ)" | sudo tee /var/www/html/migrated-from.txt >/dev/null
    echo "PREP_DONE: $(grep -c "0 0" /etc/fstab) fstab entries without fsck, netplan 60-any-nic.yaml, datasource GCE first"'
echo "T_PREP_DONE=$(date +%s)"
echo "== Steps 7-8 on the VM: capture the OS disk (the scratch disk is LUN 0: /dev/disk/azure/scsi1/lun0)"
$S 'set -e; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-utils >/dev/null
    DEV=$(readlink -f /dev/disk/azure/scsi1/lun0); sudo mkdir -p /mnt/img
    mountpoint -q /mnt/img || { sudo mkfs.ext4 -q -F "$DEV"; sudo mount "$DEV" /mnt/img; }; sudo rm -f /mnt/img/disk.raw /mnt/img/disk.qcow2
    ROOT=$(readlink -f /dev/disk/azure/root); echo "CONVERT_START root=$ROOT scratch=$DEV"
    # 1. raw copy of the OS disk with the root filesystem frozen. "-T none" reads the disk with O_DIRECT: the
    #    whole-disk device has its own page cache, which can still hold the superblock from before the first-boot
    #    online resize; a copy made through that stale cache carries a 2 GB superblock on a 30 GB filesystem and
    #    e2fsck then destroys it (seen 2026-10-27). Dropping the caches first and bypassing them makes it exact.
    sudo sh -c "sync; echo 3 > /proc/sys/vm/drop_caches; blockdev --flushbufs $ROOT; fsfreeze -f /; qemu-img convert -T none -O raw $ROOT /mnt/img/disk.raw; rc=\$?; fsfreeze -u /; exit \$rc"
    PART=$(readlink -f /dev/disk/azure/root-part1); LIVE=$(sudo dumpe2fs -h "$PART" 2>/dev/null | awk "/^Block count/{print \$3}")
    LOOP=$(sudo losetup -fP --show /mnt/img/disk.raw); N=1; COPY=$(sudo dumpe2fs -h "${LOOP}p${N}" 2>/dev/null | awk "/^Block count/{print \$3}")
    echo "superblock block count: live=$LIVE copy=$COPY"
    [ -n "$LIVE" ] && [ "$LIVE" = "$COPY" ] || { echo "CAPTURE_STALE: the copy has a different superblock than the live root; not repairing it. Rerun the capture."; sudo losetup -d "$LOOP"; exit 1; }
    # 2. check the copy (the journal replays; this also clears the "Resize inode not valid" that some copies report)
    sudo e2fsck -fy "${LOOP}p${N}" >/tmp/e2fsck.log 2>&1 || true
    grep -E "Resize inode|FILE SYSTEM WAS MODIFIED|clean|blocks" /tmp/e2fsck.log | tail -3; sudo losetup -d "$LOOP"
    # 3. compress for the transfer
    sudo qemu-img convert -c -O qcow2 /mnt/img/disk.raw /mnt/img/disk.qcow2 && sudo rm -f /mnt/img/disk.raw
    sudo chmod 644 /mnt/img/disk.qcow2; sudo ln -sf /mnt/img/disk.qcow2 /var/www/html/disk.qcow2
    ls -l /mnt/img/disk.qcow2; md5sum /mnt/img/disk.qcow2; echo CONVERT_DONE'
echo "T_CAPTURE_DONE=$(date +%s)"
echo "IMAGE_URL=http://$IP/disk.qcow2"; echo "AZURE_BUILD_DONE"
