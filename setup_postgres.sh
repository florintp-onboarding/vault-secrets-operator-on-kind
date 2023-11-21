#!/bin/bash
# Used the initial deployment steps from /Users/florin.tiucra-popa/hashicorp/git/florintp-onboarding/k8s_minikube_raft_3nodes
# https://kodekloud.com/blog/deploy-postgresql-kubernetes/
# https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
# https://developer.hashicorp.com/vault/docs/secrets/databases/postgresql
# https://developer.hashicorp.com/vault/tutorials/db-credentials/database-creds-rotation?variants=vault-deploy%3Aselfhosted
# https://developer.hashicorp.com/vault/api-docs/secret/databases
# https://sweetcode.io/how-to-deploy-postgresql-instance-to-kubernetes/
#
export DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export NAMESPACE='postgres'

export VAULT_PORT=8200
unset  VAULT_TOKEN
export VAULT_ADDR=http://localhost:8200
export V_TOKEN=$(cat init-keys.json|jq -r '.root_token')
export K_PORT_443_TCP_ADDR=$(kubectl get svc -A -o json | jq -r  '.items[] | {name:.metadata.name, ip:.spec.clusterIP} | select( .name == "kubernetes" )| .ip')

kubectl delete namespace ${NAMESPACE}
kubectl create namespace ${NAMESPACE}

kubectl delete pv postgres-persistent-volume
kubectl delete pvc db-persistent-volume-claim
kubectl apply -f postgres/pv-claim.yaml
kubectl apply -f postgres/db-secrets-configmap.yaml 
kubectl apply -f postgres/db-deployment.yaml
kubectl apply -f postgres/db-service.yaml

while [ $(kubectl get pods -n ${NAMESPACE?} -o json|jq -r '.items[]|{pod:.metadata.name, state:.status.phase}|select ( .state == "Running" )|.pod' |wc -l|awk '{print $1}') -eq 0 ] ; do
  sleep 1
done

echo "Default connect POD:$(kubectl get pods -n postgres --selector='app=postgresdb' -o jsonpath='{.items[0].metadata.name}')"
export POSTGRES_PASSWORD=$(kubectl get configmap -n ${NAMESPACE?} -o json|jq -r '.items[]|select ( .metadata.name == "db-secret-credentials") |.data.POSTGRES_PASSWORD')
export POSTGRES_URL="$(kubectl get svc -A -o json -n ${NAMESPACE?} --selector='app=postgresdb'|jq -r  '.items[] | {name:.metadata.name, ip:.spec.clusterIP} | select( .name == "postgresdb" )| .ip'):5432"

sleep 1
nc -vz 127.0.0.1 5432
kubectl port-forward --namespace postgres svc/postgresdb 5432:5432 &

kubectl exec -it -n vault vault-0 -- env KUBERNETES_PORT_443_TCP_ADDR=${K_PORT_443_TCP_ADDR?} env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault write -f /sys/leases/revoke-force/demo-db/creds
kubectl exec -it -n vault vault-0 -- env KUBERNETES_PORT_443_TCP_ADDR=${K_PORT_443_TCP_ADDR?} env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault secrets disable demo-db 
kubectl exec -it -n vault vault-0 -- env KUBERNETES_PORT_443_TCP_ADDR=${K_PORT_443_TCP_ADDR?} env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault secrets disable database
kubectl exec -it -n vault vault-0 -- env KUBERNETES_PORT_443_TCP_ADDR=${K_PORT_443_TCP_ADDR?} env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault secrets enable -path=demo-db database
kubectl exec -it -n vault vault-0 -- env KUBERNETES_PORT_443_TCP_ADDR=${K_PORT_443_TCP_ADDR?} env VAULT_TOKEN=${V_TOKEN?} env VAULT_ADDR=${VAULT_ADDR?} vault secrets enable -path=database database

kubectl exec -it -n postgres $(kubectl get pods -n ${NAMESPACE?} --selector='app=postgresdb' -o jsonpath='{.items[0].metadata.name}')  -- psql --host 127.0.0.1 -U postgres -d postgres -p 5432 -c "CREATE ROLE \"vault-edu\" WITH LOGIN PASSWORD 'mypassword';"

kubectl exec -it -n postgres $(kubectl get pods -n ${NAMESPACE?} --selector='app=postgresdb' -o jsonpath='{.items[0].metadata.name}')  -- psql --host 127.0.0.1 -U postgres -d postgres -p 5432 -c "\du"

kubectl exec -it -n postgres $(kubectl get pods -n ${NAMESPACE?} --selector='app=postgresdb' -o jsonpath='{.items[0].metadata.name}')  -- psql --host 127.0.0.1 -U postgres -d postgres -p 5432 -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"vault-edu\";"

# Another way of reaching to the endpoint of POSTGRES
# connection_url="postgresql://{{username}}:{{password}}@postgres.postgres.svc.cluster.local:5432/postgres?sslmode=disable" \
# Dynamic
VAULT_TOKEN=${V_TOKEN?} vault write demo-db/config/demo-db \
   plugin_name=postgresql-database-plugin \
   allowed_roles="dev-postgres,education" \
   connection_url="postgresql://{{username}}:{{password}}@$POSTGRES_URL/postgres?sslmode=disable" \
   username="postgres" \
   password="${POSTGRES_PASSWORD?}"
#password="${POSTGRES_PASSWORD?}"

VAULT_TOKEN=${V_TOKEN?} vault write demo-db/roles/dev-postgres \
   db_name=demo-db \
   creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';\
   GRANT ALL PRIVILEGES ON DATABASE postgres TO \"{{name}}\";" \
   backend=demo-db \
   name=dev-postgres \
   default_ttl="1m" \
   max_ttl="1m"

VAULT_TOKEN=${V_TOKEN?} vault policy write demo-auth-policy-db - <<EOF
path "demo-db/creds/dev-postgres" {
   capabilities = ["read"]
}
path "database/static-creds/*" {
   capabilities = ["read"]
}
EOF

tee rotation.sql <<EOF
ALTER USER "{{name}}" WITH PASSWORD '{{password}}';
EOF

# Or... connection_url="postgresql://{{username}}:{{password}}@$POSTGRES_URL/postgres?sslmode=disable" \
VAULT_TOKEN=${V_TOKEN?} \
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    allowed_roles="dev-postgres,education" \
    connection_url="postgresql://{{username}}:{{password}}@$POSTGRES_URL/postgres?sslmode=disable" \
    username="postgres" \
    password="${POSTGRES_PASSWORD}"

VAULT_TOKEN=${V_TOKEN?} \
vault write database/static-roles/education \
    db_name=postgresql \
    rotation_statements=@rotation.sql \
    username="vault-edu" \
    rotation_period=24h

VAULT_TOKEN=${V_TOKEN?} \
vault read database/static-roles/education


echo "TESTING
Manually rotate static credentials"
VAULT_TOKEN=${V_TOKEN?} \
vault write -f database/rotate-role/education ;\
VAULT_TOKEN=${V_TOKEN?} \
vault read database/static-creds/education

rm rotation.sql
exit
####
# Check the role in every POD
for i in $(seq  0 2) ; do 
  echo $(kubectl get pods -n ${NAMESPACE?} --selector='app=postgresdb' -o jsonpath="{.items[$i].metadata.name}") 
  kubectl exec -it -n postgres $(kubectl get pods -n ${NAMESPACE?} --selector='app=postgresdb' -o jsonpath="{.items[$i].metadata.name}")  -- psql --host 127.0.0.1 -U postgres -d postgres -p 5432 -c "\du"
done

