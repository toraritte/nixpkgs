#!/usr/bin/env bash
set -euo pipefail
set -x

image="${1}"
location="westus2"
group="sftb-nixos-vms-rg"
vm_name="${2}"
vm_size="Standard_D2s_v3";  os_size=42;

# enxure group
if ! az group show --resource-group "${group}" &>/dev/null; then
  az group create --name "${group}" --location "${location}"
fi

group_id="$(az group show --name "${group}" --output tsv --query "[id]")"

# (optional) identity
if ! az identity show --name "${group}-identity" --resource-group "${group}" &>/dev/stderr; then
  az identity create --name "${group}-identity" --resource-group "${group}"
fi

# (optional) role assignment, to the resource group, bad but not really great alternatives
identity_id="$(
  az identity show \
    --name "${group}-identity" \
    --resource-group "${group}" \
    --output tsv --query "[id]"
  )"
principal_id="$(
  az identity show \
    --name "${group}-identity" \
    --resource-group "${group}" \
    --output tsv --query "[principalId]"
  )"

# As long as the `az role assignment` command fails,
# the loop will continue
# https://tldp.org/LDP/Bash-Beginners-Guide/html/sect_09_03.html
# https://linuxize.com/post/bash-until-loop/
# TODO I think this is superfluous
until az role assignment create --assignee "${principal_id}" --role "Owner" --scope "${group_id}"; do
  echo "Retrying role assignment..."
  sleep 1
done

echo "Role assignment successful"

# boot vm
az vm create \
  --name "${vm_name}" \
  --resource-group "${group}" \
  --assign-identity "${identity_id}" \
  --size "${vm_size}" \
  --os-disk-size-gb "${os_size}" \
  --image "${image}" \
  --admin-username "${USER}" \
  --location "westus2" \
  --storage-sku "Premium_LRS" \
  --generate-ssh-keys
  # This only works if `ssh-agent` is running
  # --ssh-key-values "$(ssh-add -L)"

