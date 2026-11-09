# Week 1 Lab 1 (Azure variant): Migrate an Apache web server VM from Azure to Google Compute Engine

This is the AWS-to-GCP lab with the **source cloud changed to Azure** and the target set to the
instructor's Google Cloud project **jackson-isiko**. The learning
goals, checkpoints and the GCP half are identical to `../aws-to-gcp-vm-migration/`; only the
source steps and the Azure cleanup differ. Students can run the Azure side in the free
**Vocareum Azure Sandbox** (portal Cloud Shell; the laptop Azure CLI is blocked there) and the
GCP side in their own project or the Vocareum GCP lab.

## Objectives

1. Build an Ubuntu 22.04 VM on Azure with Apache and verify it from a browser.
2. Capture the VM's OS disk as a compressed qcow2 on a scratch data disk.
3. Move the image to Cloud Storage, create a Compute Engine image, boot it, verify Apache.
4. Compare the two platforms and clean up every billable resource.

## Naming used in this guide

| Item | Value |
|---|---|
| Azure subscription | your own (instructor: *Ensign College - School Card*, Default Directory tenant) or the Vocareum sandbox |
| Azure region and size | `eastus`, `Standard_D2s_v4` (the combination with capacity in the Vocareum sandbox; fine in a personal subscription too) |
| Azure resource group | `apacheserver1-rg` in your own subscription, or the sandbox's pre-created group (`RG=<name>`) |
| Azure VM | `apacheserver1`, Ubuntu 22.04, user `ubuntu`, key `~/.ssh/apacheserver1-key` |
| Scratch disk | `apacheserver1-scratch`, 10 GB Standard_LRS at LUN 0 (`/dev/disk/azure/scsi1/lun0`) |
| GCP project | `jackson-isiko` (replace with your own project id) |
| GCP bucket, image, VM | `<project>-apache-migration`, `apacheserver-image`, `apacheserver-gcp` in `us-central1-a` |

**One command for the whole lab:** `bash scripts/deploy-lab1.sh <GCP_PROJECT_ID>` on a laptop
where `az login` and `gcloud auth login` are done and `qemu-img` and GNU tar are installed
(`brew install qemu gnu-tar`). It runs Parts 1 to 5 and prints every checkpoint and a timing
table (about 25 minutes). `bash scripts/verify-lab1.sh <GCP_PROJECT_ID>` re-checks both sides
and `bash scripts/rollback-lab1.sh <GCP_PROJECT_ID> -y` deletes everything. The architecture is
drawn in [`../architecture/`](../architecture/README.md). The parts below are the same steps by hand.

## Part 1. Build the web server on Azure (15 min)

On your laptop with `az login` done (or in the portal's Cloud Shell on the Vocareum sandbox,
where you use the pre-created group instead of creating one):

```bash
RG=apacheserver1-rg; az group create -n $RG -l eastus        # sandbox: RG=$(az group list --query "[0].name" -o tsv)
ssh-keygen -t rsa -b 2048 -N "" -f ~/.ssh/apacheserver1-key
MY_IP=$(curl -s -4 https://api.ipify.org)                    # SSH will be open to this address only
az vm create -g $RG -n apacheserver1 -l eastus --image Ubuntu2204 --size Standard_D2s_v4 \
  --admin-username ubuntu --ssh-key-values ~/.ssh/apacheserver1-key.pub --public-ip-sku Standard --nsg-rule NONE
az network nsg rule create -g $RG --nsg-name apacheserver1NSG -n allow-ssh-admin --priority 1000 \
  --protocol Tcp --source-address-prefixes $MY_IP/32 --destination-port-ranges 22 --access Allow
az network nsg rule create -g $RG --nsg-name apacheserver1NSG -n allow-http --priority 1010 \
  --protocol Tcp --destination-port-ranges 80 --access Allow
IP=$(az vm show -d -g $RG -n apacheserver1 --query publicIps -o tsv); echo $IP
ssh -i ~/.ssh/apacheserver1-key ubuntu@$IP 'sudo apt-get update -qq && sudo apt-get install -y -qq apache2 && sudo systemctl enable --now apache2 && systemctl is-active apache2'
```

**Checkpoint 1.** `curl -s -o /dev/null -w '%{http_code}' http://$IP/` prints 200 and the browser
shows *Apache2 Ubuntu Default Page*. Screenshot 1.

If `az vm create` returns `SkuNotAvailable` or `QuotaExceeded`, read the sandbox table in
`../multi-cloud-ansible-deployment/README.md`: eastus plus Standard_D2s_v4 is the combination
that worked; `az vm list-usage -l eastus -o table` shows the per-family quota.

## Part 2. Capture the disk (15 min)

**Step 6: make the OS cloud-neutral first.** The AWS variant has the same step, with `Ec2` in place
of `Azure` in the datasource list and no agent to disable.
An Azure Ubuntu image boots on Compute Engine, but three things in it assume Azure: cloud-init
is pinned to the Azure datasource and polls `169.254.169.254` forever, netplan binds `eth0` to
the Azure NIC's MAC address (on GCE the NIC is `ens4`), and fstab runs fsck on the root
filesystem at boot, which fails on a disk captured while running and drops to the emergency
shell. On the VM:

```bash
ssh -i ~/.ssh/apacheserver1-key ubuntu@$IP
printf 'datasource_list: [ GCE, Azure, None ]\n' | sudo tee /etc/cloud/cloud.cfg.d/99-multicloud.cfg
printf 'network:\n  version: 2\n  ethernets:\n    any:\n      match:\n        name: "e*"\n      dhcp4: true\n' | sudo tee /etc/netplan/60-any-nic.yaml
sudo chmod 600 /etc/netplan/60-any-nic.yaml
sudo sed -i -E 's/(\s)0 1\s*$/\10 0/' /etc/fstab      # fsck pass 0 on / and /boot/efi
sudo systemctl disable walinuxagent.service
sudo cloud-init clean --logs                            # next boot is a fresh instance
```

**Steps 7 and 8: capture, check, compress.** Attach a scratch data disk, then on the VM:
drop the block caches, freeze the root filesystem, take a raw copy of the OS disk straight from
the device (`-T none`, sparse, about 2 GB on disk), thaw, confirm the copy carries the same
superblock as the live root, run `e2fsck` on the copy, compress it to qcow2 and publish it over
the web server:

```bash
az vm disk attach -g $RG --vm-name apacheserver1 --name apacheserver1-scratch --new --size-gb 10 --sku Standard_LRS --lun 0
ssh -i ~/.ssh/apacheserver1-key ubuntu@$IP
sudo apt-get install -y qemu-utils
DEV=$(readlink -f /dev/disk/azure/scsi1/lun0); sudo mkfs.ext4 -F $DEV; sudo mkdir -p /mnt/img; sudo mount $DEV /mnt/img
ROOT=$(readlink -f /dev/disk/azure/root)
sudo sh -c "sync; echo 3 > /proc/sys/vm/drop_caches; blockdev --flushbufs $ROOT; fsfreeze -f /; qemu-img convert -T none -O raw $ROOT /mnt/img/disk.raw; fsfreeze -u /"
LOOP=$(sudo losetup -fP --show /mnt/img/disk.raw)
sudo dumpe2fs -h ${ROOT}1 | grep "Block count"; sudo dumpe2fs -h ${LOOP}p1 | grep "Block count"   # must be equal
sudo e2fsck -fy ${LOOP}p1; sudo losetup -d $LOOP
sudo qemu-img convert -c -O qcow2 /mnt/img/disk.raw /mnt/img/disk.qcow2 && sudo rm /mnt/img/disk.raw
sudo chmod 644 /mnt/img/disk.qcow2; sudo ln -sf /mnt/img/disk.qcow2 /var/www/html/disk.qcow2
ls -l /mnt/img/disk.qcow2; md5sum /mnt/img/disk.qcow2; exit
```

Why the cache flush and `-T none`: Linux keeps a separate page cache for the whole-disk device
(`/dev/sda`) and for the partition (`/dev/sda1`) the filesystem writes through. Tools that read
the whole disk at first boot (growpart, blkid) leave the *pre-resize* superblock in the
whole-disk cache, and a plain `qemu-img convert /dev/sda` can serve that stale page: the copy
then claims a 2 GB filesystem on a 30 GB partition, `e2fsck` "repairs" it by clearing every
inode beyond 2 GB, and the target VM panics with `can't execute '/sbin/init'`. Dropping the
caches and reading with O_DIRECT gives an exact copy; the two `Block count` lines prove it.

Why the `e2fsck`: the copy is crash-consistent, so the journal replays, and some copies still
report *Resize inode not valid* (Ubuntu cloud images are grown online at first boot). Checking
the copy (never the live root) is where you first see that a migrated disk is a *copy you own*,
not the original.

**Checkpoint 2.** About 1 GB of qcow2 with its md5, reachable at `http://$IP/disk.qcow2`.
Screenshot 2. Azure's `/dev/disk/azure/...` symlinks are the one difference from AWS, where the
devices are `/dev/nvme0n1` and `/dev/nvme1n1` on a t3.micro (`xvda` and `xvdf` on a t2). `fsfreeze` blocks writes to `/` for the five minutes of
the raw copy; your SSH session may pause until the thaw, which is expected.

`scripts/00-azure-all-in-one.sh` does Parts 1 and 2 end to end (laptop with `az login`, or
`RG=<group> bash scripts/00-azure-all-in-one.sh` in the sandbox's Cloud Shell).

## Part 3. Transfer the image to Google Cloud (20 min)

Do this part on your laptop (`gcloud auth login`, `brew install qemu gnu-tar`) or in **Cloud
Shell** in your GCP project (console → the `>_` icon at the top right), which already has
`gcloud`, `curl`, `tar` and can `apt-get install qemu-utils`.

### Step 9. Enable APIs and create a bucket

```bash
gcloud config set project <PROJECT_ID>
gcloud services enable compute.googleapis.com storage.googleapis.com
B=<PROJECT_ID>-apache-migration
gcloud storage buckets create gs://$B --location=us-central1 --uniform-bucket-level-access
```

### Step 10. Download the image and verify it

```bash
curl -f --retry 10 --retry-all-errors --retry-delay 5 -C - -O http://<AZURE_PUBLIC_IP>/disk.qcow2   # resumable
md5sum disk.qcow2                      # must match Checkpoint 2
```

### Step 11. Remove the public download link in Azure

Back on the Azure VM instance (or in a second SSH session):

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
gcloud compute images create apacheserver-image \
  --source-uri=gs://$B/disk.tar.gz \
  --family=apacheserver \
  --description="Migrated from Azure apacheserver1"
gcloud compute images describe apacheserver-image --format="value(name,status,diskSizeGb)"
```

Status must be `READY`. Creation takes 1 to 3 minutes.

### Step 15. Launch the VM from the image

```bash
gcloud compute instances create apacheserver-gcp \
  --zone=us-central1-a --machine-type=e2-micro \
  --image=apacheserver-image --tags=http-server
```

No `--boot-disk-size`: the image is 31 GB (the Azure OS disk is 30 GB) and Compute Engine refuses
a boot disk smaller than the image. Note the `EXTERNAL_IP` in the output. The `http-server` tag is what the firewall
rule in the next part matches on.

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
IP=$(gcloud compute instances describe apacheserver-gcp --zone=us-central1-a \
      --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
curl -s -o /dev/null -w '%{http_code}\n' http://$IP/      # expect 200
```

Open `http://<EXTERNAL_IP>` in a browser. The Apache default page should load.
The first HTTP 200 takes about two minutes: systemd waits 90 s for a Hyper-V KVP device that GCE
does not have, so HTTP 000 for the first two minutes is normal.

### Step 18. Validate from the inside

The migrated disk does not yet contain Google's guest agent, so metadata SSH keys
are not applied until you install it. Use the Azure key pair, which the image still
trusts, to get in the first time. From the machine that holds `~/.ssh/apacheserver1-key`:

```bash
ssh -i ~/.ssh/apacheserver1-key ubuntu@<EXTERNAL_IP>
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

After the guest agent is installed, `gcloud compute ssh ubuntu@apacheserver-gcp
--zone=us-central1-a` works. Expect a host-key-changed warning the first time,
because the guest environment regenerates SSH host keys.

**Checkpoint 3:** screenshot the browser page on the GCP external IP, and the
output of `systemctl status apache2` from inside the GCP VM.

---

## Part 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `az vm create` returns `SkuNotAvailable` or `QuotaExceeded` | No capacity or quota for that size in that region | eastus with `Standard_D2s_v4` (see Part 1); `az vm list-usage -l eastus -o table` |
| `Requested disk size cannot be smaller than the image size` | `--boot-disk-size` below the 31 GB image | Create the VM without `--boot-disk-size` (Step 15) |
| HTTP 000 for the first two minutes on the GCP IP | systemd waits 90 s for the Hyper-V `hv_kvp` device | Normal; wait, then check the serial console for `DataSourceGCE` |
| `qemu-img: command not found` | Package missing | `sudo apt install -y qemu-utils` |
| `No space left on device` during convert | Writing to the root disk | Write to the mounted scratch volume `/mnt/img` |
| `curl -O` in Cloud Shell gets 404 | Symlink not created, or wrong IP | Re-run Step 8, confirm with `curl -I` |
| `images create` fails: "not a valid tar" | Wrong tar format or file not named `disk.raw` | Repeat Step 12 exactly, GNU tar `--format=oldgnu` |
| Browser times out on GCP IP | No firewall rule, or VM lacks the `http-server` tag | Step 16, then `gcloud compute instances add-tags` |
| `Permission denied (publickey)` with `gcloud compute ssh` | Guest agent not installed yet | Step 18, or SSH with the Azure key |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Host keys regenerated by guest environment | `ssh-keygen -R <EXTERNAL_IP>` and retry |
| `Required 'compute.networks.updatePolicy' permission` | Your account cannot create firewall rules in this project | Use a project where you have Compute Network Admin |

---

## Part 7. Clean up (10 min)

Azure: `bash scripts/05-cleanup-azure.sh` deletes the resource group `apacheserver1-rg` whole
(on the Vocareum sandbox it instead empties the pre-created group of the VM and its NIC,
public IP, NSG, VNet and both disks). GCP: `bash scripts/06-cleanup-gcp.sh jackson-isiko`
deletes the VM, image, bucket and the `allow-ssh-admin` rule, and `allow-http` only when no other
`http-server` VM (such as the AWS variant's `apacheserver-gcp-aws`) is left in the project. Both list first and ask; `-n` lists only,
`-y` skips the prompt. `bash scripts/rollback-lab1.sh jackson-isiko -y` runs both where both
CLIs are signed in.

## Deliverables (Canvas 1.5)

Submit a single PDF or document with:

1. Checkpoint 1: Apache page on the Azure public IP.
2. Checkpoint 2: image size and md5 hash from Azure, and the matching md5 after the download.
3. Checkpoint 3: Apache page on the GCP external IP, and `systemctl status apache2` from inside the GCP VM.
4. The cleanup proof: `05-cleanup-azure.sh -n` and `06-cleanup-gcp.sh <PROJECT_ID> -n` both reporting nothing to delete.
5. Three to five sentences: what in the image had to change for the VM to run well on Google Cloud, and what would be different if you had used the Migrate to VMs connector instead.

## Scripts in this folder

| Script | Where to run | What it does |
|---|---|---|
| `scripts/deploy-lab1.sh <PROJECT_ID>` | Laptop with az, gcloud, qemu-img, GNU tar | Parts 1 to 5 end to end with a timing table |
| `scripts/verify-lab1.sh <PROJECT_ID>` | Same | What exists on each side, HTTP codes, and the `migrated-from.txt` marker served by both VMs |
| `scripts/rollback-lab1.sh <PROJECT_ID> [-n] [-y]` | Same | Both teardowns (same as `destroy-lab1.sh`) |
| `scripts/00-azure-all-in-one.sh` | Laptop with az, or Azure Cloud Shell | Parts 1 and 2: VM, Apache, OS preparation, scratch disk, frozen capture, qcow2 published over HTTP |
| `scripts/04-gcp-import-and-launch.sh <PROJECT_ID> <AZURE_PUBLIC_IP>` | Laptop with gcloud and qemu-img, or Cloud Shell | Parts 3 to 5 |
| `scripts/05-cleanup-azure.sh [-n] [-y]` | Laptop with az, or Azure Cloud Shell | Azure teardown by name |
| `scripts/06-cleanup-gcp.sh <PROJECT_ID> [-n] [-y]` | gcloud | GCP teardown by name |
| `scripts/destroy-lab1.sh <PROJECT_ID> [-n] [-y]` | Machine with both CLIs | Both teardowns |

## Instructor notes

### Instructor run (2026-10-26, own accounts: Azure *Ensign College - School Card*, GCP `jackson-isiko`)

Run from the laptop with `bash scripts/deploy-lab1.sh jackson-isiko` (az and gcloud signed in,
qemu-img and GNU tar from Homebrew). Third attempt of the day; the first two found the two
Azure-specific problems that are now Step 6 and the capture procedure.

| Checkpoint | Result |
|---|---|
| 1. Azure VM | `apacheserver1`, eastus, Standard_D2s_v4, 13.92.28.158; NSG: 22 from the laptop IP only, 80 from anywhere; `HTTP=200`, *Apache2 Ubuntu Default Page* |
| 2. Capture | Step 6 prep (`PREP_DONE`), raw copy under `fsfreeze`, `e2fsck -fy` on the loop device, qcow2 of about 1 GB published at `/disk.qcow2` |
| 3. Transfer | download 1.6 min, convert and tar 1.5 min, upload 0.5 min from the laptop |
| 4. GCP | image `apacheserver-image` (31 GB, READY), VM `apacheserver-gcp` e2-micro 34.63.136.21, rule `allow-http` |
| 5. Validate | `http://34.63.136.21/` → 200, same Apache page; serial console: `cloud-init ... finished ... Datasource DataSourceGCE`, no fsck failure, no emergency shell; `migrated-from.txt` served from GCP names the Azure VM |
| Timing | Azure build and capture 6 min, transfer and GCP launch 9 min, total 16 min (the script prints this table) |
| Rollback | `rollback-lab1.sh jackson-isiko -y`: resource group deleted whole; GCP VM, image, bucket and rule deleted |

**Rerun 2026-10-27 (the day before class), after the stale-superblock fix:** Azure VM
20.25.42.134, `superblock block count: live=7836155 copy=7836155`, GCP VM `apacheserver-gcp`
35.254.70.255 → HTTP 200 and the Azure marker file served from GCP; serial console
`cloud-init ... finished ... Datasource DataSourceGCE` at 114 s (systemd waits 90 s for a
Hyper-V KVP device that does not exist on GCE, which is why the first HTTP 200 takes about
two minutes). Timing: Azure build and capture 6 min, transfer and launch 12 min (the download
ran next to the AWS variant's), total 18 min. The AWS variant ran the same afternoon in the
same project (`apacheserver-gcp-aws`, 34.72.104.58), so both migrated servers can be shown
side by side.

What the failed attempts taught (all are now in the guide and the scripts):

1. **Attempt 1, plain capture:** the GCE VM reached systemd, then *File System Check on Root
   Device* failed and cloud-init polled the Azure metadata service for ever (`azure.py ...
   Polling IMDS failed attempt 218`). No network, no Apache. Fix: Step 6 (datasource order,
   netplan for any NIC, fstab pass 0, walinuxagent off, `cloud-init clean`).
2. **Attempt 2, frozen capture without repair:** boot stopped in the initramfs:
   `cloudimg-rootfs: Resize inode not valid. UNEXPECTED INCONSISTENCY`. Every Ubuntu cloud
   image that was grown online at first boot carries this; the live VM never notices, a copy
   does. Fix: `e2fsck -fy` on the raw copy through a loop device before compressing.

3. **2026-10-27, the day before class, the same capture failed a different way:** the GCE VM
   panicked at `run-init: can't execute '/sbin/init'` after a *clean* fsck. The copy's
   superblock said 548,091 blocks (the 2 GB cloud image) while the live root has 7,836,155
   (29.9 GB): `qemu-img` had read the whole-disk device's page cache, which still held the
   superblock from before the first-boot resize, and `e2fsck -fy` then cleared every inode
   above 2 GB, systemd included. The 2026-10-26 run only passed because that cache had been
   evicted. Fix, now in the guide and script: `echo 3 > drop_caches`, `blockdev --flushbufs`,
   `qemu-img convert -T none` (O_DIRECT), and the script refuses to continue
   (`CAPTURE_STALE`) if the copy's block count differs from the live root's.

Also found: Compute Engine refuses a boot disk smaller than the image (31 GB), so the VM is
created without `--boot-disk-size`; and cloud-init on GCE renames the host to the instance name,
so "same server" is proven with the marker file, not the hostname.

Evidence: `images/azure-resource-group.png` (the four resources in `apacheserver1-rg`),
`images/azure-apache-default-page.png` (before, on Azure), `images/gcp-apache-migrated-page.png`
(after, on GCP).

**Evening rerun (2026-10-27, from scratch, left running for class):** `../lab1-migration-workflow/deploy-lab1.sh azure jackson-isiko` built and captured in 16 min (VM 20.169.154.143, `live=7836155 copy=7836155`), then the slow home uplink (2 MiB/s) stretched the upload to 22 min and `gcloud compute images create` returned `gcloud crashed (ReadTimeout)` after 300 s although the image was READY on the server. The script stopped there; the VM was created by hand and answered at 35.253.21.229 after 1.9 min (cloud-init 110 s, `DataSourceGCE`). The laptop's public IP changed again mid-run, so Step 11 needed the `allow-ssh-admin` rule re-pointed first. Script changes from this run: Step 10 downloads with `curl --retry 10 -C -` (resumable), and Steps 14 and 15 poll the image for `READY` and the VM for `RUNNING` after the create calls, so a client-side timeout no longer aborts the import.

### Demo plan (Tuesday)

- 5:00 PM: `bash scripts/deploy-lab1.sh jackson-isiko 2>&1 | tee ~/lab1.log` (16 to 25 min).
  If the laptop's public IP changes mid-run (carrier NAT, VPN), the script now re-points the
  SSH rule by itself; a rerun of the same command resumes on the existing VM.
- In class: portal resource group and GCP VM list side by side; `bash scripts/verify-lab1.sh
  jackson-isiko` on screen; open both IPs; `curl http://<GCP_IP>/migrated-from.txt`; then
  `gcloud compute instances get-serial-port-output apacheserver-gcp --zone us-central1-a | grep -i
  "datasource\|fsck"` to show the two things Step 6 fixed.
- After class: `bash scripts/rollback-lab1.sh jackson-isiko -y`, then the verify script should
  report nothing on either side.

### Notes

- The Azure side was driven through the browser (Playwright Firefox against the portal's Cloud
  Shell) on the first attempt; once the laptop's `az` was signed in with
  `az login --use-device-code --tenant 0c4f1382-c36f-4783-840b-a091deb8510c`, everything ran
  locally. Cloud Shell is still the path for the Vocareum sandbox, which blocks the laptop CLI.
- The GCP target project is `jackson-isiko`; firewall rules work there (unlike the Vocareum GCP
  role), so the `allow-http` rule needs no workaround.
- Students on the Vocareum Azure sandbox: `RG=<pre-created group> bash scripts/00-azure-all-in-one.sh`
  in Cloud Shell, then `04-gcp-import-and-launch.sh` in GCP Cloud Shell (which can
  `apt-get install qemu-utils`), exactly as in the AWS variant.
