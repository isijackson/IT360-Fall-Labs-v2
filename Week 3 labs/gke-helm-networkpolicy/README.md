# Week 3 Lab 1: Kubernetes on GKE with Helm and a NetworkPolicy (Use Case 3.2, Silver Lake Credit Union)

Canvas assignment **3.2 Team Lab 1: Kubernetes Cluster Setup on Google Kubernetes Engine
(GKE)**, 40 points, team submission.

Silver Lake Credit Union is moving its public loan calculator onto GKE. Last year's audit
finding: "public-facing workloads must not be able to reach internal workloads on the same
network." The infrastructure manager wants the calculator to run as a managed release that
can be rolled back in one command, and a NetworkPolicy that **provably** blocks pod-to-pod
traffic the calculator does not need. A blocked connection attempt is the evidence.

> **Where to run it.** Students: the **Vocareum Google Cloud lab** from Canvas is free and
> can create GKE Autopilot clusters; do the whole lab in its Cloud Shell, which has `kubectl`
> and `helm` preinstalled. Anyone with a personal project can run the same steps or the
> scripts in `scripts/`.

**Click-by-click handout:** `Week 3 Lab 1 Click-by-Click - Kubernetes on GKE with Helm and a NetworkPolicy.docx` in this folder is the screenshot-driven version of this guide: every console step has a numbered screenshot of where to click (`images/clicks/`) with a "What you see" description, every terminal step shows real output, and a verification-commands section lists the checks that prove the deployment. It covers GKE console screenshots (clusters, Autopilot create form, cluster detail, workloads, services) and the real kubectl, helm and probe output of the 2026-10-29 run in us-east1. Generated with `docgen/build-click-guide.js`.

## Learning objectives

1. Create a GKE Autopilot cluster and connect `kubectl` to it.
2. Deploy NGINX with a Deployment manifest and watch Kubernetes replace a deleted pod.
3. Install the same app as a Helm release, upgrade it, and roll it back with one command.
4. Write a NetworkPolicy that admits only pods labelled `role=frontend`.
5. Prove the policy with a blocked probe and an allowed probe.

## Naming used in this guide

| Item | Value |
|---|---|
| Cluster | `silverlake-public`, Autopilot, region `us-central1` |
| kubectl deployment | `loan-calc`, 3 replicas of `nginx:1.27` |
| Helm release | `loan-calc` from chart `loan-calc-chart` |
| Policy | `loan-calc-frontend-only` |

## Part 1. Cluster (cluster engineer, 15 min, mostly waiting)

```bash
gcloud container clusters create-auto silverlake-public --region us-central1
gcloud container clusters get-credentials silverlake-public --region us-central1
kubectl get nodes
```

Autopilot may show no nodes until a workload is scheduled; that is normal.
**Validation 1.** `gcloud container clusters list` shows `silverlake-public RUNNING`.

## Part 2. Deploy with kubectl (deployment engineer, 10 min)

`k8s/nginx-deployment.yaml` in this folder pins a current image (the Canvas file pins
`nginx:1.14.2` from 2018):

```bash
kubectl apply -f k8s/nginx-deployment.yaml
kubectl rollout status deployment/loan-calc
kubectl get deployments
kubectl get pods
```

**Validation 2.** Three pods `Running`. Screenshot 1.
**Checkpoint.** `kubectl delete pod <one pod name>` then `kubectl get pods` again; a
replacement appears within seconds. Explain to the room who restored it (the ReplicaSet
behind the Deployment, reconciling to `replicas: 3`).

Optional per Canvas: `kubectl expose deployment loan-calc --type=LoadBalancer --name=loan-calc-public --port=80`
and open the EXTERNAL-IP once `kubectl get service loan-calc-public` shows it.

## Part 3. Manage with Helm (release engineer, 20 min)

```bash
helm version
helm create loan-calc-chart
sed -i.bak 's/^replicaCount: .*/replicaCount: 2/' loan-calc-chart/values.yaml
sed -i.bak 's/^  tag: .*/  tag: "1.27"/' loan-calc-chart/values.yaml
helm install loan-calc ./loan-calc-chart
helm list
kubectl get all
```

`sed -i.bak` works with GNU sed (Cloud Shell) and BSD sed (macOS) alike; plain `sed -i` fails on
macOS. It leaves a `values.yaml.bak` next to the file, which Helm ignores.

Upgrade and roll back, which is the one-command rollback the manager asked for:

```bash
sed -i.bak 's/^replicaCount: .*/replicaCount: 3/' loan-calc-chart/values.yaml
helm upgrade loan-calc ./loan-calc-chart
helm history loan-calc
helm rollback loan-calc 1
helm history loan-calc
```

**Validation 3.** `helm history` shows revisions 1 (superseded, "Install complete"), 2
(superseded, "Upgrade complete") and 3 (deployed, "Rollback to 1"); only one revision is ever
`deployed`. Screenshot 2.
**Checkpoint.** Which revision is live right now? `helm history loan-calc | grep deployed`.

## Part 4. NetworkPolicy with proof (security engineer, 20 min)

The Canvas policy allows ingress from any pod in the namespace. The auditor needs tighter:
only pods labelled `role=frontend` may reach the calculator. `k8s/network-policy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: loan-calc-frontend-only
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: loan-calc-chart
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
```

```bash
kubectl apply -f k8s/network-policy.yaml
kubectl get networkpolicy
SVC=$(kubectl get svc -l app.kubernetes.io/instance=loan-calc -o jsonpath='{.items[0].metadata.name}')
# negative test: no label, must time out
kubectl run probe --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=5 http://$SVC
# positive test: labelled, must print the nginx HTML
kubectl run probe-ok --rm -it --image=busybox:1.36 --restart=Never --labels=role=frontend -- wget -qO- --timeout=5 http://$SVC
```

**Validation 4.** The first prints `wget: download timed out`; the second prints the NGINX
welcome HTML. Around those lines GKE prints notices that are normal, not errors: the
Autopilot resources warning, `All commands and output from this session will be recorded in
container logs...` and `If you don't see a command prompt, try pressing enter.` before the
output, and after the blocked probe `pod "probe" deleted from default namespace` and
`pod default/probe terminated (Error)` (the `wget` exit code is non-zero, and
`--restart=Never` reports it). Screenshot 3: both results in one terminal. That timed-out request is what
the auditor reads.

## Cleanup

```bash
helm uninstall loan-calc
kubectl delete -f k8s/network-policy.yaml -f k8s/nginx-deployment.yaml
gcloud container clusters delete silverlake-public --region us-central1 --quiet
```

Or `bash scripts/rollback-lab3-1.sh <PROJECT_ID>` (`-n` lists, `-y` skips the prompt,
`--keep-cluster` keeps the cluster for Week 4). An idle Autopilot cluster still bills a
control-plane fee of about 73 dollars a month; delete it, and end the Vocareum lab.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Both probes succeed | Policy not enforced | Autopilot enforces it by default; a Standard cluster needs Dataplane V2 at creation. Recreate as Autopilot |
| Pods `Pending` for minutes | Autopilot is provisioning nodes | Wait; `kubectl get events` shows scale-up |
| Cluster creation fails: `does not have enough resources available` | No Autopilot capacity in that region at the moment | Delete the errored cluster, create it again in another region (`REGION=us-east1` for the script) |
| Cluster creation fails with `INTERNAL` | Transient GKE error (2026-10-24, after 25 min) | Delete the errored cluster and create it again |
| `kubectl` times out against the endpoint | The cluster is still PROVISIONING, or the kubeconfig points at a deleted cluster | Wait for RUNNING, run `get-credentials` again |
| `get-credentials` fails | Wrong project | `gcloud config set project <id>` |
| `helm install` says release exists | Earlier attempt | `helm uninstall loan-calc` then retry |
| The probe pod itself is `Pending` | Autopilot needs a node for it | Wait up to 90 s; the timeout only starts once it runs |

## Deliverables (Canvas 3.2)

Screenshots 1 to 3, the NetworkPolicy YAML, `helm list` and `helm history` output, and the
Canvas summary with the Team Collaboration and Documentation section.

## Scripts in this folder

| Script | Where to run | What it does |
|---|---|---|
| `scripts/deploy-lab3-1.sh <PROJECT_ID>` | Cloud Shell or laptop with gcloud, kubectl, helm | Parts 1 to 4 with every validation printed. `REGION=us-east1` picks another region, `CLUSTER=<name>` another cluster name. On a rerun it uninstalls an existing `loan-calc` release first, so `helm history` again reads revisions 1, 2 and 3 |
| `scripts/rollback-lab3-1.sh <PROJECT_ID> [-n] [-y] [--keep-cluster]` | Same | Release, policy, deployment, cluster |
| `k8s/nginx-deployment.yaml`, `k8s/network-policy.yaml` | kubectl | The two manifests |

## Stretch

Add a second NetworkPolicy that blocks all egress from the calculator pods except DNS.
Confirm the pod can no longer reach an outside website.

## What changed in the industry, April to October 2026

- **Kubernetes 1.35 and 1.36.** EKS, AKS and GKE all run 1.35 (1.36 in GKE's Rapid channel in
  September 2026). GKE 1.35 ends cgroup v1 support and moves to containerd 2.0: check old
  images before you upgrade. CNCF's 2026 survey: 82 percent of container users run
  Kubernetes in production.
- **Google Cloud Next 2026 (April):** the Gemini Enterprise Agent Platform replaces Vertex AI
  as the place to build and govern agents, and **GKE Agent Sandbox** (a GKE add-on built on
  the open-source Agent Sandbox controller) runs isolated, stateful, single-replica agent
  workloads at about 300 sandboxes a second per cluster. Your NetworkPolicy proof is the
  kind of isolation evidence that platform asks for.
- **IaC and agents:** the Terraform MCP server went GA in June 2026; Pulumi Neo plans and
  executes changes within guardrails; OpenTofu is the open-licence fork most new projects
  pick. Clusters are increasingly created by an agent from an approved module and reviewed
  by a human.

### Across the providers: managed Kubernetes (October 2026)

| Provider | What it offers for this week |
|---|---|
| AWS | EKS on 1.35 (1.37 available), EKS Auto Mode manages nodes |
| Azure | AKS on 1.35, AKS Automatic |
| Google Cloud | GKE Autopilot (this lab), 1.36 in Rapid, Dataplane V2 enforces NetworkPolicy, GKE Agent Sandbox |
| DigitalOcean | DOKS 1.33: Gateway API on by default, network load balancers by default, Spot GPU node pools in preview (Sept 2026) |
| Oracle Cloud | OKE accepts GitHub OIDC tokens for cluster access and gives pods an OIDC issuer for workload identity |

Market context (Synergy Research, Q2 2026): 143.4 billion dollars in the quarter, up 43 percent; AWS 28, Azure 20, Google 15 percent.

Sources for this section:
- https://cloud.google.com/blog/topics/google-cloud-next/google-cloud-next-2026-wrap-up (Agent Platform, GKE Agent Sandbox)
- https://aws.amazon.com/about-aws/whats-new/2026/01/amazon-eks-distro-kubernetes-version-1-35/
- https://github.com/Azure/AKS/releases
- https://www.pulumi.com/blog/infrastructure-as-code-tools/ (Pulumi Neo; Terraform MCP server GA June 2026)

### AI and automation extension (optional, 30 min)

1. Create the cluster from code instead of the console: `cluster.tf` in `k8s/` is an
   OpenTofu definition of the same Autopilot cluster (`cd k8s && tofu init && tofu apply
   -var project=<id>`), and `tofu destroy -var project=<id>` is the cleanup.
2. Ask an AI assistant with the Terraform MCP server to add a second NetworkPolicy that blocks
   all egress except DNS, as the stretch asks. Apply it and prove it with a probe to an
   outside site.
3. Read the GKE Agent Sandbox overview and answer: what does it add on top of the NetworkPolicy
   you wrote, and which of the auditor's findings would it cover?

## Instructor run (2026-10-24, project afriven)

| Validation | Result |
|---|---|
| 1. Cluster | `silverlake-public` RUNNING in us-central1 (the first create failed with INTERNAL after 25 min; delete and retry took 6) |
| 2. Pods | 3 Running; a deleted pod was replaced in 7 seconds |
| 3. Helm | revisions 1 install, 2 upgrade, 3 *Rollback to 1* deployed |
| 4. Policy | unlabelled probe `wget: download timed out`; `role=frontend` probe got the nginx page |
| Rollback | release, policy, deployment and cluster deleted by `rollback-lab3-1.sh` |

## Instructor notes

- Autopilot is Google's recommended mode and GKE Dataplane V2 enforces NetworkPolicy
  natively, so the proof works without extra flags.
- Debrief: what does Helm give the credit union that `kubectl apply` does not (history and
  rollback)? If the policy had been applied on a cluster whose plugin does not enforce it,
  how would the team have found out (the probe would have succeeded; that is why the lab
  demands the blocked probe as evidence).
