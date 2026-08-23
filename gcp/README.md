# GCP platform

This folder contains only GCP-specific infrastructure and configuration. Shared containers and Kubernetes application resources live in `../common`.

## Provision

```bash
gcloud auth login
gcloud auth application-default login
../build.sh --cloud=gcp --project=<project-id>
```

Terraform creates GKE, private Cloud SQL PostgreSQL, GCS, Artifact Registry, VPC networking, Workload Identity, and narrowly scoped MLflow IAM.

## GitOps

`gitops/root-application.yaml` points Argo CD at the shared Helm chart and injects only GCP-specific values. The root build script renders its placeholders after the repository has been pushed.

## State

Copy `terraform/backend.tf.example` to `backend.tf`, create the state bucket separately, and update its values before team deployment.

References: [MLflow on GCP](https://mlflow.org/docs/latest/self-hosting/deploy-to-cloud/gcp/), [GKE Workload Identity](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/workload-identity), [Cloud SQL from GKE](https://docs.cloud.google.com/sql/docs/postgres/connect-kubernetes-engine).
