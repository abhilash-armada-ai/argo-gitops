#!/usr/bin/env bash
# =============================================================================
# Install ArgoCD on the bridge (management) cluster.
#
# Installs ArgoCD ONLY. Idempotent: safe to re-run. Prints the UI URL + admin
# password. Requires kubectl + helm already present.
#
# Usage:
#   bash bootstrap/install-argocd.sh
#
# Overridable via env:
#   ARGOCD_VERSION   ArgoCD Helm chart version            (default: 9.4.16)
#   ARGOCD_NS        namespace                            (default: argocd)
#   HTTP_NODEPORT    NodePort for the UI (http)           (default: 30080)
#   HTTPS_NODEPORT   NodePort for the UI (https)          (default: 30443)
# =============================================================================
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-9.4.16}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
HTTP_NODEPORT="${HTTP_NODEPORT:-30080}"
HTTPS_NODEPORT="${HTTPS_NODEPORT:-30443}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"
kubectl cluster-info >/dev/null 2>&1 || die "kubectl cannot reach a cluster — check your kubeconfig"
command -v helm >/dev/null 2>&1 || die "helm not found in PATH"
info "Helm: $(helm version --short)"

# ---------------------------------------------------------------------------
# Install / upgrade ArgoCD
# ---------------------------------------------------------------------------
info "Adding argo Helm repo…"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -

info "Installing/upgrading ArgoCD chart ${ARGOCD_VERSION} into ns/${ARGOCD_NS}…"
helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGOCD_NS}" \
  --version "${ARGOCD_VERSION}" \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  --set server.extraArgs="{--insecure}" \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp="${HTTP_NODEPORT}" \
  --set server.service.nodePortHttps="${HTTPS_NODEPORT}" \
  --wait --timeout 10m

# ---------------------------------------------------------------------------
# Credentials + access
# ---------------------------------------------------------------------------
ARGOCD_PASSWORD="$(kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '(already rotated — not available)')"
NODE_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

info "ArgoCD install complete."
echo "  UI       : http://${NODE_IP:-<node-ip>}:${HTTP_NODEPORT}"
echo "  Username : admin"
echo "  Password : ${ARGOCD_PASSWORD}"
