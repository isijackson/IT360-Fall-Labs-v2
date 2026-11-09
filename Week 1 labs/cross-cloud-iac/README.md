# Week 1 add-on: one web server, three clouds, one language (OpenTofu / Terraform)

Both Week 1 labs build Ubuntu VMs by hand or with Ansible. This add-on expresses the **same
server** (Ubuntu 22.04, NGINX, ports 22 and 80, a page that names its cloud) as
infrastructure as code for AWS, Azure and Google Cloud, so a team can create, change and
destroy it with one command per cloud and compare the three providers line by line.

Use it as the automation stretch for Lab 1 (the AWS source VM and the GCP target VM are
both here) and Lab 2 (the two Ansible clients are here too; point the Ansible inventory at
the IPs the `tofu output` prints).

> **Why OpenTofu.** Terraform moved to the BSL licence in 2023 and HashiCorp is now part of
> IBM; OpenTofu is the Linux Foundation fork with the same language and the open licence,
> and it is the usual choice for new projects. Every file here runs unchanged under
> `terraform` as well. In June 2026 HashiCorp also shipped a Terraform MCP server (open
> source, GA) so coding agents can author configurations against approved modules; the
> "AI extension" at the end uses it.

## Layout

```
aws/    main.tf   security group, key pair from your public key, t2.micro, user_data installs NGINX
azure/  main.tf   resource group, VNet, NSG (22, 80), public IP, Standard_D2s_v4, custom_data installs NGINX
gcp/    main.tf   firewall rule, e2-micro, metadata startup-script installs NGINX, SSH key in metadata
scripts/apply.sh    <aws|azure|gcp>   init + apply, prints the public IP and waits for HTTP 200
scripts/destroy.sh  <aws|azure|gcp>   destroy
```

Each configuration takes `ssh_public_key` (the controller's key from Lab 2, or your laptop
key), `name` (default `it360-web`) and `ssh_source_cidr` (default open; set it to
`<your public ip>/32` anywhere that is not a sandbox). Credentials come from the usual CLI
sign-in: `aws configure` or CloudShell, `az login` or the portal Cloud Shell, `gcloud auth
application-default login` (or `GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)`).

## Run it

```bash
cd gcp && tofu init && tofu apply -var project=<PROJECT_ID> -var ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
tofu output public_ip            # open http://<ip>: "served from Google Cloud by it360-web"
tofu destroy -var project=<PROJECT_ID> -var ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
```

`scripts/apply.sh gcp` and `scripts/destroy.sh gcp` wrap exactly that. AWS and Azure work
the same way from a shell where those CLIs are signed in (the Vocareum sandboxes allow the
AWS terminal and the Azure portal Cloud Shell; install `tofu` there with the one-line
installer printed by `scripts/apply.sh`).

**Validation.** `tofu plan` shows the resources before anything is created; `tofu output`
prints the IP; the page says which cloud served it; `tofu destroy` leaves nothing. Compare
the three `main.tf` files: the resource names differ, the shape does not.

## Instructor test (2026-10-25)

`tofu validate` passes for all three. The GCP configuration was applied on project afriven
(3 resources: two firewall rules and the VM at 34.67.60.143), the page answered from
Google Cloud over HTTP, and `tofu destroy` removed all 3. The instructor project is now
`jackson-isiko` (`-var project=jackson-isiko`). AWS and Azure were validated only; since
2026-10-26 the laptop's `az` is signed in to the *Ensign College - School Card* subscription,
so `cd azure && tofu init && tofu apply` is the next thing to try. The AWS side needs the CLI
signed in (run it from CloudShell with the one-line OpenTofu installer).

## AI extension (15 min)

1. Ask an AI CLI (Gemini CLI has a free tier; GitHub Copilot CLI and AWS Kiro CLI are the
   other two) to add a second VM to one of the configurations. Read the diff before you
   apply it; the agent does not know your quota or your budget.
2. Install the Terraform MCP server in that CLI and ask it to rewrite the AWS configuration
   using the registry's `terraform-aws-modules/ec2-instance` module. Compare the
   module-based version with the hand-written one: which would you rather maintain?
3. Debrief: in 2026 every major cloud ships agentic migration tooling (AWS Transform replaced
   Migration Hub for new customers in November 2025; Azure's Copilot migration agent and
   Google's Migration Center with Gemini followed). What would you still want a human to
   check before an agent cut a production server over to another cloud?
