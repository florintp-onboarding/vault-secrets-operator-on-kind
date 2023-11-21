#!/bin/bash
export NAMESPACE=ldap
kubectl delete ns ${NAMESPACE}
kubectl create ns ${NAMESPACE}

kubectl create -n ${NAMESPACE} secret generic openldap --from-literal=adminpassword=adminpassword --from-literal=users=user01,user02 --from-literal=passwords=password01,password02

kubectl apply -f ldap/simple-svc.yaml
kubectl apply -f ldap/simple-deployment.yaml

sleep 10
nc -vz 127.0.0.1 1389
kubectl port-forward --namespace  ldap svc/openldap 1389:1389 &


export V_TOKEN=$(cat init-keys.json|jq -r '.root_token')
export OPENLDAP_URL="$(kubectl get svc -A -o json  --selector="app.kubernetes.io/name=openldap" |jq -r  '.items[].spec.clusterIP'):1389"

VAULT_TOKEN=${V_TOKEN?} \
vault secrets disable ldap

VAULT_TOKEN=${V_TOKEN?} \
vault secrets enable ldap

VAULT_TOKEN=${V_TOKEN?} \
vault write ldap/config \
    binddn="cn=admin,dc=example, dc=org" \
    bindpass="adminpassword" \
    url=ldap://$OPENLDAP_URL

VAULT_TOKEN=${V_TOKEN?} \
vault write ldap/static-role/test130238 \
    dn='cn=user01,ou=users,dc=example,dc=org' \
    username='user01' \
    rotation_period="30s"

#### Request OpenLDAP credential from the learn role
#  cat >static_policy.hcl<<EOF2
#  path "ldap/static-cred/learn" {
#    capabilities = [ "read" ]
#  }
#  EOF2
#  
#  export V_TOKEN=$(cat init-keys.json|jq -r '.root_token')
#  VAULT_TOKEN=${V_TOKEN?} \
#  vault policy write static-policy static_policy.hcl
###

# Extend the policy permissions for "ldap/static-cred/*"
VAULT_TOKEN=${V_TOKEN?} vault policy write demo-auth-policy-db - <<EOF
path "demo-db/creds/dev-postgres" {
   capabilities = ["read"]
}
path "database/static-creds/*" {
   capabilities = ["read"]
}
path "ldap/static-cred/test130238" {
   capabilities = ["read"]
}
EOF


date; echo "Manually rotate static credentials"
echo 'KV-V2 secret'
_vsecret="static-KVV2-PASS-$(date '+%H:%M:%S')" && echo $_vsecret
VAULT_TOKEN=${V_TOKEN?} vault kv put -non-interactive kvv2/webapp/config username=static-user2 password="$_vsecret" -format=json 

echo 'DATABASE dynamic - secret'
VAULT_TOKEN=${V_TOKEN?} vault write -f demo-db/rotate-role/dev-postgres -format=json &>/dev/null
VAULT_TOKEN=${V_TOKEN?} vault read demo-db/creds/dev-postgres -format=json |jq -r

echo 'DATABASE static - secret'
VAULT_TOKEN=${V_TOKEN?} vault read database/static-creds/education -format=json |jq -r
echo 'LDAP static-secret'
VAULT_TOKEN=${V_TOKEN?} vault write -f ldap/rotate-role/test130238 
VAULT_TOKEN=${V_TOKEN?} vault read  ldap/static-cred/test130238 -format=json |jq -r

exit
#LOOPS
while : ; do sleep 2;printf '\n %s ' "" && kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D ; done

a="" ; while : ; do 
  sleep 2;printf '\r %s ' "." &&  c=$(kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D |jq -r) ; b=$(echo "${c}"|jq -r '.last_vault_rotation')
  if [[ "a$a" ==  "a$b" ]] ; then
   printf '\r %s  ' ""
  else
     a=$b && echo $c || printf '\n{Password=%s\nChanged_at=%s\nlast_vault_rotation=%s\nTTL=%s}\n' "$(kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D |jq -r '.password')" "$(date)" "${a}" "$(kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D |jq -r '.ttl')"
  fi
done

a="" ; while :; do b=$(kubectl get  secret/secretkv -n app --template={{.data.password}} | base64 -D) 
  if [[ "a$a" ==  "a$b" ]] ; then
   printf '\r %s  ' "$a : $b"
  else
    a=$b && printf '\n%s \n%s' "Changed at:$(date)  last vault_rotation:$a" $(kubectl get  secret/secretkv -n app --template={{.data.password}} | base64 -D)
  fi
done
# Check the creation of PODS
 while : ; do sleep 2 ;kubectl get pods -A -o json  | jq -r '.items[] | select(.status.phase != "Running" or ([ .status.conditions[] | select(.type == "Ready" and .status == "False") ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name + " " + .status.phase + " " + .metadata.creationTimestamp' |tee -a state.txt;  done

