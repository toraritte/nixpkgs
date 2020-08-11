# Deploy custom images and NixOS VMs to Azure

## 1. Demo

Here's a demo of this being used: https://asciinema.org/a/euXb9dIeUybE3VkstLWLbvhmp

## 2. Before using

The provided [`shell.nix`](./shell.nix) and [`image.nix`](./examples/basic/image.nix) will import the cloned Nixpkgs repo's [`default.nix`](../../../../default.nix). 

As a consequence, depending on the current state of Nixpkgs, `nix-shell` and the Azure image may not build at all.  The former can be resolved by the suggestions below, but the latter may still fail (when [`upload-image.sh`](./upload-image.sh) calls [`image.nix`](./examples/basic/image.nix)).

### 2.1 `nix-shell` won't build

1. Try using the channel of your system

```text
$ nix-shell --arg pkgs 'import <nixpkgs> {}'
```

2. or find a stable Nixpkgs version via commit hash (such 0c0fe6d for example)

```text
$ nix-shell --arg pkgs 'import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/0c0fe6d85b92c4e992e314bd6f9943413af9a309.tar.gz") {}'
```

### 2.2 Image build fails

[`system.nix`](./examples/basic/system.nix) (called by [`image.nix`](./examples/basic/image.nix)) relies on the `virtualisation.azureImage` (defined in [`azure-image.nix`](https://github.com/NixOS/nixpkgs/blob/066c604eec6089e25aa5c4cc933decebdf8aa626/nixos/modules/virtualisation/azure-image.nix)?) attribute, that is not yet present in the 20.03 channel, ruling out option 1 in section 2.1 above.

See also [issue #86005](https://github.com/NixOS/nixpkgs/issues/86005) when getting `The option `virtualisation.azureImage` defined in ... does not exist`.

## 3. Usage

### 3.1 Enter `nix-shell`

```text
$ nix-shell
```

See section 2.1 on how to provide a specific Nixpkgs version to `nix-shell`.

### 3.2 Create and upload image

```text
[..]$ ./upload-image.sh --resource-group "my-rg" --image-name "my-image"
```

See other options and default values via `./upload-image.sh --help`.

### 3.3 Start virtual machine

Post the example boot-vm.sh command here but implement calling by image name first not just id.

this is a note
```text
[..]$ ./upload-image.sh --resource-group "my-rg" --image-name "my-image"
--boot-sh-opts "resource-group=my-vms-rg;vm-name=sftb-nixos-freeswitch-noconfigjusttest-vm;"
```

Have a section detailing the quirks that can only be changed by changing the scripts themselves. (e.g., disks, identitys, etc.)
Mention that leftover artifact cleanup is a manual business. (possibly a good opportunity for a third script - or just add extra options. Do research - is identity needed after the VM creation or can be discarded like the disks used for upload?

This is meant to be an example image that you can copy into your own
project and modify to your own needs. Notice that the example image
includes a built-in test user account, which by default uses your
`~/.ssh/id_ed25519.pub` as an `authorized_key`.

Build and upload the image
```shell
$ ./upload-image.sh ./examples/basic/image.nix

...
+ attr=azbasic
+ nix-build ./examples/basic/image.nix --out-link azure
/nix/store/qdpzknpskzw30vba92mb24xzll1dqsmd-azure-image
...
95.5 %, 0 Done, 0 Failed, 1 Pending, 0 Skipped, 1 Total, 2-sec Throughput (Mb/s): 932.9565
...
/subscriptions/aff271ee-e9be-4441-b9bb-42f5af4cbaeb/resourceGroups/nixos-images/providers/Microsoft.Compute/images/azure-image-todo-makethisbetter
```

Take the output, boot an Azure VM:

```
img="/subscriptions/.../..." # use output from last command
./boot-vm.sh "${img}"
...
=> booted
```

## Future Work

1. If the user specifies a hard-coded user, then the agent could be removed.
   Probably has security benefits; definitely has closure-size benefits.
   (It's likely the VM will need to be booted with a special flag. See:
   https://github.com/Azure/azure-cli/issues/12775 for details.)
