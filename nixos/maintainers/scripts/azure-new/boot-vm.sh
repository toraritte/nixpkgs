#!/usr/bin/env bash
# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

usage() {
  printf "-g --resource-group REQUIRED Created if does  not exist. Will"
  printf "                             house a new disk and the created"
  printf "                             image."
  printf ""
  printf "-i --image-id       REQUIRED Nix  expression   to  build  the"
  printf "                             image. Defaults to"
  printf "                             \"./examples/basic/image.nix\"."
  printf ""
  printf "-n --vm-name        REQUIRED The name of the  virtual machine"
  printf "                             created."
  printf ""
  printf "-n --vm-size        See https://azure.microsoft.com/pricing/details/virtual-machines/ for size info."
  printf "                    Default value: \"Standard_DS1_v2\""
  printf ""
  printf "-d --os-size        OS disk size in GB to create."
  printf "                    Default value: \"42\""
  printf ""
  printf "-l --location       Values from `az account list-locations`."
  printf "                    Default value: \"westus2\"."
};
 
# https://unix.stackexchange.com/a/204927/85131
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--location)
      location="$2"
      ;;
    -g|--resource-group)
      group="$2"
      ;;
    -i|--image-id)
      img_id="$2"
      ;;
    -n|--vm-name)
      vm_name="$2"
      ;;
    -s|--vm-size)
      vm_size="$2"
      ;;
    -d|--os-disk-size-gb)
      os_size="$2"
      ;;
    *)
      printf "***************************\n"
      printf "* Error: Invalid argument *\n"
      printf "***************************\n"
      usage
      exit 1
  esac
  shift
  shift
done

if [ -z "${img_id}" ] || [ -z "${group}" ] || [ -z "${vm_name}" ];
then
  printf "************************************\n"
  printf "* Error: Missing required argument *\n"
  printf "************************************\n"
  usage
  exit 1
fi

# ensure group
if ! az group show --resource-group "${group}" &>/dev/null;
then
  az group create     \
    --name "${group}" \
    --location "${location:-"westus2"}"
fi

# (optional) identity
if ! az identity show --name "${group}-identity" --resource-group "${group}" &>/dev/stderr;
then
  az identity create           \
    --name "${group}-identity" \
    --resource-group "${group}"
fi

# (optional) role assignment, to the resource group;
# bad but not really great alternatives
principal_id="$(
  az identity show              \
    --name "${group}-identity"  \
    --resource-group "${group}" \
    --output tsv --query "[principalId]"
)"

group_id="$(
  az group show       \
    --name "${group}" \
    --output tsv      \
    --query "[id]"
)"

assign_role() {
  az role assignment create      \
    --assignee "${principal_id}" \
    --role "Owner"               \
    --scope "${group_id}"
}
# As long as the `az role assignment` command fails,
# the loop will continue
# https://tldp.org/LDP/Bash-Beginners-Guide/html/sect_09_03.html
# https://linuxize.com/post/bash-until-loop/
# TODO I think this is superfluous
until assign_role;
do
  echo "Retrying role assignment..."
  sleep 1
done

echo "Role assignment successful"

identity_id="$(
  az identity show              \
    --name "${group}-identity"  \
    --resource-group "${group}" \
    --output tsv --query "[id]"
  )"

# boot vm
az vm create \
  --name "${vm_name}"                   \
  --resource-group "${group}"           \
  --assign-identity "${identity_id}"    \
  --size "${vm_size}"                   \
  --os-disk-size-gb "${os_size}"        \
  --image "${img_id}"                   \
  --admin-username "${USER}"            \
  --location "${location:-"westus2"}"   \
  --storage-sku "Premium_LRS"           \
  --generate-ssh-keys
  # This only works if `ssh-agent` is running
  # --ssh-key-values "$(ssh-add -L)"

