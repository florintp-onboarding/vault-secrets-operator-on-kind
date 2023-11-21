#!/bin/bash
#
export DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

rm -f init-keys.json workers.yaml
helm repo remove hashicorp
kind delete clusters kind1
unset VAULT_TOKEN
unset VAULT_UNSEAL_KEY
unset VAULT_ROOT_KEY
unset NAMESPACE
exit

