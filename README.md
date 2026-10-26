# Mono Senior DevOps Engineer Assessment

Simple TypeScript Node.js API exposing health, metrics and account endpoints.

## Assessment Requirments

You have been provided with a simple web service that serves 4 endpoints, you are required to do the following;

1. Add a DOCKERFILE in the repository
2. Provision an EKS cluster on AWS with terraform (you can create a free tier account on AWS)
3. Create a docker image and upload on AWS Elastic container registry using the same Terraform file
4. Deploy the docker image from AWS ECR to the kubernetes cluster
5. Write a CI/CD script for GitHub actions that uses your Terraform file to;

   i. create or updates the docker image and deploy to AWS Elastic container registry 
     ii. deploy the docker images to kubernetes cluster; anytime that there is a push on the default branch (you can make changes to the code to confirm this works)
6. Consider the app is accessible via the public internet, while accounting for security and availability in your architecture (feel free to use other AWS services that to strengthen your solution)

## Bonus Requirements

1. collect `/metrics` with Prometheus (or Grafana Alloy)
2. A plan for upgrading the EKS cluster version with no downtime
3. extend the metric collected and build a reasonable a Grafana dashboard for request rate, error rate and latency, and commit it as JSON
4. A live URL that accessible with the necessary security measures in place for a production public API

## Submission

1. Add a `SOLUTION.md`  or a link to a document covering:
   - **Architecture**: a diagram and a short description
   - **How to run it**: deploy from scratch, and tear down
   - **Decisions and trade-offs**: what you chose, what you rejected, and why
   - **Security and compliance**: how your setup handles least-privilege IAM, secrets, encryption in transit and at rest, and audit logging, and which ISO 27001 / PCI DSS controls it would provide evidence for  (brief is fine and your actual implemention may not cover all but your solution to speak to every technical expectation of your solution)
   - **Backup and recovery**: your suggested RTO/RPO for this service and how you would meet them
   - **Gaps**: what is missing before this is truly production-ready and how you intend to handle this
2.  Share a GitHub repo with your solution
   - Include the updated service
   - Terraform, 
   - Kubernetes manifests/chart
   - workflows
   - dashboard JSON and `SOLUTION.md` or documentation of your solution
3. A live URL is optional
4. Share how you used AI for your solution (if you did)

## Solution

- **[SOLUTION.md](SOLUTION.md)**: architecture, how to deploy and tear down, decisions and trade-offs, security and compliance, backup and recovery, gaps, AI usage.
- **[docs/WALKTHROUGH.md](docs/WALKTHROUGH.md)**: step-by-step account of how each problem was found and solved, with evidence.
- **[docs/eks-upgrade-runbook.md](docs/eks-upgrade-runbook.md)**: zero-downtime EKS upgrade plan.

## How to Run the Application

```bash
npm ci
npm test         # builds, then runs the test suite
npm start        # API on PORT (default 3000), metrics on METRICS_PORT (default 9100)
```

Development (recompiles with tsc and restarts on change):

```bash
npm run dev
```

Container and full local stack (kind + Prometheus + Grafana):

```bash
docker build -t accounts-api:local .
scripts/kind-up.sh
```

### Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | `3000` | Public API port |
| `METRICS_PORT` | `9100` | Internal Prometheus metrics port (never exposed publicly) |
| `API_KEY` | empty | When set, `GET /getAccount` requires a matching `x-api-key` header |
| `TRUST_PROXY_HOPS` | `0` | Reverse proxies in front of the app (`1` behind the ALB) |
| `SHUTDOWN_DELAY_MS` | `5000` | After SIGTERM, keep serving (readiness failing) before draining |
| `SHUTDOWN_TIMEOUT_MS` | `20000` | Force exit if draining takes longer |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn` or `error` (JSON lines on stdout/stderr) |

## Project structure

```text
src/
├── app.ts                 # Public app (controllers + middleware) and the separate metrics app
├── server.ts              # Entry point: starts both listeners, graceful shutdown on SIGTERM
├── config.ts              # Environment configuration
├── logger.ts              # JSON-lines logger
├── controllers/
│   ├── account.controller.ts          # GET /getAccount (API key protected)
│   └── health.controller.ts           # GET /health (liveness), GET /ready (readiness)
├── services/
│   ├── account.service.ts
│   ├── lifecycle.service.ts           # Draining state for readiness
│   └── metrics.service.ts             # Counter, latency histogram, in-flight gauge
├── middleware/
│   ├── api-key.middleware.ts          # Constant-time x-api-key check
│   ├── error-handler.middleware.ts    # 4xx messages pass through, 5xx are generic (details logged)
│   ├── not-found.middleware.ts        # 404 fallback / 405 for non-GET methods
│   ├── request-metrics.middleware.ts  # Metrics by route template + access log
│   └── security-headers.middleware.ts
└── interfaces/
    └── account.ts
test/                      # node:test integration tests against the compiled app
Dockerfile                 # Multi-stage, distroless non-root runtime
infra/terraform/           # bootstrap (state, OIDC, CI roles, CloudTrail) and platform (VPC, EKS, ECR, WAF, add-ons)
deploy/helm/accounts-api/  # Helm chart
deploy/kind/               # Local three-zone cluster definition
observability/             # kube-prometheus-stack values, Grafana dashboard JSON
.github/workflows/         # ci.yml, deploy.yml, destroy.yml
```

## Endpoints

| Endpoint | Port | Description |
| --- | --- | --- |
| `GET /health` | 3000 | Liveness check with uptime |
| `GET /ready` | 3000 | Readiness; returns `503` while the pod is draining |
| `GET /getAccount` | 3000 | All accounts (requires `x-api-key` when `API_KEY` is set) |
| `GET /getAccount?id=66ab443c4d4ac0b1cdf45691` | 3000 | Single account by id (404 if not found) |
| `GET /metrics` | 9100 | Prometheus metrics (internal only) |

Non-GET methods are rejected with `405`, unknown routes with `404`.

## Metrics

Exposed in Prometheus text format at `GET :9100/metrics`:

- Default Node.js process metrics (CPU, memory, event loop lag, GC, ...)
- `http_requests_total{method,route,status_code}`: request counter
- `http_request_duration_seconds{method,route,status_code}`: latency histogram
- `http_requests_in_flight`: concurrent requests

`route` is the matched route template (`/getAccount`), or `unmatched` for unknown paths, so label cardinality is bounded.
