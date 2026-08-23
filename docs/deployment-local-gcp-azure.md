# Deployment modes

## Shared architecture

All modes preserve MLflow's split storage model:

| Concern | Local | GCP | Azure |
|---|---|---|---|
| Metadata/backend | PostgreSQL container | Cloud SQL PostgreSQL | PostgreSQL Flexible Server |
| Artifacts | MinIO | Cloud Storage | Blob Storage |
| Compute | Docker Compose | GKE | AKS |
| Images | Local Docker | Artifact Registry | Azure Container Registry |
| Workload identity | Local credentials | GKE Workload Identity | Entra Workload ID |
| Deployment | Compose | Helm or Argo CD | Helm or Argo CD |

## Local

```bash
./build.sh --local
```

Local mode is intended for development and study. Its fixed credentials must never be reused outside a developer machine.

## GCP

```bash
gcloud auth login
gcloud auth application-default login
./build.sh --cloud=gcp --project=my-project --region=us-central1 --zone=us-central1-a
```

Terraform initially uses local state. Configure a versioned GCS state backend before collaborating. The Cloud SQL instance uses a private address, and the MLflow pod connects through its Cloud SQL Auth Proxy sidecar. GCS access uses Workload Identity rather than service-account key files.

## Azure

```bash
az login
./build.sh --cloud=azure --subscription=<subscription-id> --location=eastus2
```

Terraform creates a delegated PostgreSQL subnet and private DNS. AKS enables its OIDC issuer and Workload Identity. The bootstrap currently places database and Blob connection information into a Kubernetes Secret; move this to Azure Key Vault and the Secrets Store CSI Driver for production GitOps.

## GitOps

The `--gitops` switch installs Argo CD and creates the provider-specific root Application. Before invoking it, push the repository to the URL supplied by `--git-repo`.

```bash
./build.sh --cloud=gcp --project=my-project --gitops --git-repo=https://github.com/me/platform.git
```

The bootstrap owns infrastructure, image publication, and initial runtime-secret creation. Argo CD owns the shared Helm application thereafter.

## Destruction

```bash
./build.sh --local --destroy
./build.sh --cloud=gcp --project=my-project --destroy
./build.sh --cloud=azure --resource-group=agentic-ml-rg --destroy
```

Local destruction retains volumes. GCP Terraform destruction and Azure resource-group deletion are destructive and remove managed platform resources. Artifact buckets/storage accounts use protective settings and may require deliberate cleanup if they contain retained artifacts.
