#!/usr/bin/env bash
# Steps 6-8: run ON THE EC2 INSTANCE (SSH session), after 02-aws-attach-scratch-volume.sh.
# Step 6 makes the OS cloud-neutral (cloud-init datasource GCE first, netplan for any NIC, no boot-time
# fsck, cloud-init clean, migrated-from.txt marker). Steps 7-8 format and mount the 10 GB scratch volume,
# take a frozen raw copy of the root device, check that its superblock matches the live root, e2fsck the
# copy, compress it to qcow2 and publish it at http://<EC2_PUBLIC_IP>/disk.qcow2 for the download.
# The same commands as 00-aws-all-in-one.sh; devices are found with lsblk/findmnt, so t2 (xvda/xvdf) and
# t3 (nvme0n1/nvme1n1) both work.
set -euo pipefail

echo "== Step 6: prepare the OS for Google Cloud (cloud-init datasource, netplan, fstab)"
printf "datasource_list: [ GCE, Ec2, None ]\n" | sudo tee /etc/cloud/cloud.cfg.d/99-multicloud.cfg >/dev/null
printf "network:\n  version: 2\n  ethernets:\n    any:\n      match:\n        name: \"e*\"\n      dhcp4: true\n" | sudo tee /etc/netplan/60-any-nic.yaml >/dev/null
sudo chmod 600 /etc/netplan/60-any-nic.yaml
sudo sed -i -E 's/(\s)0 1\s*$/\10 0/' /etc/fstab        # no fsck at boot: the capture is crash-consistent, the journal replays
sudo cloud-init clean --logs >/dev/null 2>&1 || true   # next boot (on GCE) is a fresh instance: new host keys, network, metadata
printf "migrated-from: AWS instance %s (%s) captured %s\n" "$(hostname)" "$(curl -s -4 --max-time 5 https://api.ipify.org)" "$(date -u +%Y-%m-%dT%H:%MZ)" | sudo tee /var/www/html/migrated-from.txt >/dev/null
echo "PREP_DONE: $(grep -c "0 0" /etc/fstab) fstab entries without fsck, netplan 60-any-nic.yaml, datasource GCE first"

echo "== Steps 7-8: capture the root volume (scratch volume = the 10 GB disk)"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-utils >/dev/null
DEV=$(lsblk -dno NAME,SIZE | awk '$2=="10G"{print "/dev/"$1; exit}')
[ -n "$DEV" ] || { echo "No 10G scratch disk found (lsblk). Run 02-aws-attach-scratch-volume.sh first."; exit 1; }
sudo mkdir -p /mnt/img
mountpoint -q /mnt/img || { sudo mkfs.ext4 -q -F "$DEV"; sudo mount "$DEV" /mnt/img; }
sudo rm -f /mnt/img/disk.raw /mnt/img/disk.qcow2
ROOT=/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)"); PART=$(findmnt -no SOURCE /)
echo "CONVERT_START root=$ROOT rootfs=$PART scratch=$DEV (3 to 5 minutes; writes to / pause during the copy)"
# 1. raw copy of the OS disk with the root filesystem frozen. "-T none" reads the disk with O_DIRECT: the
#    whole-disk device has its own page cache, which can still hold the superblock from before the first-boot
#    online resize; a copy made through that stale cache carries the old superblock and e2fsck then destroys
#    it (seen 2026-10-27). Dropping the caches first and bypassing them makes it exact.
sudo sh -c "sync; echo 3 > /proc/sys/vm/drop_caches; blockdev --flushbufs $ROOT; fsfreeze -f /; qemu-img convert -T none -O raw $ROOT /mnt/img/disk.raw; rc=\$?; fsfreeze -u /; exit \$rc"
LIVE=$(sudo dumpe2fs -h "$PART" 2>/dev/null | awk '/^Block count/{print $3}' || true)
LOOP=$(sudo losetup -fP --show /mnt/img/disk.raw); N=$(echo "$PART" | grep -o "[0-9]*$")
COPY=$(sudo dumpe2fs -h "${LOOP}p${N}" 2>/dev/null | awk '/^Block count/{print $3}' || true)
echo "superblock block count: live=$LIVE copy=$COPY"
if [ -z "$LIVE" ] || [ "$LIVE" != "$COPY" ]; then
  echo "CAPTURE_STALE: the copy has a different superblock than the live root; not repairing it. Rerun this script."
  sudo losetup -d "$LOOP"; exit 1
fi
# 2. check the copy (the journal replays; this also clears the "Resize inode not valid" that some copies report)
sudo e2fsck -fy "${LOOP}p${N}" >/tmp/e2fsck.log 2>&1 || true
grep -E "Resize inode|FILE SYSTEM WAS MODIFIED|clean|blocks" /tmp/e2fsck.log | tail -3; sudo losetup -d "$LOOP"
# 3. compress for the transfer, then publish over the web server (Step 8)
sudo qemu-img convert -c -O qcow2 /mnt/img/disk.raw /mnt/img/disk.qcow2 && sudo rm -f /mnt/img/disk.raw
sudo chmod 644 /mnt/img/disk.qcow2; sudo ln -sf /mnt/img/disk.qcow2 /var/www/html/disk.qcow2
ls -lh /mnt/img/disk.qcow2
md5sum /mnt/img/disk.qcow2                              # Checkpoint 2: write this down
echo "CONVERT_DONE"
echo "Image published at http://$(curl -s -4 --max-time 5 https://checkip.amazonaws.com)/disk.qcow2  (remove with: sudo rm /var/www/html/disk.qcow2)"
