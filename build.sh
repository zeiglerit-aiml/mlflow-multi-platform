#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=""
CLOUD=""
ACTION="deploy"
GITOPS="false"

PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"
PLATFORM_NAME="${PLATFORM_NAME:-agentic-ml}"
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"
GIT_REPO_URL="${GIT_REPO_URL:-}"
GIT_REVISION="${GIT_REVISION:-main}"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo dev)}"

usage() {
  cat <<'EOF'
Usage:
  ./build.sh --local [--destroy]
  ./build.sh --cloud=gcp --project=PROJECT_ID [options]
  ./build.sh --cloud=azure [--subscription=ID] [options]

Modes:
  --local                 Docker Compose: MLflow + PostgreSQL + MinIO + app services.
  --cloud=gcp|gpc         Terraform + GKE + Cloud SQL + GCS + Artifact Registry.
  --cloud=azure           Terraform + AKS + PostgreSQL + Blob Storage + ACR.

Common options:
  --name=NAME             Platform prefix. Default: agentic-ml.
  --image-tag=TAG         Default: Git short SHA or dev.
  --gitops                Install Argo CD and create a root Application.
  --git-repo=URL          Required with --gitops.
  --git-revision=REF      Default: main.
  --destroy               Tear down the selected environment.

GCP options:
  --project=ID            Required, or set GCP_PROJECT_ID.
  --region=REGION         Default: us-central1.
  --zone=ZONE             Default: us-central1-a.

Azure options:
  --subscription=ID       Optional if Azure CLI already targets the subscription.
  --resource-group=NAME   Default: <platform-name>-rg.
  --location=LOCATION     Default: eastus2.

Examples:
  ./build.sh --local
  ./build.sh --cloud=gcp --project=my-project
  ./build.sh --cloud=azure --subscription=00000000-0000-0000-0000-000000000000
  ./build.sh --cloud=gcp --project=my-project --gitops --git-repo=https://github.com/me/repo.git
EOF
}

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }

for arg in "$@"; do
  case "$arg" in
    --local) MODE="local" ;;
    --cloud=gcp|--cloud=gpc) MODE="cloud"; CLOUD="gcp" ;;
    --cloud=azure) MODE="cloud"; CLOUD="azure" ;;
    --project=*) PROJECT_ID="${arg#*=}" ;;
    --region=*) REGION="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --subscription=*) AZURE_SUBSCRIPTION_ID="${arg#*=}" ;;
    --resource-group=*) AZURE_RESOURCE_GROUP="${arg#*=}" ;;
    --location=*) AZURE_LOCATION="${arg#*=}" ;;
    --name=*) PLATFORM_NAME="${arg#*=}" ;;
    --image-tag=*) IMAGE_TAG="${arg#*=}" ;;
    --gitops) GITOPS="true" ;;
    --git-repo=*) GIT_REPO_URL="${arg#*=}" ;;
    --git-revision=*) GIT_REVISION="${arg#*=}" ;;
    --destroy) ACTION="destroy" ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $arg" ;;
  esac
done

[[ -n "$MODE" ]] || { usage; fail "Choose --local, --cloud=gcp, or --cloud=azure"; }
[[ "$GITOPS" != "true" || -n "$GIT_REPO_URL" ]] || fail "--git-repo is required with --gitops"
[[ "$PLATFORM_NAME" =~ ^[a-z][a-z0-9-]{1,18}[a-z0-9]$ ]] || \
  fail "--name must be 3-20 lowercase letters, digits, or hyphens and start with a letter"

build_images() {
  local image_prefix="$1"
  local artifact_dependencies="$2"
  docker build --build-arg "ARTIFACT_DEPENDENCIES=$artifact_dependencies" \
    -f "$ROOT_DIR/common/docker/Dockerfile.mlflow" -t "$image_prefix/mlflow:$IMAGE_TAG" "$ROOT_DIR"
  docker build -f "$ROOT_DIR/common/docker/Dockerfile.api" -t "$image_prefix/api:$IMAGE_TAG" "$ROOT_DIR"
  docker build -f "$ROOT_DIR/common/docker/Dockerfile.model-service" -t "$image_prefix/model-service:$IMAGE_TAG" "$ROOT_DIR"
  docker push "$image_prefix/mlflow:$IMAGE_TAG"
  docker push "$image_prefix/api:$IMAGE_TAG"
  docker push "$image_prefix/model-service:$IMAGE_TAG"
}

install_argocd() {
  helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
  helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace --wait
}

local_mode() {
  need docker; need curl
  docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required"
  cd "$ROOT_DIR"
  if [[ "$ACTION" == "destroy" ]]; then
    docker compose down --remove-orphans
    log "Local services stopped; volumes retained. Use 'docker compose down -v' to erase them."
    return
  fi
  log "Building and starting the local platform"
  docker compose up --build -d
  for _ in {1..60}; do
    curl -fsS http://localhost:5000/health >/dev/null 2>&1 && break
    sleep 2
  done
  curl -fsS http://localhost:5000/health >/dev/null || fail "MLflow did not become healthy"
  cat <<'EOF'
Local platform ready:
  MLflow UI:      http://localhost:5000
  Agentic API:    http://localhost:8000/docs
  Model service:  http://localhost:8010/docs
  MinIO console:  http://localhost:9001  (minioadmin / minioadmin)
EOF
}

gcp_mode() {
  [[ -n "$PROJECT_ID" ]] || fail "--project or GCP_PROJECT_ID is required"
  need gcloud; need terraform; need kubectl; need helm; need docker
  local tf_dir="$ROOT_DIR/gcp/terraform"
  gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1 || fail "Cannot access GCP project $PROJECT_ID"
  gcloud config set project "$PROJECT_ID" >/dev/null

  if [[ "$ACTION" == "destroy" ]]; then
    terraform -chdir="$tf_dir" init
    terraform -chdir="$tf_dir" destroy -auto-approve -var="project_id=$PROJECT_ID" \
      -var="region=$REGION" -var="zone=$ZONE" -var="platform_name=$PLATFORM_NAME"
    return
  fi

  log "Provisioning the GCP platform"
  terraform -chdir="$tf_dir" init
  terraform -chdir="$tf_dir" apply -auto-approve -var="project_id=$PROJECT_ID" \
    -var="region=$REGION" -var="zone=$ZONE" -var="platform_name=$PLATFORM_NAME"

  local cluster registry_host repository bucket sql_connection gsa db_secret image_prefix db_password
  cluster="$(terraform -chdir="$tf_dir" output -raw cluster_name)"
  registry_host="$(terraform -chdir="$tf_dir" output -raw registry_host)"
  repository="$(terraform -chdir="$tf_dir" output -raw artifact_repository)"
  bucket="$(terraform -chdir="$tf_dir" output -raw artifact_bucket)"
  sql_connection="$(terraform -chdir="$tf_dir" output -raw cloud_sql_connection_name)"
  gsa="$(terraform -chdir="$tf_dir" output -raw mlflow_service_account_email)"
  db_secret="$(terraform -chdir="$tf_dir" output -raw database_password_secret_id)"
  image_prefix="$registry_host/$PROJECT_ID/$repository"

  gcloud container clusters get-credentials "$cluster" --zone "$ZONE" --project "$PROJECT_ID"
  gcloud auth configure-docker "$registry_host" --quiet
  build_images "$image_prefix" "google-cloud-storage"

  kubectl create namespace ml-platform --dry-run=client -o yaml | kubectl apply -f -
  db_password="$(gcloud secrets versions access latest --secret="$db_secret" --project="$PROJECT_ID")"
  kubectl -n ml-platform create secret generic mlflow-runtime \
    --from-literal=backendUri="postgresql+psycopg2://mlflow:${db_password}@127.0.0.1:5432/mlflow" \
    --dry-run=client -o yaml | kubectl apply -f -
  unset db_password

  if [[ "$GITOPS" == "true" ]]; then
    install_argocd
    sed -e "s|__GIT_REPO_URL__|$GIT_REPO_URL|g" -e "s|__GIT_REVISION__|$GIT_REVISION|g" \
      -e "s|__PROJECT_ID__|$PROJECT_ID|g" -e "s|__REGION__|$REGION|g" \
      -e "s|__IMAGE_REPOSITORY__|$image_prefix|g" -e "s|__IMAGE_TAG__|$IMAGE_TAG|g" \
      -e "s|__BUCKET__|$bucket|g" -e "s|__SQL_CONNECTION__|$sql_connection|g" \
      -e "s|__GSA_EMAIL__|$gsa|g" "$ROOT_DIR/gcp/gitops/root-application.yaml" | kubectl apply -f -
  else
    helm upgrade --install ml-platform "$ROOT_DIR/common/helm/platform" -n ml-platform \
      -f "$ROOT_DIR/gcp/helm/values.yaml" --set global.projectId="$PROJECT_ID" \
      --set global.region="$REGION" --set global.imageRepository="$image_prefix" \
      --set global.imageTag="$IMAGE_TAG" --set mlflow.artifactRoot="gs://$bucket" \
      --set mlflow.providerConfig.connectionName="$sql_connection" \
      --set-string "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account=$gsa" \
      --wait --timeout 15m
  fi
  log "GCP deployment submitted. MLflow: kubectl -n ml-platform port-forward svc/mlflow 5000:5000"
}

azure_mode() {
  need az; need terraform; need kubectl; need helm; need docker
  [[ -n "$AZURE_SUBSCRIPTION_ID" ]] && az account set --subscription "$AZURE_SUBSCRIPTION_ID"
  AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
  AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-${PLATFORM_NAME}-rg}"
  local tf_dir="$ROOT_DIR/azure/terraform"
  if [[ "$ACTION" == "destroy" ]]; then
    terraform -chdir="$tf_dir" init
    terraform -chdir="$tf_dir" destroy -auto-approve \
      -var="subscription_id=$AZURE_SUBSCRIPTION_ID" \
      -var="resource_group_name=$AZURE_RESOURCE_GROUP" \
      -var="location=$AZURE_LOCATION" -var="platform_name=$PLATFORM_NAME"
    return
  fi

  log "Provisioning the Azure platform"
  terraform -chdir="$tf_dir" init
  terraform -chdir="$tf_dir" apply -auto-approve \
    -var="subscription_id=$AZURE_SUBSCRIPTION_ID" \
    -var="resource_group_name=$AZURE_RESOURCE_GROUP" \
    -var="location=$AZURE_LOCATION" -var="platform_name=$PLATFORM_NAME"

  local db_password cluster acr login_server storage pg_host client_id tenant image_prefix connection
  cluster="$(terraform -chdir="$tf_dir" output -raw cluster_name)"
  acr="$(terraform -chdir="$tf_dir" output -raw acr_name)"
  login_server="$(terraform -chdir="$tf_dir" output -raw acr_login_server)"
  storage="$(terraform -chdir="$tf_dir" output -raw storage_account_name)"
  pg_host="$(terraform -chdir="$tf_dir" output -raw postgres_host)"
  client_id="$(terraform -chdir="$tf_dir" output -raw workload_identity_client_id)"
  tenant="$(terraform -chdir="$tf_dir" output -raw tenant_id)"
  db_password="$(terraform -chdir="$tf_dir" output -raw database_password)"
  image_prefix="$login_server"

  az aks get-credentials -g "$AZURE_RESOURCE_GROUP" -n "$cluster" --overwrite-existing
  az acr login --name "$acr"
  build_images "$image_prefix" "azure-storage-blob azure-identity"
  connection="$(az storage account show-connection-string -g "$AZURE_RESOURCE_GROUP" -n "$storage" --query connectionString -o tsv)"

  kubectl create namespace ml-platform --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n ml-platform create secret generic mlflow-runtime \
    --from-literal=backendUri="postgresql+psycopg2://mlflow:${db_password}@${pg_host}:5432/mlflow?sslmode=require" \
    --from-literal=azureStorageConnectionString="$connection" \
    --dry-run=client -o yaml | kubectl apply -f -
  unset db_password connection

  if [[ "$GITOPS" == "true" ]]; then
    install_argocd
    sed -e "s|__GIT_REPO_URL__|$GIT_REPO_URL|g" -e "s|__GIT_REVISION__|$GIT_REVISION|g" \
      -e "s|__IMAGE_REPOSITORY__|$image_prefix|g" -e "s|__IMAGE_TAG__|$IMAGE_TAG|g" \
      -e "s|__STORAGE_ACCOUNT__|$storage|g" -e "s|__AZURE_CLIENT_ID__|$client_id|g" \
      -e "s|__AZURE_TENANT_ID__|$tenant|g" "$ROOT_DIR/azure/gitops/root-application.yaml" | kubectl apply -f -
  else
    helm upgrade --install ml-platform "$ROOT_DIR/common/helm/platform" -n ml-platform \
      -f "$ROOT_DIR/azure/helm/values.yaml" --set global.imageRepository="$image_prefix" \
      --set global.imageTag="$IMAGE_TAG" \
      --set mlflow.artifactRoot="wasbs://mlflow@${storage}.blob.core.windows.net" \
      --set-string "serviceAccount.annotations.azure\\.workload\\.identity/client-id=$client_id" \
      --set-string "serviceAccount.annotations.azure\\.workload\\.identity/tenant-id=$tenant" \
      --wait --timeout 15m
  fi
  log "Azure deployment submitted. MLflow: kubectl -n ml-platform port-forward svc/mlflow 5000:5000"
}

case "$MODE:$CLOUD" in
  local:) local_mode ;;
  cloud:gcp) gcp_mode ;;
  cloud:azure) azure_mode ;;
  *) fail "Unsupported mode" ;;
esac
