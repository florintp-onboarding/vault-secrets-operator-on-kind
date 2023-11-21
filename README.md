# vault-secrets-operator-on-kind
Vault Secrets Operator with static and dynamic secrets hands-on 

- Clean up infrastructure (KIND)
````
chmod u+rx clean.sh
sh clean.sh
````

- Initialize the VAULT_TOKEN variable
````
unset VAULT_TOKEN
export V_TOKEN=$(cat init-keys.json|jq -r '.root_token')
````

- Watching the PODs state changes
````
while : ; do sleep 2 ;kubectl get pods -A -o json  | jq -r '.items[] | select(.status.phase != "Running" or ([ .status.conditions[] | select(.type == "Ready" and .status == "False") ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name + " " + .status.phase + " " + .metadata.creationTimestamp' |tee -a state.txt;  done
````

- Watching the KV-V2 secret sync in APP namespace
````
while : ; do
  a=$(kubectl get  secret/secretkv -n app --template={{.data.password}} | base64 -D) 
  printf '\n%s %s' "$(date)" $a ; sleep 1 
done
````

- Watching the LDAP static-secret sync in demo-ns namespace
````
a="" ; while : ; do
  sleep 2;printf '\r %s ' "." &&  c=$(kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D |jq -r) ; b=$(echo "${c}"|jq -r '.last_vault_rotation')
  if [[ "a$a" ==  "a$b" ]] ; then
   printf '\r %s  ' ""
  else
     a=$b && echo $c || printf '\n{Password=%s\nChanged_at=%s\nlast_vault_rotation=%s\nTTL=%s}\n' "$(kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D |jq -r '.password')" "$(date)" "${a}" "$(kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D |jq -r '.ttl')"
  fi
done
````

- Get all the PODs
````
kubectl get pods -A
````
