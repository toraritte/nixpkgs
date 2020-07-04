#!/usr/bin/env bash
set -euo pipefail
set -x

# if there's no $2, use the image.nix in the repo
image_nix="${2:-"./examples/basic/image.nix"}"

nix-build "${image_nix}" --out-link "azure"

group="sftb-nixos-images-rg"
location="westus2"
img_name="nixos-"${1}"-image"
img_file="$(readlink -f ./azure/disk.vhd)"

show_id() {
  az $1 show \
    --resource-group "${group}" \
    --name "${img_name}"        \
    --output tsv --query "[id]" 
}
 
 if ! az group show --resource-group "${group}" &>/dev/null; then
   az group create --name "${group}" --location "${location}"
 fi
 
 # note: the disk access token song/dance is tedious
 # but allows us to upload direct to a disk image
 # thereby avoid storage accounts (and naming them) entirely!
 if ! show_id "disk" &>/dev/null; then
 # if ! az disk show --resource-group "${group}" --name "${img_name}" &>/dev/null; then
   bytes="$(stat -c %s ${img_file})"
   az disk create \
     --resource-group "${group}" \
     --name "${img_name}" \
     --for-upload true --upload-size-bytes "${bytes}"
 
   timeout=$(( 60 * 60 )) # disk access token timeout
   sasurl="$(\
     az disk grant-access \
       --access-level Write \
       --resource-group "${group}" \
       --name "${img_name}" \
       --duration-in-seconds ${timeout} \
       --output tsv --query "[accessSas]"
   )"
   # the --query part is not necessary (one column output)
 
   azcopy copy "${img_file}" "${sasurl}" \
     --blob-type PageBlob 
     
   # See public hypethes.is not at https://docs.microsoft.com/en-us/cli/azure/disk?view=azure-cli-latest#az-disk-revoke-access why this is important
   az disk revoke-access \
     --resource-group "${group}" \
     --name "${img_name}"
 fi

if ! show_id "image" &>/dev/null; then

  az image create \
    --resource-group "${group}" \
    --name "${img_name}" \
    --source "$(show_id "disk")" \
    --os-type "linux" >/dev/null
fi

echo "$(show_id "image")"
