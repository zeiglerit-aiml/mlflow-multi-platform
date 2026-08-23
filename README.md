# Agentic Multi-Model MLflow Platform

A local/GCP/Azure MLflow platform for heterogeneous model training, registration, champion/challenger lifecycle management, model-serving pools, and an agentic relay API. The Python application is shared; cloud infrastructure and deployment values remain isolated by provider.

## One build entry point

```bash
./build.sh --local
./build.sh --cloud=gcp --project=my-gcp-project
./build.sh --cloud=azure --subscription=00000000-0000-0000-0000-000000000000
```

`--cloud=gpc` is accepted as an alias for `gcp`.

GitOps deployment:

```bash
./build.sh --cloud=gcp \
  --project=my-gcp-project \
  --gitops \
  --git-repo=https://github.com/example/agentic-ml-platform.git

./build.sh --cloud=azure \
  --gitops \
  --git-repo=https://github.com/example/agentic-ml-platform.git
```

Run `./build.sh --help` for all parameters and `--destroy` behavior.

## Repository organization

```text
build.sh                       Unified local/GCP/Azure entry point
compose.yaml                   Local MLflow platform

common/
├── docker/                    Shared MLflow/API/model-serving images
├── helm/platform/             Shared Kubernetes application chart
└── k8s/                       Common Kubernetes primitives

gcp/
├── terraform/                 GKE, Cloud SQL, GCS, Artifact Registry, IAM
├── helm/values.yaml           GCP-specific chart configuration
└── gitops/                    Argo CD root Application

azure/
├── terraform/                 AKS, PostgreSQL, Blob, ACR, identity, networking
├── helm/values.yaml           Azure-specific chart configuration
├── gitops/                    Argo CD root Application
└── apim/                      Optional public API policy

src/aioffice/                  Shared FastAPI, MCP, planner, router, comparison
services/                      Dependency-isolated model-serving code
training/                      MLflow training and registration pipeline
notebooks/                     Executable Jupyter learning/prototype edition
```

## Local mode

`./build.sh --local` starts:

| Service | Address | Purpose |
|---|---|---|
| MLflow | `http://localhost:5000` | Tracking, registry, UI, artifact proxy |
| Agentic API | `http://localhost:8000/docs` | REST/SSE inference and comparison |
| Model service | `http://localhost:8010/docs` | Development serving pool |
| MinIO | `http://localhost:9001` | S3-compatible local artifact storage |
| PostgreSQL | internal only | MLflow metadata and registry backend |

The local architecture deliberately mirrors cloud separation: PostgreSQL stores metadata, MinIO stores large artifacts, and the MLflow server proxies artifact access.

Stop without deleting data:

```bash
./build.sh --local --destroy
```

## GCP mode

The GCP implementation provisions:

- VPC-native GKE Standard cluster
- Workload Identity Federation for GKE
- Cloud SQL for PostgreSQL 16 on a private address
- Cloud SQL Auth Proxy sidecar for MLflow
- Versioned/private GCS artifact bucket
- Artifact Registry Docker repository
- Dedicated MLflow Google service account and scoped IAM
- Shared Helm deployment or Argo CD GitOps

Prerequisites: `gcloud`, `terraform`, `kubectl`, `helm`, and Docker. Authenticate with `gcloud auth login` and Application Default Credentials before running.

## Azure mode

The Azure implementation preserves the previous Azure design under `azure/`, implemented with the same Terraform workflow as GCP, and provisions:

- AKS with OIDC and Microsoft Entra Workload ID
- Azure Database for PostgreSQL Flexible Server on a delegated subnet
- private PostgreSQL DNS
- private Blob Storage container for MLflow artifacts
- Azure Container Registry
- user-assigned workload identity and Blob RBAC
- Log Analytics integration
- shared Helm deployment or Argo CD GitOps

Prerequisites: `az`, `kubectl`, `helm`, `jq`, OpenSSL, and Docker. Authenticate with `az login` before running.

## Application APIs

```text
POST /api/v1/infer
POST /api/v1/tasks/{task}/compare
POST /api/v1/algorithms/{algorithm}/predict
POST /api/v1/models/{model_name}/predict
POST /api/v1/models/{model_name}/versions/{version}/predict
GET  /api/v1/models
```

The public API is task/model oriented. Model framework dependencies stay in their serving-pool images rather than the API/MCP control plane.

## MLflow lifecycle

The operational identity hierarchy is:

```text
business task → model family → algorithm → framework → artifact version → role
```

Example model URIs:

```text
models:/customer-churn-logistic@champion
models:/customer-churn-xgboost@challenger
models:/customer-churn-pytorch@canary
```

Only champion, challenger, canary, previous champion, and an optional experimental version should remain actively deployable. Historical runs and artifacts remain retained for lineage and reproducibility.

## Manual Python development

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e '.[dev,mcp,ml]'
pytest
uvicorn aioffice.main:app --reload --port 8000
```

## Production notes

- MLflow is `ClusterIP` and private by default; use an authenticated gateway before making the UI public.
- The agentic API is a `LoadBalancer` in the starter values. Add cloud gateway, TLS, DNS, WAF, and identity policy before production exposure.
- Build scripts bootstrap runtime secrets. For mature GitOps, replace this with External Secrets/Secret Store CSI and managed database identity.
- Terraform state must be moved to protected remote backends before team use.
- Pin and scan all production images; example version tags should be reviewed during upgrades.

See `docs/` for architecture, routing, dependency isolation, frontend behavior, model lifecycle, and cloud deployment details.
