#!/usr/bin/env bash
# Week 1 Lab 1 (AWS variant), AWS side, steps 1-8 in one run. Run in AWS CloudShell or on a laptop where
# the AWS CLI has credentials (AWS_PROFILE / AWS_DEFAULT_REGION). CloudShell sets AWS_REGION to its own
# region, so from a CloudShell outside Ohio run `export AWS_DEFAULT_REGION=us-east-2` first. Creates a key pair, a
# security group (SSH only from the machine running this script, HTTP open to all), an Ubuntu 22.04
# instance, installs Apache, attaches a 10 GB scratch volume, prepares the OS for Google Cloud, captures
# the root volume as a compressed qcow2 and publishes it at http://<PUBLIC_IP>/disk.qcow2.
#   bash 00-aws-all-in-one.sh                 env: NAME (apacheserver1) TYPE (t3.micro) AWS_DEFAULT_REGION
#   (default: AWS_REGION if set, as in CloudShell, else us-east-2)
set -euo pipefail
NAME="${NAME:-apacheserver1}"; TYPE="${TYPE:-t3.micro}"; KEY_NAME="${NAME}-key"; KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-2}}"; export AWS_PAGER=""
mkdir -p ~/.ssh; chmod 700 ~/.ssh
MY_IP=$(curl -s -4 --max-time 10 https://api.ipify.org || curl -s -4 --max-time 10 https://ifconfig.me)
echo "ACCOUNT=$(aws sts get-caller-identity --query Account --output text) REGION=$AWS_DEFAULT_REGION TYPE=$TYPE ADMIN_IP=$MY_IP"; echo "T_START=$(date +%s)"   # T_ lines feed the step-timing table in deploy-lab1.sh
echo "== Steps 1-2: key pair, security group (22 from this machine, 80 from everyone), instance"
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  rm -f "$KEY_FILE"; aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type rsa --key-format pem --query KeyMaterial --output text > "$KEY_FILE"
fi
[ -s "$KEY_FILE" ] || { echo "key pair $KEY_NAME exists in AWS but $KEY_FILE is missing: delete the key pair and rerun"; exit 1; }
chmod 400 "$KEY_FILE"; echo "KEYPAIR=$KEY_NAME"
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${NAME}-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ "$SG" = "None" ] || [ -z "$SG" ]; then
  SG=$(aws ec2 create-security-group --group-name "${NAME}-sg" --description "SSH from admin and HTTP for ${NAME}" --vpc-id "$VPC" --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG" --ip-permissions \
    "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=http-for-everyone}]" >/dev/null
fi
# (re)point the SSH rule at this machine only
for old in $(aws ec2 describe-security-groups --group-ids "$SG" --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\`].IpRanges[].CidrIp" --output text); do
  [ "$old" = "$MY_IP/32" ] || aws ec2 revoke-security-group-ingress --group-id "$SG" --protocol tcp --port 22 --cidr "$old" >/dev/null
done
aws ec2 authorize-security-group-ingress --group-id "$SG" --ip-permissions \
  "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MY_IP/32,Description=ssh-from-admin}]" >/dev/null 2>&1 || true
echo "SG=$SG VPC=$VPC"
ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
if [ "$ID" = "None" ] || [ -z "$ID" ]; then
  AMI=$(aws ec2 describe-images --owners 099720109477 \
    --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' 'Name=state,Values=available' \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text); echo "AMI=$AMI"
  ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEY_NAME" \
    --security-group-ids "$SG" --associate-public-ip-address \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}}]" \
    --query 'Instances[0].InstanceId' --output text)
fi
echo "INSTANCE=$ID"; aws ec2 wait instance-running --instance-ids "$ID"
IP=$(aws ec2 describe-instances --instance-ids "$ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
AZ=$(aws ec2 describe-instances --instance-ids "$ID" --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)
echo "VM=$NAME IP=$IP AZ=$AZ"; echo "T_VM_READY=$(date +%s)"
echo "== Step 5: 10 GB scratch volume at /dev/sdf"
V=$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=${NAME}-scratch" "Name=status,Values=available,in-use" --query 'Volumes[0].VolumeId' --output text 2>/dev/null)
if [ "$V" = "None" ] || [ -z "$V" ]; then
  V=$(aws ec2 create-volume --availability-zone "$AZ" --size 10 --volume-type gp3 \
       --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${NAME}-scratch}]" --query VolumeId --output text)
  aws ec2 wait volume-available --volume-ids "$V"; aws ec2 attach-volume --volume-id "$V" --instance-id "$ID" --device /dev/sdf >/dev/null
else echo "scratch volume already exists"; fi
echo "VOLUME=$V"
echo "== Steps 3-4: Apache"
S="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $KEY_FILE ubuntu@$IP"
for i in $(seq 1 30); do
  $S true 2>/dev/null && break; sleep 10
  # Laptops on carrier NAT or VPNs change public IP mid-run; refresh the admin rule if that happened.
  NOW_IP=$(curl -s -4 --max-time 10 https://api.ipify.org || curl -s -4 --max-time 10 https://ifconfig.me)
  if [ -n "$NOW_IP" ] && [ "$NOW_IP" != "$MY_IP" ]; then
    echo "public IP changed $MY_IP -> $NOW_IP; updating the SSH rule"
    aws ec2 revoke-security-group-ingress --group-id "$SG" --protocol tcp --port 22 --cidr "$MY_IP/32" >/dev/null 2>&1 || true
    aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22 --cidr "$NOW_IP/32" >/dev/null 2>&1 || true; MY_IP=$NOW_IP
  fi
done
$S 'sudo apt-get update -qq >/dev/null; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2 >/dev/null;
    sudo systemctl enable apache2 >/dev/null 2>&1; sudo systemctl start apache2; echo "APACHE=$(systemctl is-active apache2)"; hostname; lsb_release -ds'
echo "HTTP=$(curl -s -o /dev/null -w '%{http_code}' http://$IP/)"; curl -s "http://$IP/" | grep -o '<title>.*</title>'; echo "T_APACHE_OK=$(date +%s)"
echo "== Step 6 on the instance: prepare the OS for Google Cloud (cloud-init datasource, netplan, fstab)"
# An AWS Ubuntu image boots on GCE but (1) cloud-init pinned to the Ec2 datasource waits for the AWS metadata
# service, (2) netplan pins the NIC by MAC address, (3) the boot-time fsck fails on a copied root (see the
# capture step). These edits make the captured disk cloud-neutral.
$S 'set -e
    printf "datasource_list: [ GCE, Ec2, None ]\n" | sudo tee /etc/cloud/cloud.cfg.d/99-multicloud.cfg >/dev/null
    printf "network:\n  version: 2\n  ethernets:\n    any:\n      match:\n        name: \"e*\"\n      dhcp4: true\n" | sudo tee /etc/netplan/60-any-nic.yaml >/dev/null
    sudo chmod 600 /etc/netplan/60-any-nic.yaml
    sudo sed -i -E "s/(\s)0 1\s*$/\10 0/" /etc/fstab        # no fsck at boot: the capture is crash-consistent, the journal replays
    sudo cloud-init clean --logs >/dev/null 2>&1 || true   # next boot (on GCE) is a fresh instance: new host keys, network, metadata
    printf "migrated-from: AWS instance %s (%s) captured %s\n" "$(hostname)" "$(curl -s -4 --max-time 5 https://api.ipify.org)" "$(date -u +%Y-%m-%dT%H:%MZ)" | sudo tee /var/www/html/migrated-from.txt >/dev/null
    echo "PREP_DONE: $(grep -c "0 0" /etc/fstab) fstab entries without fsck, netplan 60-any-nic.yaml, datasource GCE first"'
echo "T_PREP_DONE=$(date +%s)"
echo "== Steps 7-8 on the instance: capture the root volume (scratch volume = the 10 GB disk)"
$S 'set -e; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-utils >/dev/null
    DEV=$(lsblk -dno NAME,SIZE | awk "\$2==\"10G\"{print \"/dev/\"\$1; exit}"); sudo mkdir -p /mnt/img
    mountpoint -q /mnt/img || { sudo mkfs.ext4 -q -F "$DEV"; sudo mount "$DEV" /mnt/img; }; sudo rm -f /mnt/img/disk.raw /mnt/img/disk.qcow2
    ROOT=/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)"); PART=$(findmnt -no SOURCE /); echo "CONVERT_START root=$ROOT rootfs=$PART scratch=$DEV"
    # 1. raw copy of the OS disk with the root filesystem frozen. "-T none" reads the disk with O_DIRECT: the
    #    whole-disk device has its own page cache, which can still hold the superblock from before the first-boot
    #    online resize; a copy made through that stale cache carries a 2 GB superblock on a 30 GB filesystem and
    #    e2fsck then destroys it (seen 2026-10-27). Dropping the caches first and bypassing them makes it exact.
    sudo sh -c "sync; echo 3 > /proc/sys/vm/drop_caches; blockdev --flushbufs $ROOT; fsfreeze -f /; qemu-img convert -T none -O raw $ROOT /mnt/img/disk.raw; rc=\$?; fsfreeze -u /; exit \$rc"
    PART=$(findmnt -no SOURCE /); LIVE=$(sudo dumpe2fs -h "$PART" 2>/dev/null | awk "/^Block count/{print \$3}")
    LOOP=$(sudo losetup -fP --show /mnt/img/disk.raw); N=$(echo "$PART" | grep -o "[0-9]*$"); COPY=$(sudo dumpe2fs -h "${LOOP}p${N}" 2>/dev/null | awk "/^Block count/{print \$3}")
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
echo "IMAGE_URL=http://$IP/disk.qcow2"; echo "AWS_BUILD_DONE"
