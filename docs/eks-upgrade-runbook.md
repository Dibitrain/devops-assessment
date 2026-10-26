# EKS upgrade runbook (zero downtime)

EKS upgrades one minor version at a time (1.35 → 1.36, never 1.35 → 1.37). An upgrade has three parts,
done in this order: **control plane → add-ons → nodes**. Only the node step moves application pods, and
that is the step the workload is built to survive.

## Why the API stays up during an upgrade

| Mechanism | Where | What it prevents |
|---|---|---|
| ≥ 2 replicas, spread across zones and nodes | `deploy/helm/accounts-api/templates/deployment.yaml` | One node drain taking out every pod |
| PodDisruptionBudget `minAvailable: 1` | `templates/pdb.yaml` | A drain evicting the last ready pod |
| Rolling update `maxUnavailable: 0, maxSurge: 1` | `templates/deployment.yaml` | Capacity dropping during a rollout |
| ALB pod readiness gate | namespace label in `infra/terraform/platform/k8s.tf` | A new pod counting as Ready before the ALB sends it traffic |
| `/ready` fails on SIGTERM + preStop sleep 15s + 30s deregistration delay | `src/server.ts`, chart values, Ingress annotations | In-flight requests being cut when a pod is evicted |
| Managed node group `max_unavailable_percentage = 33` | `infra/terraform/platform/eks.tf` | More than a third of nodes being replaced at once |

## 1. Prepare (a week before)

1. **Read the release notes** for the target version: [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) and the upstream changelog. Note removed APIs and changed defaults.
2. **Check EKS upgrade insights.** EKS scans the cluster's audit log for calls to deprecated APIs:
   ```bash
   aws eks list-insights --cluster-name accounts-api --filter categories=UPGRADE_READINESS
   aws eks describe-insight --cluster-name accounts-api --id <insight-id>
   ```
3. **Scan manifests for removed APIs**, both live and in the chart:
   ```bash
   pluto detect-helm --target-versions k8s=v1.36.0
   helm template deploy/helm/accounts-api | pluto detect - --target-versions k8s=v1.36.0
   ```
4. **Check add-on compatibility.** Managed add-ons (`vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent`) use `most_recent = true`, so Terraform picks the version built for the new Kubernetes version. For the Helm add-ons in `addons.tf` (ALB controller, External Secrets, metrics-server, kube-prometheus-stack, ExternalDNS), check each chart's supported Kubernetes range and bump `local.chart_versions` in a separate PR *before* the cluster upgrade.
5. **Confirm headroom**: the node group needs room for one surge node, and every PDB must be satisfiable (`kubectl get pdb -A`: `ALLOWED DISRUPTIONS` ≥ 1 everywhere).
6. **Rehearse** on a non-production cluster (or locally on kind, see below).

## 2. Upgrade the control plane

Change one variable and ship it through the normal pipeline (PR → plan → approval → apply):

```hcl
# infra/terraform/platform/env/<env>.tfvars
kubernetes_version = "1.36"
```

`terraform apply` calls `UpdateClusterVersion`. EKS replaces API servers behind its load balancer one at
a time; the Kubernetes API stays available and **running pods are untouched**. It takes 10–20 minutes.
The control plane cannot be downgraded afterwards, which is why step 1 matters.

The same apply also updates the managed add-ons to versions built for 1.36.

## 3. Roll the nodes

The managed node group follows the cluster version: the same apply (or the next one) updates the
launch template to the new EKS-optimized AL2023 AMI, and EKS performs a rolling replacement:

1. Launch new nodes (surge) on the new version.
2. Cordon and drain old nodes, at most 33% at a time, **respecting PodDisruptionBudgets**.
3. Evicted pods are rescheduled onto new nodes. Readiness gates hold the old pod's replacement out of the ALB until it is healthy, and the evicted pod drains its connections before exiting.
4. Terminate the old nodes.

Watch it:

```bash
kubectl get nodes -L eks.amazonaws.com/nodegroup -o wide -w
kubectl -n accounts-api get pods -o wide -w
aws eks describe-update --name accounts-api --update-id <id>
```

**Alternative for risky upgrades (blue/green node groups):** add a second node group on the new version
in `eks_managed_node_groups`, apply, cordon the old group, drain it node by node, then remove it in a
second apply. This gives an instant fallback, at the cost of temporarily running both groups.

## 4. Verify

- Grafana *Accounts API* dashboard: 5xx ratio flat, p95 latency unchanged through the window.
- No `AccountsApiHighErrorRate` / `AccountsApiTargetDown` alerts fired.
- `kubectl get nodes` all on the new version; `kubectl get pods -A` with no restarts or pending pods.
- Smoke test: `curl https://<host>/health`.

## 5. Roll back

- **Nodes:** if the new AMI misbehaves, revert the node group to the previous AMI release (or switch traffic back to the blue node group) and re-apply.
- **Control plane:** cannot be rolled back. The recovery path for a broken control plane upgrade is a new cluster on the old version built from the same Terraform (see *Backup and recovery* in SOLUTION.md), then redeploy the last good image from ECR. This is why the rehearsal is mandatory.

## Rehearsal on kind

The drain behavior can be rehearsed for free on the local three-zone kind cluster (`scripts/kind-up.sh`),
draining each worker while traffic runs:

```bash
for node in $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name); do
  kubectl drain "${node#node/}" --ignore-daemonsets --delete-emptydir-data --timeout=180s
  kubectl uncordon "${node#node/}"
done
```

The result of running this under load is recorded in [WALKTHROUGH.md](WALKTHROUGH.md#step-9--prove-it-locally).
