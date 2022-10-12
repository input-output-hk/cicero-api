{
  description = "API bindings to Cicero";

  inputs = {
    haskell-nix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskell-nix/nixpkgs-unstable";
    flake-utils.follows = "haskell-nix/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, haskell-nix }@inputs: let
    supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];

    ifExists = p: if builtins.pathExists p then p else null;

    flake = { self, nixpkgs, flake-utils, haskell-nix }: flake-utils.lib.eachSystem supportedSystems (evalSystem: let
      packagesBySystem = builtins.listToAttrs (map (system: {
        name = system;

        value = let
          materializedRelative = "/nix/materialized/${system}";

          materializedFor = component: ifExists (./. + materializedRelative + "/${component}");

          pkgs = import nixpkgs {
            inherit system;
            overlays = [ haskell-nix.overlay ];
            inherit (haskell-nix) config;
          };

          tools = {
            cabal = {
              inherit (project) index-state evalSystem;
              version = "3.8.1.0";
              materialized = materializedFor "cabal";
            };
            hoogle = {
              inherit (project) index-state evalSystem;
              version = "5.0.18.3";
              materialized = materializedFor "hoogle";
            };
            haskell-language-server = {
              inherit (project) index-state evalSystem;
              version = "1.7.0.0";
              materialized = materializedFor "haskell-language-server";
            };
            hlint = {
              inherit (project) index-state evalSystem;
              version = "3.4.1";
              materialized = materializedFor "hlint";
            };
          };

          project = pkgs.haskell-nix.cabalProject' {
            inherit evalSystem;
            src = ./.;
            compiler-nix-name = "ghc924";
            shell.tools = tools;
            materialized = materializedFor "project";
          };

          tools-built = project.tools tools;
        in {
          inherit pkgs project;

          update-all-materialized = evalPkgs.writeShellScript "update-all-materialized-${system}" ''
            set -eEuo pipefail
            mkdir -p .${materializedRelative}
            cd .${materializedRelative}
            echo "Updating project materialization" >&2
            ${project.plan-nix.passthru.generateMaterialized} project
            ${evalPkgs.lib.concatStringsSep "\n" (map (tool: ''
              echo "Updating ${tool} materialization" >&2
              ${tools-built.${tool}.project.plan-nix.passthru.generateMaterialized} ${tool}
            '') (builtins.attrNames tools-built))}
          '';
        };
      }) supportedSystems);

      inherit (packagesBySystem.${evalSystem}) project pkgs;

      evalPkgs = pkgs;

      flake = project.flake {};
    in flake // rec {
      defaultPackage = packages.default;

      packages = flake.packages // {
        default = flake.packages."cicero-api:exe:cicero-cli";
      };

      defaultApp = apps.default;

      apps = flake.apps // {
        default = flake.apps."cicero-api:exe:cicero-cli";

        update-all-materialized = {
          type = "app";

          program = (pkgs.writeShellScript "update-all-materialized" ''
            set -eEuo pipefail
            cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
            ${pkgs.lib.concatStringsSep "\n" (map (system: ''
              echo "Updating materialization for ${system}" >&2
              ${packagesBySystem.${system}.update-all-materialized}
            '') supportedSystems)}
          '').outPath;
        };
      };
      hydraJobs = self.packages.${evalSystem};
    });
  in flake inputs // {
    hydraJobs = { nixpkgs ? inputs.nixpkgs, flake-utils ? inputs.flake-utils, haskell-nix ? inputs.haskell-nix }@overrides: let
      flake' = flake (inputs // overrides // { self = flake'; });
      evalSystem = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${evalSystem};
    in flake'.hydraJobs // {
      forceNewEval = pkgs.writeText "forceNewEval" (self.rev or self.lastModified);
      required = pkgs.releaseTools.aggregate {
        name = "cicero-api";
        constituents = builtins.concatMap (system:
          map (x: "${x}.${system}") (builtins.attrNames flake'.hydraJobs)
        ) supportedSystems;
      };
    };
  };
}
