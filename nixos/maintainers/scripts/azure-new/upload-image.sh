#!/usr/bin/env bash

####################################################
# HELPERS                                          #
####################################################
show_id() {
  az $1 show \
    --resource-group "${group}" \
    --name "${img_name}"        \
    --output tsv --query "[id]" 
}

usage() {
  echo '-g --resource-group REQUIRED Created if does  not exist. Will'
  echo '                             house a new disk and the created'
  echo '                             image.'
  echo ''
  echo '-n --image-name     REQUIRED The  name of  the image  created'
  echo '                             (and also of the new disk).'
  echo ''
  echo '-i --image-nix      Nix  expression   to  build  the'
  echo '                    image. Default value:'
  echo '                    "./examples/basic/image.nix".'
  echo ''
  echo '-l --location       Values from `az account list-locations`.'
  echo '                    Default value: "westus2".'
}
 
####################################################
# SWITCHES                                         #
####################################################

# https://unix.stackexchange.com/a/204927/85131
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--image-nix)
      image_nix="$2"
      ;;
    -l|--location)
      location="$2"
      ;;
    -g|--resource-group)
      group="$2"
      ;;
    -n|--image-name)
      img_name="$2"
      ;;
    -h|--help)
      usage
      exit 1
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

if [ -z "${img_name}" ] || [ -z "${group}" ];
then
  printf "************************************\n"
  printf "* Error: Missing required argument *\n"
  printf "************************************\n"
  usage
  exit 1
fi

####################################################
# AZ LOGIN and BUILD THE IMAGE                     #
####################################################

# Making  sure  that  one   is  logged  in  (to  avoid
# surprises down the line).
if [ $(az account list 2> /dev/null) = [] ];
then
  echo
  echo '********************************************************'
  echo '* Please log  in to  Azure by  typing "az  login", and *'
  echo '* repeat the "./upload-image.sh" command.              *'
  echo '********************************************************'
  exit 1
fi

nix-build                                 \
  --out-link "azure"                      \
  "${image_nix:-"./examples/basic/image.nix"}"

if ! az group show --resource-group "${group}" &>/dev/null;
then
  az group create     \
    --name "${group}" \
    --location "${location:-"westus2"}"
fi

####################################################
# PUT IMAGE INTO AZURE CLOUD                       #
####################################################

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# NOTE: The  disk   access  token   song/dance  is
#       tedious  but allows  us  to upload  direct
#       to  a  disk  image thereby  avoid  storage
#       accounts (and naming them) entirely!

if ! show_id "disk" &>/dev/null;
then

  img_file="$(readlink -f ./azure/disk.vhd)"
  bytes="$(stat -c %s ${img_file})"

  az disk create                \
    --resource-group "${group}" \
    --name "${img_name}"        \
    --for-upload true           \
    --upload-size-bytes "${bytes}"

  timeout=$(( 60 * 60 )) # disk access token timeout
  sasurl="$(\
    az disk grant-access               \
      --access-level Write             \
      --resource-group "${group}"      \
      --name "${img_name}"             \
      --duration-in-seconds ${timeout} \
      --output tsv                     \
      --query "[accessSas]"
  )"
  # the --query part is not necessary (one column output)

  azcopy copy "${img_file}" "${sasurl}" \
    --blob-type PageBlob 
    
  # https://docs.microsoft.com/en-us/cli/azure/disk?view=azure-cli-latest#az-disk-revoke-access
  # > Revoking the SAS will  change the state of
  # > the managed  disk and allow you  to attach
  # > the disk to a VM.
  az disk revoke-access         \
    --resource-group "${group}" \
    --name "${img_name}"
fi

if ! show_id "image" &>/dev/null;
then

  az image create                \
    --resource-group "${group}"  \
    --name "${img_name}"         \
    --source "$(show_id "disk")" \
    --os-type "linux" >/dev/null
fi

echo "$(show_id "image")"
