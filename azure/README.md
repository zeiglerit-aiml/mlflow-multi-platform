# Azure platform

This folder contains only Azure-specific infrastructure and configuration. Shared containers and Kubernetes application resources live in `../common`.

## Provision

```bash
az login
../build.sh --cloud=azure --subscription=<subscription-id>
```

Terraform creates AKS, private PostgreSQL Flexible Server, Blob Storage, ACR, VNet networking, Entra Workload ID, and Log Analytics.

## GitOps

`gitops/root-application.yaml` points Argo CD at the shared Helm chart and injects Azure-specific values. The optional APIM policy is retained under `apim/` for a later authenticated public gateway.

## State

Copy `terraform/backend.tf.example` to `backend.tf`, create the state storage resources separately, and update its values before team deployment.

References: [MLflow on Azure](https://mlflow.org/docs/latest/self-hosting/deploy-to-cloud/azure/), [AKS Workload Identity](https://learn.microsoft.com/azure/aks/workload-identity-overview), [Azure PostgreSQL managed identity](https://learn.microsoft.com/azure/postgresql/security/security-connect-with-managed-identity).
