#!/bin/bash
# Used the initial deployment steps from /Users/florin.tiucra-popa/hashicorp/git/florintp-onboarding/k8s_minikube_raft_3nodes
# https://developer.hashicorp.com/vault/tutorials/kubernetes/vault-secrets-operator
# https://.hashicorp.com/vault/docs/platform/k8s/vso/api-reference
# https://developer.hashicorp.com/vault/docs/platform/k8s/vso/installation
# https://cloud.google.com/knowledge/kb/deleted-namespace-remains-stuck-in-terminating-status-in-google-kubernetes-engine-000004867

export DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export NAMESPACE='demo-ns'

export VAULT_PORT=8200
export VAULT_LICENSE=$(cat ./vault_license.hclic) ; export VAULT_LICENSE=$(echo -en "$VAULT_LICENSE") ; export TF_VAR_vault_license=$VAULT_LICENSE

helm uninstall vault-secrets-operator -n vault-secrets-operator-system 
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update hashicorp
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator -n vault-secrets-operator-system --create-namespace --values vault/vault-operator-values.yaml

# Possible upgrade path on HELM
# helm show crds --version 0.4.0 hashicorp/vault-secrets-operator | kubectl apply -f -
# helm upgrade --version 0.4.0 --namespace vault-secrets-operator vault-secrets-operator hashicorp/vault-secrets-operator

kubectl delete namespace ${NAMESPACE}
kubectl create namespace ${NAMESPACE}

kubectl delete app
kubectl create ns app
kubectl apply -f vault/vault-auth-static.yaml
kubectl apply -f vault/static-secret.yaml

unset  VAULT_TOKEN
export VAULT_ADDR=http://localhost:8200
export V_TOKEN=$(cat init-keys.json|jq -r '.root_token')  
export K_PORT_443_TCP_ADDR=$(kubectl get svc -A -o json | jq -r  '.items[] | {name:.metadata.name, ip:.spec.clusterIP} | select( .name == "kubernetes" )| .ip')

# Enable Kubernetes auth as demo-auth-mount
kubectl exec -it -n vault vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault auth disable -non-interactive demo-auth-mount
kubectl exec -it -n vault vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault auth enable -non-interactive -path demo-auth-mount kubernetes
kubectl exec -it -n vault vault-0 -- env KUBERNETES_PORT_443_TCP_ADDR=${K_PORT_443_TCP_ADDR?} env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault write -non-interactive auth/demo-auth-mount/config kubernetes_host="https://${K_PORT_443_TCP_ADDR?}:443"

VAULT_TOKEN=$(echo ${V_TOKEN?}) vault policy write dev - <<EOF
path "kvv2/*" {
   capabilities = ["read"]
}
EOF

VAULT_TOKEN=${V_TOKEN?} vault write auth/demo-auth-mount/role/role1 \
   bound_service_account_names=default \
   bound_service_account_namespaces=app \
   policies=dev \
   audience=vault \
   ttl=24h


# Enable TRANSIT as demo-transit
kubectl exec -it -n vault vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault secrets disable demo-transit
kubectl exec -it -n vault vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault secrets enable -path=demo-transit transit
kubectl exec -it -n vault vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault write -force demo-transit/keys/vso-client-cache

# Added a policy to allo encrypt/decrypt of VSO-CLIENT-CACHE
VAULT_TOKEN=${V_TOKEN?} vault policy write demo-auth-policy-operator - <<EOF
path "demo-transit/encrypt/vso-client-cache" {
   capabilities = ["create", "update"]
}
path "demo-transit/decrypt/vso-client-cache" {
   capabilities = ["create", "update"]
}
EOF

# Create the role for demo-operator in namespace vault-secrets-operator-system
VAULT_TOKEN=${V_TOKEN?} vault write auth/demo-auth-mount/role/auth-role-operator \
   bound_service_account_names=demo-operator \
   bound_service_account_namespaces=vault-secrets-operator-system \
   token_ttl=0 \
   token_period=120 \
   token_policies=demo-auth-policy-db \
   audience=vault

VAULT_TOKEN=${V_TOKEN?} vault write auth/demo-auth-mount/role/auth-role \
   bound_service_account_names=default \
   bound_service_account_namespaces=demo-ns \
   token_ttl=0 \
   token_period=120 \
   token_policies=demo-auth-policy-db \
   audience=vault


kubectl exec -it -n vault vault-0 -- env VAULT_ADDR=${VAULT_ADDR?} vault status
kubectl exec -it -n vault vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?}  vault kv put -non-interactive kvv2/webapp/config username="static-user2" password="static-KVV2-$(date '+%H:%M:%S')" 

kubectl apply -f dynamic-secrets/.

