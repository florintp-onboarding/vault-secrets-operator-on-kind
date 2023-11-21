#!/bin/bash 
export DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
chmod +rx ${DIR}/clean.sh
${DIR}/clean.sh

export NAMESPACE='vault'
export VAULT_LICENSE=$(cat ./vault_license.hclic)
cat > workers.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kind1
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

kind create cluster --name=kind1 --config=workers.yaml
#kubectl get nodes
#kind get clusters
kubectl cluster-info --context kind-kind1

helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault
chmod u+rx setup_vault.sh
bash  setup_vault.sh

chmod u+rx setup_postgres.sh
bash  setup_postgres.sh

chmod u+rx setup_ldap.sh
bash  setup_ldap.sh

chmod u+rx setup_vso.sh
bash  setup_vso.sh

