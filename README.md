## Simple PoC project `vault-secrets-operator-on-kind` that creates a Kind Kubernetes Cluster and configures Vault Secrets Operator to sync the secrets.

-----

![Vault Logo](https://github.com/hashicorp/vault/raw/f22d202cde2018f9455dec755118a9b84586e082/Vault_PrimaryLogo_Black.png)


### What is it : 

  This project `vault-secrets-operator-on-kind` creates a Kind Kubernetes Cluster (kind1) and configures Vault Secrets Operator to sync the secrets.
  Vault Secrets Operator with static and dynamic secrets hands-on KV-V2 secrets, POSTGRES dynamic secrets, LDAP static secrets.
  
  The main script (`setup.sh`) will create a Kind cluster (`kind1`) and call the modules for:
  -  deploy and confgure Vault (`setup_vault.sh`),
  -  deploy and configure POSTGRES (`setup_postgres.sh`),
  -  deploy and configure LDAP (OpenLDAP) (`setup_ldap.sh`),
  -  and deploy and configure VSO (`setup_vso.sh`).

  The structure may look similar to the tree image from below.
````
├── clean.sh
├── dynamic-secrets
│   ├── app-deployment.yaml
│   ├── app-secret.yaml
│   ├── vault-auth-dynamic.yaml
│   ├── vault-auth-operator.yaml
│   ├── vault-dynamic-secret-create.yaml
│   ├── vault-dynamic-secret.yaml
│   └── vault-operator-sa.yaml
├── ldap
│   ├── simple-deployment.yaml
│   └── simple-svc.yaml
├── postgres
│   ├── db-deployment.yaml
│   ├── db-secrets-configmap.yaml
│   ├── db-service.yaml
│   └── pv-claim.yaml
├── setup.sh
├── setup_ldap.sh
├── setup_postgres.sh
├── setup_vault.sh
├── setup_vso.sh
├── vault
│   ├── static-secret.yaml
│   ├── template_values.yaml
│   ├── values.yaml
│   ├── vault-auth-static.yaml
│   ├── vault-operator-values.yaml
│   └── vault-values.yaml
└── vault_license.hclic
  ````
  Each of the child scripts may be executed independently for debug purposes.
  Vault cluster deployed is a 5 nodes Vault having as storage backend RAFT into a specific namespace `vault`. 
  

### Prerequisites :

  - Having Kind installed and configured: [Kind Tool](https://kind.sigs.k8s.io/)
  - Having HELM package manager installed: [HELM package manager](https://helm.sh/)
  - JQ utility: JQ Command-line JSON processor: [JQ](https://jqlang.github.io/jq/)
  - A valid Vault license

### Guidance and articles followed :

   This repo is used as hands-on experience for using Vault Secrets Operator to sync Kubernetes secrets from different secret mounts.
   The repo is built following the guidance:

   - [Vault Secrets Operator on Kubernetes](https://developer.hashicorp.com/vault/tutorials/kubernetes/vault-secrets-operator)
   - [Vault Database Secrets Engine](https://developer.hashicorp.com/vault/tutorials/db-credentials/database-secrets)
   - [Vault LDAP Secrets Engine](https://developer.hashicorp.com/vault/tutorials/secrets-management/openldap)

### Usage :

  - Clone the repository : `git clone https://github.com/florintp-onboarding/vault-secrets-operator-on-kind.git`.
  - Change into its directory : `cd vault-secrets-operator-on-kind`.
  - Put your Vault enterprise license in a file named `vault_license.hclic` in the root directory of this project.
  - Choose the desired version TAG of Vault Enterprise according to GA from [Vault Docker Enterprise TAGS](https://hub.docker.com/r/hashicorp/vault-enterprise/tags) in `vault/values.yaml`
  - Change the ownership of the setup.sh file `chmod u+rx setup.sh`
  - Execute the all in one script `bash setup.sh` and check the deployed PODs and the secrets created.
  - Possible output is attached below.


###  Clean up infrastructure (KIND)
````
chmod u+rx clean.sh
bash clean.sh
````

###  Scritps to monitor and observe the secrets and PODs state
- Initialize the VAULT_TOKEN variable
````
unset VAULT_TOKEN
export V_TOKEN=$(cat init-keys.json|jq -r '.root_token')
````

- Watching the PODs state changes and keep the history into state_pods.txt
````
while : ; do
  sleep 1
  kubectl get pods -A -o json  | jq -r '.items[] | select(.status.phase != "Running" or ([ .status.conditions[] | select(.type == "Ready" and .status == "False") ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name + " " + .status.phase + " " + .metadata.creationTimestamp' |tee -a state_pods.txt
done
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

### Possible Ouptut :

````
bash setup.sh
Error: no repo named "hashicorp" found
Deleted clusters: ["kind1"]
Creating cluster "kind1" ...
 ✓ Ensuring node image (kindest/node:v1.27.3) 🖼
 ✓ Preparing nodes 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-kind1"
You can now use your cluster with:

kubectl cluster-info --context kind-kind1

Have a question, bug, or feature request? Let us know! https://kind.sigs.k8s.io/#community 🙂
Kubernetes control plane is running at https://127.0.0.1:54158
CoreDNS is running at https://127.0.0.1:54158/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
"hashicorp" has been added to your repositories
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "aws-ebs-csi-driver" chart repository
...Successfully got an update from the "hashicorp" chart repository
...Successfully got an update from the "bitnami" chart repository
Update Complete. ⎈Happy Helming!⎈
namespace/vault created
# Adding Vault HELM repo."hashicorp" already exists with the same configuration, skipping
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "aws-ebs-csi-driver" chart repository
...Successfully got an update from the "hashicorp" chart repository
...Successfully got an update from the "bitnami" chart repository
Update Complete. ⎈Happy Helming!⎈
namespace "vault" deleted
namespace/vault created
# Deploying Vault HELM CHART  with 5 nodes.W1121 10:40:57.231883   78963 warnings.go:70] unknown field "spec.template.spec.containers[0].resources.auditStorage"
W1121 10:40:57.231906   78963 warnings.go:70] unknown field "spec.template.spec.containers[0].resources.dataStorage"
W1121 10:40:57.231909   78963 warnings.go:70] unknown field "spec.template.spec.containers[0].resources.pullPolicy"
NAME: vault
LAST DEPLOYED: Tue Nov 21 10:40:56 2023
NAMESPACE: vault
STATUS: deployed
REVISION: 1
NOTES:
Thank you for installing HashiCorp Vault!

Now that you have deployed Vault, you should look over the docs on using
Vault with Kubernetes available here:

https://developer.hashicorp.com/vault/docs


Your release is named vault. To learn more about the release, try:

  $ helm status vault
  $ helm get manifest vault

# Waiting for all Vault PODs to reach the Running state
|
````
