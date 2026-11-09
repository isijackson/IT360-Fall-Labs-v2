# Lab: Migrate an Apache Web Server from AWS EC2 to Google Compute Engine

**Course:** IT 360 Cloud Integration | **Week 1** | **Time:** 2 to 2.5 hours

**Student handout:** `Lab 1 Student Guide - AWS to GCP Apache Migration.docx` in this folder is the
printable version of this guide, with a console (UI) path and a CLI path for every step, expected
results, troubleshooting and the cleanup proof. Generated 2026-10-28 from a verified run.

**Click-by-click handout:** `Lab 1 Click-by-Click - AWS to GCP Image Creation and Migration.docx` is the shorter, screenshot-driven version: every console step has a numbered screenshot of where to click (`images/clicks/`) next to the matching AWS CloudShell, SSH or Google Cloud Shell commands. Version 2026-10-29; screenshots taken from the live consoles on 2026-10-28 and 2026-10-29; commands re-validated on 2026-10-31.

In this lab you build a Linux web server in AWS, capture its boot disk as a
portable image, move that image to Google Cloud, and boot it as a Compute Engine
VM. At the end, the *same* server that answered on an AWS public IP answers on a
Google Cloud public IP.

```
   AWS (us-east-2)                                   Google Cloud (us-central1)
 +--------------------+    1 GB compressed image     +------------------------------+
 | EC2 apacheserver1  |  ───────────────────────▶    | Cloud Storage bucket         |
 | Ubuntu 22.04       |   (qcow2 over HTTP, then     |   disk.tar.gz                |
 | Apache 2           |    raw tar.gz to a bucket)   +--------------┬---------------+
 +--------------------+                                             │ images create
                                                     +--------------▼---------------+
                                                     | Image apacheserver-image-aws |
                                                     +--------------┬---------------+
                                                                    │ instances create
                                                     +--------------▼---------------+
                                                     | VM apacheserver-gcp-aws      |
                                                     | tag: http-server :80         |
                                                     +------------------------------+
```

## Learning outcomes

By the end of this lab you will be able to:

1. Launch an Ubuntu EC2 instance, install Apache, and verify it over HTTP.
2. Attach a scratch EBS volume and capture a running VM's boot disk with `qemu-img`.
3. Move a disk image between clouds and convert it to the Compute Engine raw format.
4. Create a Compute Engine image from Cloud Storage and boot a VM from it.
5. Open HTTP traffic with a VPC firewall rule and validate the migrated service.
6. Troubleshoot the common failures in a cross-cloud migration.
7. Clean up every billable resource in both clouds.

## Why this method and not the "Migrate to Virtual Machines" AWS connector?

Both alternatives are written up in **Part 4B** for students with their own AWS account.

Google's Migrate to VMs service can replicate EC2 instances directly, but it
requires a **long-lived IAM user access key** in AWS. Educational sandboxes such
as Vocareum deny `iam:CreateUser` through an organization policy and also
delete `ec2 export-image` tasks, so the connector cannot be set up there. The
disk-image method in this lab needs only SSH access to the EC2 instance and
normal Compute Engine permissions, and it teaches the same concepts: capture,
transfer, import, cut over, validate.

## Prerequisites

- An AWS account or lab sandbox where you can launch EC2 instances. The
  Vocareum **AWS Sandbox** works for every AWS step in this lab.
- A Google Cloud project with billing enabled where you can enable APIs, create
  Cloud Storage buckets, Compute Engine images, VMs, and **firewall rules**.
  A personal free-trial project works. See the instructor note at the end
  about the Vocareum GCP lab.
- Basic Linux command line skills. All commands are given in full.

## Naming used in this guide

| Item | Value in this guide | Yours |
|---|---|---|
| AWS region | `us-east-2` (Ohio); Vocareum sandboxes use `us-east-1` | |
| EC2 instance name | `apacheserver1` | |
| EC2 public IP | `<EC2_PUBLIC_IP>` | |
| EC2 key pair | `apacheserver1-key` (own account, created by the script) or `vockey` (Vocareum) | |
| Security group | `apacheserver1-sg`: 22 from your IP only, 80 from anywhere | |
| GCP project ID | `<PROJECT_ID>` (instructor: `jackson-isiko`) | |
| GCP bucket | `<PROJECT_ID>-apache-migration-aws` | |
| GCP image | `apacheserver-image-aws` | |
| GCP VM | `apacheserver-gcp-aws` | |
| GCP zone | `us-central1-a` | |

The `-aws` suffix on the GCP names lets this lab and its Azure variant run side by side in
one project (the Azure variant uses `apacheserver-image` and `apacheserver-gcp`).

Write your real values in the right-hand column before you start.

---

## Part 1. Build the Apache server in AWS (25 min)

### Step 1. Launch an Ubuntu EC2 instance

Console path: **EC2 → Instances → Launch instance**.

| Setting | Value |
|---|---|
| Name | `apacheserver1` |
| AMI | Ubuntu Server 22.04 LTS from the Community AMIs: the Quick Start list no longer offers plain 22.04, so click **Browse more AMIs** → **Community AMIs**, search `ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server`, and **Select** the newest one whose Owner is 099720109477 (Canonical) |
| Instance type | `t3.micro` (`t2.micro` on Vocareum) |
| Key pair | Vocareum: `vockey`. Own account: create one and download the `.pem`. |
| Network | Default VPC, **Auto-assign public IP: Enable** |
| Security group | New group `apacheserver1-sg` allowing **SSH (22) from your own IP** (the console offers *My IP*) and **HTTP (80)** from `0.0.0.0/0` |

Click **Launch instance**, then note the **Public IPv4 address**.

CLI alternative (run in the Vocareum terminal or anywhere the AWS CLI is configured):

```bash
KEY=apacheserver1-key; TYPE=t3.micro          # Vocareum: KEY=vockey; TYPE=t2.micro, and skip create-key-pair
mkdir -p ~/.ssh && chmod 700 ~/.ssh
aws ec2 create-key-pair --key-name $KEY --query KeyMaterial --output text > ~/.ssh/$KEY.pem && chmod 400 ~/.ssh/$KEY.pem
MY_IP=$(curl -s -4 https://api.ipify.org)
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 create-security-group --group-name apacheserver1-sg \
      --description "SSH from admin and HTTP" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG --ip-permissions \
  "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MY_IP/32}]" \
  "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]"
AMI=$(aws ec2 describe-images --owners 099720109477 \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
aws ec2 run-instances --image-id $AMI --instance-type $TYPE --key-name $KEY \
  --security-group-ids $SG --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=apacheserver1}]' \
  --query 'Instances[0].InstanceId' --output text
```

### Step 2. Connect over SSH

```bash
chmod 400 /path/to/key.pem          # Vocareum terminal: ~/.ssh/labsuser.pem
ssh -i /path/to/key.pem ubuntu@<EC2_PUBLIC_IP>
```

### Step 3. Install Apache

```bash
sudo apt update -y
sudo apt install apache2 -y
sudo systemctl enable apache2
sudo systemctl start apache2
```

### Step 4. Verify Apache in AWS

```bash
systemctl is-active apache2          # expect: active
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/   # expect: 200
```

Open `http://<EC2_PUBLIC_IP>` in a browser. You should see
**"Apache2 Ubuntu Default Page: It works"**.

**Checkpoint 1:** screenshot the browser page showing the AWS public IP.

---

## Part 2. Capture the boot disk as a portable image (25 min)

You cannot safely write an image of the root disk onto the root disk itself, so
first attach a small scratch volume to hold the output.

### Step 5. Attach a 10 GB scratch volume

From the AWS CLI (replace the instance ID):

```bash
I=<INSTANCE_ID>
AZ=$(aws ec2 describe-instances --instance-ids $I \
      --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)
V=$(aws ec2 create-volume --availability-zone $AZ --size 10 --volume-type gp3 \
      --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=apacheserver1-scratch}]' \
      --query VolumeId --output text)
aws ec2 wait volume-available --volume-ids $V
aws ec2 attach-volume --volume-id $V --instance-id $I --device /dev/sdf
echo "Scratch volume: $V"
```

Console alternative: **EC2 → Volumes → Create volume** (10 GiB, gp3, same AZ as the
instance, tag `Name=apacheserver1-scratch` so the cleanup scripts find it) → **Actions → Attach volume** → device `/dev/sdf`.

### Step 6. Prepare the OS for Google Cloud, then mount the scratch volume

An AWS Ubuntu image boots on Compute Engine, but three AWS-specific settings would
leave it without network or stuck in a boot-time fsck: cloud-init is pinned to the
EC2 metadata service, netplan pins the NIC by MAC address, and `/etc/fstab` asks for
an fsck of the root at boot. SSH to the instance and make the disk cloud-neutral:

```bash
printf "datasource_list: [ GCE, Ec2, None ]\n" | sudo tee /etc/cloud/cloud.cfg.d/99-multicloud.cfg
printf "network:\n  version: 2\n  ethernets:\n    any:\n      match:\n        name: \"e*\"\n      dhcp4: true\n" | sudo tee /etc/netplan/60-any-nic.yaml
sudo chmod 600 /etc/netplan/60-any-nic.yaml
sudo sed -i -E 's/(\s)0 1\s*$/\10 0/' /etc/fstab          # no fsck at boot; the journal replays
sudo cloud-init clean --logs                             # next boot is a fresh instance
echo "migrated-from: AWS $(hostname) $(date -u +%FT%TZ)" | sudo tee /var/www/html/migrated-from.txt
```

Then format and mount the scratch volume (it is `nvme1n1` on t3 instances, `xvdf` on t2):

```bash
lsblk                                  # the new 10G disk
DEV=$(lsblk -dno NAME,SIZE | awk '$2=="10G"{print "/dev/"$1; exit}')
sudo mkfs.ext4 -F $DEV; sudo mkdir -p /mnt/img; sudo mount $DEV /mnt/img
```

### Step 7. Capture, check and compress the root volume

Freeze the root filesystem, take a raw copy of the whole root device straight from
disk, thaw, confirm the copy has the same superblock as the live root, check it,
then compress it:

```bash
sudo apt install -y qemu-utils
ROOT=/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)")       # nvme0n1 on t3, xvda on t2
PART=$(findmnt -no SOURCE /)                                 # nvme0n1p1 or xvda1
sudo sh -c "sync; echo 3 > /proc/sys/vm/drop_caches; blockdev --flushbufs $ROOT; fsfreeze -f /; qemu-img convert -T none -O raw $ROOT /mnt/img/disk.raw; fsfreeze -u /"
LOOP=$(sudo losetup -fP --show /mnt/img/disk.raw); N=${PART##*[!0-9]}
sudo dumpe2fs -h $PART | grep "Block count"; sudo dumpe2fs -h ${LOOP}p$N | grep "Block count"   # must be equal
sudo e2fsck -fy ${LOOP}p$N; sudo losetup -d $LOOP
sudo qemu-img convert -c -O qcow2 /mnt/img/disk.raw /mnt/img/disk.qcow2 && sudo rm /mnt/img/disk.raw
ls -lh /mnt/img/disk.qcow2             # about 1 GB for a fresh server
md5sum /mnt/img/disk.qcow2             # write this down
```

This takes 3 to 5 minutes on a t3.micro. `fsfreeze` blocks writes to `/` during the raw
copy, so a second SSH session may pause until the thaw. Why the cache flush and `-T none`:
Linux caches the whole-disk device and the partition separately, and the whole-disk cache
can still hold the superblock from *before* the first-boot resize; a copy made through it
claims a 2 GB filesystem on an 8 GB partition, `e2fsck` then clears every inode above 2 GB,
and the migrated VM panics at `/sbin/init`. The two `Block count` lines prove the copy is
exact. Why the `e2fsck`: the copy is crash-consistent (the journal replays) and some copies
report *Resize inode not valid*; checking the copy, never the live root, is also where you
first see that a migrated disk is a copy you own.

### Step 8. Publish the image for download

The simplest cross-cloud transfer for a lab is to serve the file from the Apache
server you just built:

```bash
sudo chmod 644 /mnt/img/disk.qcow2
sudo ln -s /mnt/img/disk.qcow2 /var/www/html/disk.qcow2
curl -sI http://localhost/disk.qcow2 | head -1      # expect HTTP/1.1 200 OK
```

The file is now at `http://<EC2_PUBLIC_IP>/disk.qcow2`. You will remove this
link in Step 11. Do not leave a disk image on a public web server longer than
needed.

**Checkpoint 2:** record the image size and md5 hash.

---

## Part 3. Transfer the image to Google Cloud (20 min)

Do this part in **Cloud Shell** in your GCP project (console → the `>_` icon at
the top right). Cloud Shell already has `gcloud`, `curl`, and `tar`. A laptop with
`gcloud`, `qemu-img` and GNU tar (`brew install qemu gnu-tar`) works the same way.

### Step 9. Enable APIs and create a bucket

```bash
gcloud config set project <PROJECT_ID>
gcloud services enable compute.googleapis.com storage.googleapis.com
B=<PROJECT_ID>-apache-migration-aws
gcloud storage buckets create gs://$B --location=us-central1 --uniform-bucket-level-access
```

### Step 10. Download the image and verify it

```bash
curl -f --retry 10 --retry-all-errors --retry-delay 5 -C - -O http://<EC2_PUBLIC_IP>/disk.qcow2   # resumable
md5sum disk.qcow2                      # must match Checkpoint 2
```

### Step 11. Remove the public download link in AWS

Back on the EC2 instance (or in a second SSH session):

```bash
sudo rm /var/www/html/disk.qcow2
```

### Step 12. Convert to the Compute Engine raw format

Compute Engine builds images from a **tar.gz that contains a single file named
`disk.raw`**, written with GNU tar in `oldgnu` format with sparse-file support.

```bash
sudo apt-get install -y qemu-utils
qemu-img convert -O raw disk.qcow2 disk.raw
rm disk.qcow2
tar --format=oldgnu -Sczf disk.tar.gz disk.raw
rm disk.raw
ls -lh disk.tar.gz                     # about 1 GB
```

### Step 13. Upload to Cloud Storage

```bash
gcloud storage cp disk.tar.gz gs://$B/disk.tar.gz
gcloud storage ls -l gs://$B/
```

---

## Part 4. Create the image and launch the VM in GCP (20 min)

### Step 14. Create the Compute Engine image

```bash
gcloud compute images create apacheserver-image-aws \
  --source-uri=gs://$B/disk.tar.gz \
  --family=apacheserver-aws \
  --description="Migrated from AWS apacheserver1"
gcloud compute images describe apacheserver-image-aws --format="value(name,status,diskSizeGb)"
```

Status must be `READY`. Creation takes 1 to 3 minutes.

### Step 15. Launch the VM from the image

```bash
gcloud compute instances create apacheserver-gcp-aws \
  --zone=us-central1-a --machine-type=e2-micro \
  --image=apacheserver-image-aws --boot-disk-size=10GB \
  --tags=http-server
```

Note the `EXTERNAL_IP` in the output. The `http-server` tag is what the firewall
rule in the next part matches on.

---

## Part 4B. Alternative routes: AWS AMI export and Google Migrate to Virtual Machines (optional, 45 to 90 min)

Parts 2 to 4 copy the disk yourself. Two other routes use the cloud providers'
own tools. Both need permissions that the Vocareum AWS sandbox denies (see
"Why this method"), so do them on a personal AWS account or ask the instructor
to run them in the school account. Pick one; the result in each case is a
Compute Engine VM you validate in Part 5.

| Route | What moves | AWS side needs | GCP side needs | Time |
|---|---|---|---|---|
| A. Disk copy (Parts 2 to 4) | `disk.qcow2` over HTTP | SSH to the instance | Cloud Storage, `images create` | 65 min (the Part 2 to 4 allowances) |
| B. AMI export + Image Import | AMI → VMDK in S3 → Cloud Storage | `vmimport` IAM role, S3 bucket, `ec2 export-image` | Migrate to VMs **Image imports** | 45 to 90 min |
| C. Migrate to VMs AWS connector | Snapshots of the running instance, pulled by Google | IAM user with an access key and the Migrate to VMs policy | Migrate to VMs **Sources** → AWS source | 60 to 90 min (first replication is the slow part) |

### Route B. Export the AMI with AWS tools, import it with Google Image Import

**B1. Create an AMI of the instance.** Console: **EC2 → Instances → select
`apacheserver1` → Actions → Image and templates → Create image**, name
`apacheserver1-ami`, keep **Reboot instance** ticked (a consistent copy), **Create
image**. Watch **AMIs → Owned by me** until the status is Available. CLI:

```bash
export AWS_DEFAULT_REGION=us-east-2
I=<INSTANCE_ID>
AMI=$(aws ec2 create-image --instance-id $I --name apacheserver1-ami --query ImageId --output text)
aws ec2 wait image-available --image-ids $AMI; echo $AMI
```

**B2. One-time setup for VM Import/Export: an S3 bucket and the `vmimport` role.**
The export service writes into your bucket through this role; it must be named
exactly `vmimport` and trust `vmie.amazonaws.com`.

```bash
B=apacheserver1-export-$(aws sts get-caller-identity --query Account --output text)
aws s3 mb s3://$B --region us-east-2
cat > trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"vmie.amazonaws.com"},
  "Action":"sts:AssumeRole","Condition":{"StringEquals":{"sts:Externalid":"vmimport"}}}]}
EOF
cat > role-policy.json <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["s3:GetBucketLocation","s3:GetObject","s3:ListBucket","s3:PutObject","s3:GetBucketAcl"],
  "Resource":["arn:aws:s3:::$B","arn:aws:s3:::$B/*"]},
 {"Effect":"Allow","Action":["ec2:ModifySnapshotAttribute","ec2:CopySnapshot","ec2:RegisterImage","ec2:Describe*"],"Resource":"*"}]}
EOF
aws iam create-role --role-name vmimport --assume-role-policy-document file://trust.json
aws iam put-role-policy --role-name vmimport --policy-name vmimport --policy-document file://role-policy.json
```

**B3. Export the AMI as a VMDK.** There is no console button for this; it is CLI only.

```bash
TASK=$(aws ec2 export-image --image-id $AMI --disk-image-format VMDK \
        --s3-export-location S3Bucket=$B,S3Prefix=export/ --query ExportImageTaskId --output text)
watch -n 20 "aws ec2 describe-export-image-tasks --export-image-task-ids $TASK \
  --query 'ExportImageTasks[0].[Status,Progress,StatusMessage]' --output text"   # until: completed
aws s3 ls s3://$B/export/                                                        # export-ami-xxxx.vmdk, about 1.5 GB
```

In the Vocareum sandbox this task goes to `deleted` within seconds; that is the
organization policy, not a mistake on your side.

**B4. Move the VMDK to Cloud Storage.** Cloud Shell has no AWS credentials, so
hand it a pre-signed URL (valid for one hour) instead of keys:

```bash
# in the AWS shell
aws s3 presign s3://$B/export/<FILE>.vmdk --expires-in 3600
# in Google Cloud Shell
curl -f -L -o disk.vmdk "<PRESIGNED_URL>"
gcloud storage cp disk.vmdk gs://<PROJECT_ID>-apache-migration-aws/disk.vmdk
```

**B5. Import the VMDK as a Compute Engine image.** Console: **Compute Engine →
Migrate to Virtual Machines → Image imports → Import image** (the old
*Create image → Virtual disk* source now redirects here). Name
`apacheserver-image-aws-vmdk`, Source Cloud Storage file
`<PROJECT_ID>-apache-migration-aws/disk.vmdk`, Region `us-central1`, then
**Import image**. The import runs a temporary worker VM, installs the Google
guest environment and takes 10 to 20 minutes. CLI:

```bash
gcloud services enable vmmigration.googleapis.com
gcloud migration vms image-imports create apacheserver-image-aws-vmdk \
  --location=us-central1 --source-file=gs://<PROJECT_ID>-apache-migration-aws/disk.vmdk \
  --image-name=apacheserver-image-aws-vmdk      # target project defaults to the current project
gcloud migration vms image-imports describe apacheserver-image-aws-vmdk --location=us-central1   # until the state is SUCCEEDED
```

Then launch the VM exactly as in Step 15 with `--image=apacheserver-image-aws-vmdk`
and continue with Part 5. Because the import installs the guest agent,
`gcloud compute ssh` works immediately.

### Route C. Google Migrate to Virtual Machines with the AWS source connector

Google replicates the running instance from EBS snapshots; nothing is copied by
hand. It needs an IAM user access key, which the Vocareum sandbox refuses to
create.

**C1. In AWS, create the connector's IAM user and policy** (console: **IAM →
Policies → Create policy → JSON**, then **IAM → Users → Create user → Attach
policies directly**, then **Security credentials → Create access key → Third-party
service**). Google publishes the exact policy in the Migrate to VMs
documentation ("AWS prerequisites"); it is read access to EC2 plus snapshot
create, delete, tag and EBS direct-API read (`ebs:ListSnapshotBlocks`,
`ebs:GetSnapshotBlock`, `ebs:ListChangedBlocks`). Keep the key ID and secret for
step C2; never commit them.

**C2. In GCP, add the AWS source.** Enable the API (`gcloud services enable
vmmigration.googleapis.com`), then **Compute Engine → Migrate to Virtual
Machines → Sources → Add source → Add AWS source**: Name `aws-us-east-2`, GCP
region `us-central1`, AWS region `us-east-2`, paste the Access key ID and Secret
access key, **Create**. After a minute the source shows your EC2 inventory.

**C3. Migrate.** Open the source, tick `apacheserver1` → **Add migrations**. On
the **Migrate VMs** tab select it → **Start replication**; the first cycle copies
the whole 8 GB disk (10 to 30 minutes), later cycles copy only changed blocks.
Then **Edit target details**: project, zone `us-central1-a`, machine type
`e2-micro`, network `default`, external IP ephemeral, network tag `http-server`.
Click **Cut-over** (or **Test-clone** to try first): Google stops replication,
creates the Compute Engine VM from the latest snapshot and installs the guest
environment. When the VM answers on port 80 (Part 5), click **Finalize** to
release the replication resources, and delete the source when you are done.

Route C is console only. The Migrate to VMs REST API (`vmmigration.googleapis.com`) has the
sources and migrating VMs, but gcloud has no commands for them: the only groups under
`gcloud migration vms` are `image-imports`, `machine-image-imports` and `target-projects`
(Google Cloud SDK 538.0.0, checked 2026-10-31).

Clean-up for these routes, on top of Part 7: deregister the AMI and delete its
snapshot, empty and delete the S3 bucket, delete the `vmimport` role, delete
the IAM user and its access key, and delete the Migrate to VMs source and the
`-vmdk` image.

---

## Part 5. Open the firewall and validate (15 min)

### Step 16. Allow HTTP traffic in the VPC firewall

Console path: **VPC network → Firewall → Create firewall rule**.

| Setting | Value |
|---|---|
| Name | `allow-http` |
| Network | `default` |
| Direction | Ingress |
| Action | Allow |
| Targets | Specified target tags: `http-server` |
| Source IPv4 ranges | `0.0.0.0/0` |
| Protocols and ports | TCP `80` |

CLI equivalent:

```bash
gcloud compute firewall-rules create allow-http --network=default \
  --direction=INGRESS --action=ALLOW --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 --target-tags=http-server
```

### Step 17. Validate from the outside

```bash
IP=$(gcloud compute instances describe apacheserver-gcp-aws --zone=us-central1-a \
      --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
curl -s -o /dev/null -w '%{http_code}\n' http://$IP/      # expect 200
```

Open `http://<EXTERNAL_IP>` in a browser. The Apache default page should load.
On the 2026-10-27 runs the first HTTP 200 came about 36 s to 2 min after the VM was created
(36 s on the afternoon run).

### Step 18. Validate from the inside

The migrated disk does not yet contain Google's guest agent, so metadata SSH keys
are not applied until you install it. Use the AWS key pair, which the image still
trusts, to get in the first time. From the machine that holds your AWS `.pem`:

```bash
ssh -i /path/to/key.pem ubuntu@<EXTERNAL_IP>
sudo systemctl status apache2 --no-pager | head -3
sudo apt-get install -y google-guest-agent google-compute-engine
```

If SSH times out, add a firewall rule for TCP 22 from **your own public IP only**
(`curl -s https://checkip.amazonaws.com` prints it):

```bash
gcloud compute firewall-rules create allow-ssh-admin --network=default \
  --direction=INGRESS --action=ALLOW --rules=tcp:22 \
  --source-ranges=<YOUR_IP>/32 --target-tags=http-server
```

After the guest agent is installed, `gcloud compute ssh ubuntu@apacheserver-gcp-aws
--zone=us-central1-a` works. Expect a host-key-changed warning the first time,
because the guest environment regenerates SSH host keys.

**Checkpoint 3:** screenshot the browser page on the GCP external IP, and the
output of `systemctl status apache2` from inside the GCP VM.

---

## Part 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `export-image` task goes to `deleted` with no message | Sandbox policy kills VM Import/Export | Use this lab's qemu-img method instead |
| `iam:CreateUser` AccessDenied with "explicit deny in a service control policy" | Sandbox forbids IAM users, so the Migrate to VMs connector cannot be configured | Use this lab's method, or your own AWS account |
| `qemu-img: command not found` | Package missing | `sudo apt install -y qemu-utils` |
| `No space left on device` during convert | Writing to the root disk | Write to the mounted scratch volume `/mnt/img` |
| `curl -O` in Cloud Shell gets 404 | Symlink not created, or wrong IP | Re-run Step 8, confirm with `curl -I` |
| `images create` fails: "not a valid tar" | Wrong tar format or file not named `disk.raw` | Repeat Step 12 exactly, GNU tar `--format=oldgnu` |
| Browser times out on GCP IP | No firewall rule, or VM lacks the `http-server` tag | Step 16, then `gcloud compute instances add-tags` |
| `Permission denied (publickey)` with `gcloud compute ssh` | Guest agent not installed yet | Step 18, or SSH with the AWS key |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Host keys regenerated by guest environment | `ssh-keygen -R <EXTERNAL_IP>` and retry |
| `Required 'compute.networks.updatePolicy' permission` | Your account cannot create firewall rules in this project | Use a project where you have Compute Network Admin |

---

## Part 7. Clean up (10 min)

Everything below is billable until deleted.

**AWS**

```bash
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
aws ec2 wait instance-terminated --instance-ids <INSTANCE_ID>
aws ec2 delete-volume --volume-id <SCRATCH_VOLUME_ID>
aws ec2 delete-security-group --group-id <SG_ID>
aws ec2 delete-key-pair --key-name apacheserver1-key   # own-account runs (Vocareum's vockey stays)
```

**Google Cloud**

```bash
gcloud compute instances delete apacheserver-gcp-aws --zone=us-central1-a --quiet
gcloud compute images delete apacheserver-image-aws --quiet
gcloud storage rm -r gs://<PROJECT_ID>-apache-migration-aws
gcloud compute firewall-rules delete allow-http --quiet    # keep it if the Azure variant is still running
gcloud compute firewall-rules delete allow-ssh-admin --quiet   # if Step 18 created it
```

Confirm with `aws ec2 describe-instances` and `gcloud compute instances list`
that nothing from this lab remains.

**One-command teardown.** The cleanup scripts find every resource by name, so
no IDs are needed. Each lists what it found, asks once, then deletes and
prints a "remaining" count. Add `-n` to only list, `-y` to skip the prompt.

```bash
# AWS side: in CloudShell (us-east-2), the Vocareum terminal, or a laptop with AWS_PROFILE set
bash scripts/05-cleanup-aws.sh
# GCP side: in Cloud Shell or anywhere gcloud is signed in
bash scripts/06-cleanup-gcp.sh <PROJECT_ID>
# Both at once from a machine that has both CLIs signed in
bash scripts/rollback-lab1.sh <PROJECT_ID> -y
```

They remove the instance, scratch volume, security group, key pair
(`apacheserver1-key`), any AMI and snapshot named after the server, any
`apacheserver1*` S3 bucket and the `vmimport` role on AWS; and the `-aws` VM, image
and bucket on GCP, plus the `allow-http` rule when no other `http-server` VM is left.

---

## Deliverables

Submit a single PDF or document with:

1. Checkpoint 1: Apache page on the AWS public IP.
2. Checkpoint 2: image size and md5 hash from AWS, and the matching md5 from Cloud Shell.
3. Checkpoint 3: Apache page on the GCP external IP, and `systemctl status apache2` from inside the GCP VM.
4. The output of the two "confirm nothing remains" commands after cleanup.
5. Three to five sentences: what in the image had to change for the VM to run well on Google Cloud, and what would be different if you had used the Migrate to VMs connector instead.

## Follow-along video

`videos/aws-to-gcp-vm-migration-lab.mp4` is a single ten-minute narrated
walkthrough of this guide with chapter cards for each part. Pause after each
step, do it yourself, then resume.

| Time | Chapter | Covers |
|---|---|---|
| 0:00 | Overview | What you build, architecture diagram, why this method, what sandbox blocks look like, the Vocareum panel |
| 1:50 | Part 1 | Steps 1 to 4, terminal and browser checks, Checkpoint 1 |
| 3:20 | Part 2 | Disk layout, Steps 5 to 8, Checkpoint 2 |
| 5:10 | Parts 3 and 4 | Steps 9 to 15, Cloud Shell output, where things appear in the console |
| 6:55 | Part 5 | Steps 16 to 18, Checkpoint 3, troubleshooting, cleanup proof, submission |

The `images/` folder holds every screenshot used in the video, captured from a
real run of this lab:

| Image | Shows |
|---|---|
| `vocareum-aws-lab-panel.png` | Vocareum AWS Sandbox panel with status, Cloud access and terminal |
| `aws-apache-verified.png`, `apache-it-works-aws.png` | Step 4 terminal check and the browser page (Checkpoint 1) |
| `ec2-disk-layout.png`, `aws-volume-attached.png`, `aws-image-ready.png` | Part 2: lsblk, scratch volume attached, finished qcow2 with md5 (Checkpoint 2) |
| `gcp-cloud-shell-apis.png` | Cloud Shell after Step 9 |
| `gcp-instance-created.png` | Step 15 output: apacheserver-gcp RUNNING with its external IP, then the first HTTP 200 (captured on the 2026-10-24 run, before the `-aws` suffix was introduced) |
| `gcp-console-vm-instances.png`, `gcp-console-vm-instances-sample.png` | The Compute Engine VM instances page, empty and with a sample apacheserver-gcp row added for illustration (captured on the 2026-10-24 run, before the `-aws` suffix was introduced) |
| `gcp-apache-verified.png` | Step 18 inside the GCP VM (Checkpoint 3) |
| `aws-export-task-deleted.png`, `aws-iam-scp-denied.png` | What the sandbox blocks look like |
| `aws-cleanup-done.png` | A completed AWS cleanup |

## Helper scripts

The `scripts/` folder contains the same commands as runnable scripts:

| Script | Where to run | What it does |
|---|---|---|
| `scripts/deploy-lab1.sh <PROJECT_ID>` | Laptop with AWS credentials and gcloud | Whole lab: runs 00, then 04, then Step 11; prints the timing table and both URLs |
| `scripts/verify-lab1.sh <PROJECT_ID>` | Laptop | Lists the instance, volume, security-group rules, GCP image, VM, rule and bucket; curls both servers and the `migrated-from.txt` marker |
| `scripts/rollback-lab1.sh <PROJECT_ID> -y` | Laptop | Both teardowns (same as `destroy-lab1.sh`) |
| `scripts/00-aws-all-in-one.sh` | AWS CloudShell or a laptop with credentials (from a CloudShell outside Ohio, `export AWS_DEFAULT_REGION=us-east-2` first: CloudShell sets `AWS_REGION` to its own region) | Steps 1 to 8 in one run: key pair, security group (22 from the caller only), instance, Apache, scratch volume, Step 6 prep, frozen capture with the superblock check, qcow2 |
| `scripts/01-aws-build-apache.sh` | Vocareum terminal or any AWS CLI shell | Steps 1 to 4 on a t2.micro with `vockey` (override `KEY_NAME`, `KEY_FILE`); SSH open to the caller's IP only |
| `scripts/02-aws-attach-scratch-volume.sh` | Same AWS CLI shell | Step 5 |
| `scripts/03-ec2-make-image.sh` | **On the EC2 instance** over SSH | Steps 6 to 8: Step 6 prep, scratch and root devices found with `lsblk`/`findmnt` (t2 or t3), frozen raw copy, block-count check, `e2fsck`, qcow2, publish |
| `scripts/04-gcp-import-and-launch.sh <PROJECT_ID> <EC2_IP>` | Cloud Shell or laptop | Steps 9, 10, 12 to 17 with the `-aws` names; idempotent |
| `scripts/05-cleanup-aws.sh` | AWS CLI shell | AWS teardown by name (`-n` dry run, `-y` no prompt) |
| `scripts/06-cleanup-gcp.sh` | Cloud Shell | GCP teardown by name (`-n` dry run, `-y` no prompt) |
| `scripts/destroy-lab1.sh` | Machine with both CLIs | Runs both teardowns; skips a cloud whose CLI is not signed in |

Read each script before running it and set the variables at the top.

## Instructor run on the school AWS account (2026-10-27)

AWS account *Ensign Software Engineering Live*, the instructor's IAM user,
region us-east-2, driven from the console's CloudShell with
`scripts/00-aws-all-in-one.sh`; GCP project `jackson-isiko` from the laptop with
`scripts/04-gcp-import-and-launch.sh`. The account holds other people's resources
(key pair `shepherds-guide-django-dev`), so everything here is found by the name
`apacheserver1` and nothing else is touched.

| Checkpoint | Result |
|---|---|
| 1. Apache on AWS | `i-01b8d04d847535524`, t3.micro Ubuntu 22.04.5, us-east-2c, 18.191.148.39; security group: 22 from the CloudShell IP only, 80 from anywhere; `APACHE=active`, HTTP 200, *Apache2 Ubuntu Default Page* |
| 2. Capture | Step 6 prep (`PREP_DONE`), scratch `vol-086b9087c337faf57` as `/dev/nvme1n1`, frozen direct-I/O copy of `/dev/nvme0n1`, `superblock block count: live=2068731 copy=2068731`, qcow2 1,186,012,160 bytes, md5 `74e6879f5620cb9e7ec5ab5332f7e933`, same md5 after download |
| 3. Transfer | download 5.5 min (shared with the Azure variant's download), convert and tar 1 min, upload 1 min at 34 MiB/s |
| 4. GCP | image `apacheserver-image-aws` (8 GB, READY), VM `apacheserver-gcp-aws` e2-micro 34.72.104.58, rule `allow-http` |
| 5. Validate | `http://34.72.104.58/` → 200 with the Apache title 36 s after the VM was created (about 36 s to 2 min across the 2026-10-27 runs); serial console: `cloud-init ... finished ... Datasource DataSourceGCE`, no fsck failure, no panic; `migrated-from.txt` served from GCP names the EC2 instance; `http://18.191.148.39/disk.qcow2` → 404 after Step 11 |
| Timing | AWS build and capture 7 min in CloudShell, transfer and GCP launch 10 min from the laptop |

Two lessons from this run, both now in the scripts:

1. **Start the build once.** Two copies of `00-aws-all-in-one.sh` started in the same
   CloudShell collide on the apt lock (`Could not get lock /var/lib/dpkg/lock-frontend`)
   and the second one captures a server without Apache. `pkill -f 00-aws-all-in-one` and
   rerun; the script resumes on the existing instance.
2. **The stale-superblock capture** (found on the Azure variant the same afternoon, see its
   README) applies to AWS too. The script now drops caches, reads the device with
   `qemu-img -T none`, and stops with `CAPTURE_STALE` if the copy's block count differs
   from the live root's. On this run both were 2,068,731 blocks.

No laptop access key was created for this account; CloudShell carries the console's
credentials. To run `deploy-lab1.sh` end to end from the laptop instead, create an access
key for the IAM user and store it with `aws configure --profile ensign` (region us-east-2),
then `AWS_PROFILE=ensign bash scripts/deploy-lab1.sh jackson-isiko`.

**Evening rerun (2026-10-27, after the afternoon teardown, left running for class):** the us-east-2 CloudShell would not open a session (`Failed to open session`, then `Unable to create the environment` after a restart), so the build ran from the us-east-1 CloudShell with `AWS_DEFAULT_REGION=us-east-2` exported; the instance still landed in us-east-2c as 18.191.11.26. Build to `IMAGE_URL` took 4.5 min (superblock `live=2068731 copy=2068731`). The laptop download stalled at 657 MB and `curl` exited, so Step 10 now uses `curl --retry 10 --retry-all-errors -C -` and a rerun resumed the file. The uplink was slow (2 MiB/s), the upload took 11 min, and `gcloud compute instances create` hit its 300 s client read timeout although the VM was created; `04-gcp-import-and-launch.sh` now polls the image for `READY` and the VM for `RUNNING` instead of trusting the call. Result: `apacheserver-gcp-aws` 136.64.162.16, cloud-init finished at 20 s uptime on `DataSourceGCE`. Step 11 from CloudShell needs port 22 open from *that* CloudShell session's egress IP; the one used for the build had changed, so the fix was `authorize-security-group-ingress` for the new IP, the `ssh ... rm`, then `revoke-security-group-ingress`. The key pair file lives in the CloudShell home of the region it was created from (CloudShell homes are per region).

## Instructor run on personal accounts (2026-10-24)

Second validation run, outside Vocareum: an AWS account (us-east-1,
driven from the console's CloudShell with `scripts/00-aws-all-in-one.sh`) and
GCP project `afriven` (local gcloud with `scripts/04-gcp-import-and-launch.sh`).

| Checkpoint | Evidence |
|---|---|
| 1. Apache on AWS | `i-01053a0832355b34d`, t2.micro Ubuntu 22.04.5, `APACHE=active`, HTTP 200 on http://98.94.68.176 |
| 2. Disk captured | `/mnt/img/disk.qcow2` 1,024,731,136 bytes, md5 `6cba6a3e1c7ec5fc5b119cc18df49353`, same md5 after download |
| 3. Same server on GCP | image `apacheserver-image` READY, VM `apacheserver-gcp` e2-micro, HTTP 200 with the Apache title on http://34.59.242.231 |

Timing: AWS build to HTTP 200 3 min, qcow2 capture 3 min, download 8 min
(home link), tar 1 min, upload 3 min, image + VM + first HTTP 200 under 3 min.
Two things to know for a laptop run: macOS `tar` has no `oldgnu` format, so
install `gnu-tar` (the script now picks `gtar` automatically); and the migrated
VM has no Google guest agent, so `gcloud compute ssh` keys are not installed.
SSH into it with the AWS key pair as `ubuntu`, through a port-22 rule or an
IAP tunnel.

## Instructor note: Vocareum GCP lab limits

The Vocareum **Google Cloud Lab** account used for this course runs under a
custom organization role that cannot create VPC firewall rules
(`compute.networks.updatePolicy` is missing), and its Migrate to Virtual
Machines console page does not load. Students on that account can complete
Parts 3 and 4 but will fail at Step 16 and cannot reach the VM on port 80 or 22.
Either ask Vocareum to add Compute Network Admin to the lab role, or have
students use a personal Google Cloud project for Parts 3 to 7.

## What changed in the industry, April to October 2026

- **Migration is now agentic on all three clouds.** AWS Transform replaced Migration Hub for
  new customers (November 2025), Azure shipped a Copilot migration agent, and Google pairs
  Migration Center with Gemini. An agent profiles, maps, moves and validates; this lab is the
  manual version so you can judge what the agent is doing and when to stop it.
- **Multi-cloud is the default, not the exception.** 2026 surveys put most mid-size
  organisations on two or more clouds, and 51 percent of platform engineers support
  multi-cloud; migration between providers is a routine engineering task.
- **AI in the terminal.** Gemini CLI (free tier), GitHub Copilot CLI and AWS Kiro CLI (the
  successor to Q Developer; Q Developer reaches end of support April 30, 2027) all run
  shell commands for you. Use one to draft the runbook, and read everything it proposes.
- **FinOps for AI.** The State of FinOps 2026 survey (1,192 respondents, 83 billion dollars of
  spend) names AI cost management the most wanted skill; every lab here ends with a cost
  line and a teardown for that reason.

### Across the providers: migration and server automation (October 2026)

| Provider | What it offers for this week |
|---|---|
| AWS | AWS Transform (agentic; replaced Migration Hub for new customers Nov 2025), Application Migration Service, Kiro CLI |
| Azure | Azure Migrate with the Copilot migration agent |
| Google Cloud | Migration Center with Gemini, Migrate to VMs, Compute Engine image import (this lab) |
| DigitalOcean | Droplets from custom images; VPC subnets and routes in public preview (Sept 2026); Gradient AI cloud |
| Oracle Cloud | OCI Cloud Migrations; Oracle Interconnect for AWS (limited availability May 2026); Oracle AI Database@AWS, @Azure, @Google Cloud |

Market context (Synergy Research, Q2 2026): 143.4 billion dollars in the quarter, up 43 percent; AWS 28, Azure 20, Google 15 percent.

Sources for this section:
- https://cloudconsultingfirms.com/cloud-migration/ (AWS Transform, Azure Copilot migration agent, Migration Center + Gemini)
- https://www.usage.ai/blogs/aws/monthly-updates/aws-may-2026/ (Kiro GA, Q Developer end of support)
- https://data.finops.org/ (State of FinOps 2026)
- https://hexamatic.com.au/posts/infrastructure_as_code_in_2026/ (OpenTofu, Terraform MCP server)

### AI and automation extension (optional, 30 min)

1. Do the whole migration again as code with `../cross-cloud-iac/`: `tofu apply` the AWS
   source and the GCP target from one language, then compare the two `main.tf` files.
2. Ask an AI CLI to write `scripts/00-aws-all-in-one.sh` from the lab text, then diff it
   against the one here. Count the mistakes; that is the review step an agent still needs.
3. Debrief question for the Wasatch Dental note: if AWS Transform could have moved the
   portal in an afternoon, what would you still insist on seeing before the cutover?
