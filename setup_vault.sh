#!/bin/bash -x
# Used the initial deployment steps from /Users/florin.tiucra-popa/hashicorp/git/florintp-onboarding/k8s_minikube_raft_3nodes
# https://developer.hashicorp.com/vault/docs/platform/k8s/helm/configuration#activevaultpodonly
# https://support.hashicorp.com/hc/en-us/articles/10674456289555-Adding-Environment-Variables-to-a-Vault-Process

export DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export NAMESPACE='vault'
export VAULT_PORT=8200
export VAULT_LICENSE=$(cat ./vault_license.hclic) ; export VAULT_LICENSE=$(echo -en "$VAULT_LICENSE") ; export TF_VAR_vault_license=$VAULT_LICENSE
if [ "X${VAULT_LICENSE}" == "X" ] ;then
  printf '\n%s' "No Vault license provided!"
  exit 1
fi

if [ ! -f vault/values.yaml ] ; then 
   printf '\n%s' "No values file for deployment of Vault!"
   exit 2
fi

if ! $(helm version &>/dev/null)  ||
   !  $(kubectl version &>/dev/null)  ; then
   printf '\n%s' "Not all binaries present!"
   exit 3
fi

printf '\r# Adding Vault HELM repo.'
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
kubectl delete  namespace ${NAMESPACE}
kubectl create namespace ${NAMESPACE}

# Cread Vault license secret
kubectl create secret generic \
	vault-license \
	-n "${NAMESPACE}" \
	--from-literal=VAULT_LICENSE=${VAULT_LICENSE} &>/dev/null

#[ -t ] && kubectl get secret vault-license -n ${NAMESPACE} -o json

#--set=server.extraEnvironmentVars.VAULT_ADDR=http://127.0.0.1:${VAULT_PORT} \
printf '\r# Deploying Vault HELM CHART  with 5 nodes.'
helm install ${NAMESPACE} hashicorp/vault \
	--namespace="${NAMESPACE?}" \
	-f vault/values.yaml

printf '\n# Waiting for all Vault PODs to reach the Running state\n'
while [ $(kubectl get pods -n ${NAMESPACE?} -o json|jq -r '.items[]|{pod:.metadata.name, state:.status.phase}|select ( .state == "Running" )|.pod' |wc -l|awk '{print $1}') -lt 6 ] ; do
  printf '\r\'
  sleep 1
  printf '\r|'
  sleep 1
  printf '\r/'
done
printf '\r# All Vault PODs are in Running state!'

printf '\n# Executing Init Vault vault-0'
kubectl exec -it vault-0 -n ${NAMESPACE?} -- vault operator init -format=json -t 1 -n 1 >  init-keys.json
#cat -vte init-keys.json
sleep 5
VAULT_UNSEAL_KEY=$(cat init-keys.json|sed 's/^M$//' |jq -r ".unseal_keys_b64[]" )
VAULT_ROOT_KEY=$(cat init-keys.json|sed 's/^M$//'|jq -r ".root_token" )

kubectl exec -it vault-0 -n ${NAMESPACE?}  -- vault operator unseal ${VAULT_UNSEAL_KEY?} &>/dev/null
sleep 5

printf '\r# Joining the Vault PODs to RAFT cluster.'
for j in $(seq 1 4) ; do
   printf '\n## Joining %s' vault-$j
   while ! kubectl exec -it vault-$j -n ${NAMESPACE?}  -- vault operator raft join "http://vault-0.vault-internal:8200" &>/dev/null ; do
      sleep 1 
      printf '\r%s' "."
   done
   printf '\n## Joined %s     ' vault-$j
   printf '\r## Unsealing %s  ' vault-$j
   kubectl exec -it vault-$j -n ${NAMESPACE?}  -- vault operator unseal ${VAULT_UNSEAL_KEY?} &>/dev/null
   printf '\r## Unsealed %s   ' vault-$j
done
printf '\n# Vault is ready and all nodes joined\n'

unset  VAULT_TOKEN
export VAULT_ADDR='http://localhost:8200'
export V_TOKEN=$(cat init-keys.json|jq -r '.root_token')  
#### export K_PORT_443_TCP_ADDR=$(kubectl get svc -A -o json | jq -r  '.items[] | {name:.metadata.name, ip:.spec.clusterIP} | select( .name == "kubernetes" )| .ip')
#### 
#### kubectl exec -it -n vault vault-0 -- env VAULT_ADDR=${VAULT_ADDR?} vault status
#### kubectl exec -it -n vault vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault auth disable -non-interactive demo-auth-mount 
#### kubectl exec -it -n vault vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault auth enable -non-interactive -path demo-auth-mount kubernetes 
#### kubectl exec -it -n vault vault-0 -- env KUBERNETES_PORT_443_TCP_ADDR=${K_PORT_443_TCP_ADDR?} env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault write -non-interactive auth/demo-auth-mount/config kubernetes_host="https://${K_PORT_443_TCP_ADDR?}:443"
#### 
kubectl exec -it -n ${NAMESPACE?} vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault secrets disable -non-interactive kvv2 &>/dev/null
kubectl exec -it -n ${NAMESPACE?} vault-0 -- env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?}  vault secrets enable -non-interactive -path=kvv2 kv-v2 &>/dev/null
kubectl port-forward -n ${NAMESPACE?} service/vault 8200 &> /dev/null &
nc -vz localhost 8200

VAULT_TOKEN=${V_TOKEN?} vault secrets list -detailed |awk '{print $1,$2, $NF}'
VAULT_TOKEN=${V_TOKEN?} vault policy write dev - <<EOF
path "kvv2/*" {
   capabilities = ["read"]
}
EOF

printf '\nKV path used %s and key %s\n' "kvv2" "webapp/config username='static-user' password='static-password'"
VAULT_TOKEN=${V_TOKEN?} vault kv put -format=json kvv2/webapp/config username="static-user" password="static-password"

