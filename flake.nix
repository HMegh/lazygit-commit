{
  description = "GitHub Copilot commit messages for lazygit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = eachSystem (system: {
        default = nixpkgs.legacyPackages.${system}.writeShellApplication {
          name = "lazygit-aicommit";
          runtimeInputs = with nixpkgs.legacyPackages.${system}; [ coreutils curl git jq ];
          text = builtins.readFile ./lazygit-aicommit.sh;
        };
      });

      homeManagerModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs."lazygit-aicommit";
          package = self.packages.${pkgs.system}.default;
        in
        {
          options.programs."lazygit-aicommit" = {
            enable = lib.mkEnableOption "Copilot commit messages for lazygit";
            package = lib.mkOption {
              type = lib.types.package;
              default = package;
              description = "The lazygit-aicommit package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];
            programs.lazygit.enable = lib.mkDefault true;
            programs.lazygit.settings.customCommands = lib.mkAfter [
              {
                key = "<c-u>";
                context = "files";
                description = "Generate Copilot commit";
                prompts = [
                  {
                    type = "menuFromCommand";
                    key = "Commit";
                    title = "Copilot commit";
                    command = "${cfg.package}/bin/lazygit-aicommit";
                  }
                ];
                command = "git commit -m \"{{.Form.Commit}}\"";
                output = "terminal";
                loadingText = "Generating Copilot commit...";
              }
              {
                key = "<c-g>";
                context = "global";
                description = "Copilot authentication";
                prompts = [
                  {
                    type = "menu";
                    key = "Action";
                    title = "Copilot";
                    options = [
                      { name = "Login"; value = "login"; }
                      { name = "Logout"; value = "logout"; }
                      { name = "Status"; value = "status"; }
                    ];
                  }
                ];
                command = "${cfg.package}/bin/lazygit-aicommit {{.Form.Action}}";
                output = "terminal";
              }
            ];
          };
        };
    };
}
