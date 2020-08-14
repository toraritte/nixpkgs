# From an end-user configuration file (`configuration.nix'), build a NixOS
# configuration object (`config') from which we can retrieve option
# values.

# !!! Please think twice before adding to this argument list!
# Ideally eval-config.nix would be an extremely thin wrapper
# around lib.evalModules, so that modular systems that have nixos configs
# as subcomponents (e.g. the container feature, or nixops if network
# expressions are ever made modular at the top level) can just use
# types.submodule instead of using eval-config.nix
{ # !!! system can be set modularly, would be nice to remove
  # LAND https://nixos.org/nix/manual/#:~:text=builtins.currentSystem
  # LAND > The  built-in value  currentSystem evaluates  to the
  # LAND > Nix platform identifier for  the Nix installation on
  # LAND > which  the expression  is being  evaluated, such  as
  # LAND > "i686-linux" or "x86_64-darwin".
  # LAND Relevant: https://github.com/NixOS/nix/pull/3071
  system ? builtins.currentSystem
, # !!! is this argument needed any more? The pkgs argument can
  # be set modularly anyway.
  pkgs ? null
, # !!! what do we gain by making this configurable?
  baseModules ? import ../modules/module-list.nix
, # !!! See comment about args in lib/modules.nix
  extraArgs ? {}
, # !!! See comment about args in lib/modules.nix
  specialArgs ? {}
, modules
, # !!! See comment about check in lib/modules.nix
  check ? true
, prefix ? []
, lib ? import ../../lib
}:

let extraArgs_ = extraArgs; pkgs_ = pkgs;
    extraModules = let e = builtins.getEnv "NIXOS_EXTRA_MODULE_PATH";
                   in if e == "" then [] else [(import e)];
in

let
  pkgsModule = rec {
    _file = ./eval-config.nix;
    key = _file;
    config = {
      # Explicit `nixpkgs.system` or `nixpkgs.localSystem` should override
      # this.  Since the latter defaults to the former, the former should
      # default to the argument. That way this new default could propagate all
      # they way through, but has the last priority behind everything else.
      nixpkgs.system = lib.mkDefault system;
      # LAND When `eval-config.nix` is called from
      # LAND `nixos/maintainers/scripts/azure-new/examples/basic/image.nix`,
      # LAND `nixpkgs.system`  ends  up  as  the
      # LAND attribute set
      # LAND ```nix
      # LAND {
      # LAND   _type = "override";
      # LAND   priority = 1000;
      # LAND   content = "x86_64-linux";
      # LAND };
      ```

      # Stash the value of the `system` argument. When using `nesting.children`
      # we want to have the same default value behavior (immediately above)
      # without any interference from the user's configuration.
      nixpkgs.initialSystem = system;

      # LAND Figure out `lib.mkIf`
      # LAND https://hyp.is/7yG5_N3cEeqdRa_GOPH1ew/nixos.org/nixpkgs/manual/
      _module.args.pkgs = lib.mkIf (pkgs_ != null) (lib.mkForce pkgs_);
    };
  };

in rec {

  # Merge the option definitions in all modules, forming the full
  # system configuration.
  inherit (lib.evalModules {
    inherit prefix check;
    modules = baseModules ++ extraModules ++ [ pkgsModule ] ++ modules;
    args = extraArgs;
    specialArgs =
      { modulesPath = builtins.toString ../modules; } // specialArgs;
  }) config options _module;

  # These are the extra arguments passed to every module.  In
  # particular, Nixpkgs is passed through the "pkgs" argument.
  extraArgs = extraArgs_ // {
    inherit baseModules extraModules modules;
  };

  inherit (_module.args) pkgs;
}
