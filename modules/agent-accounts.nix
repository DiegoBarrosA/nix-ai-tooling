# Per-account launchers for opencode and Google Antigravity (agy).
# Each account reads its API key from a file (for example a sops secret) at
# launch and gets its own data/config/HOME dir, so accounts never share state.
#   opencode-<name>, opencode-<name>-acp   (key in <envVar>; own XDG dirs)
#   agy-<name>, agy-<name>-acp             (key in GEMINI_API_KEY; own HOME)
# Antigravity needs modelProvider=gemini in settings.json or the key is ignored;
# the launcher seeds that file when it is missing. ACP launchers appear only
# when the matching package option is set.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.agent-accounts;
  mkLauncher = import ./account-launcher.nix { inherit pkgs lib; };
  root = name: "${config.home.homeDirectory}/.config/agent-accounts/${name}";
  agyHome = name: "${root "antigravity-${name}"}/home";
  agySettings = ''
    __s="$HOME/.gemini/antigravity-cli/settings.json"
    if [ ! -e "$__s" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$__s")"
      echo '{"modelProvider":"gemini"}' > "$__s"
    fi
  '';
in
{
  options.programs.agent-accounts = {
    opencodePackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "opencode package. Required when opencode accounts exist.";
    };
    antigravityCliPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "antigravity-cli package (binary `agy`). Required when antigravity accounts exist.";
    };
    antigravityAcpPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "antigravity-acp package (binary `agy_acp_server`). Adds agy-<name>-acp launchers.";
    };

    opencode = lib.mkOption {
      default = { };
      description = "opencode accounts, keyed by name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            keyFile = lib.mkOption {
              type = lib.types.str;
              description = "File holding the provider API key.";
            };
            envVar = lib.mkOption {
              type = lib.types.str;
              default = "OPENCODE_API_KEY";
              description = "Environment variable opencode reads the key from.";
            };
          };
        }
      );
    };

    antigravity = lib.mkOption {
      default = { };
      description = "Antigravity CLI accounts, keyed by name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.keyFile = lib.mkOption {
            type = lib.types.str;
            description = "File holding the Gemini API key.";
          };
        }
      );
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.opencode == { } || cfg.opencodePackage != null;
        message = "programs.agent-accounts.opencodePackage must be set when opencode accounts exist.";
      }
      {
        assertion = cfg.antigravity == { } || cfg.antigravityCliPackage != null;
        message = "programs.agent-accounts.antigravityCliPackage must be set when antigravity accounts exist.";
      }
    ];

    home.packages =
      lib.concatLists (
        lib.mapAttrsToList (
          name: a:
          let
            mk = suffix: exe: mkLauncher {
              name = "opencode-${name}${suffix}";
              inherit exe;
              env.${a.envVar} = a.keyFile;
              fixed = {
                XDG_CONFIG_HOME = "${root "opencode-${name}"}/config";
                XDG_DATA_HOME = "${root "opencode-${name}"}/data";
              };
            };
          in
          lib.optionals (cfg.opencodePackage != null) [
            (mk "" "${cfg.opencodePackage}/bin/opencode")
            (mk "-acp" "${cfg.opencodePackage}/bin/opencode acp")
          ]
        ) cfg.opencode
      )
      ++ lib.concatLists (
        lib.mapAttrsToList (
          name: a:
          let
            mk = suffix: exe: mkLauncher {
              name = "agy-${name}${suffix}";
              inherit exe;
              env.GEMINI_API_KEY = a.keyFile;
              fixed.HOME = agyHome name;
              pre = agySettings;
            };
          in
          lib.optionals (cfg.antigravityCliPackage != null) [ (mk "" "${cfg.antigravityCliPackage}/bin/agy") ]
          ++ lib.optionals (cfg.antigravityAcpPackage != null) [
            (mk "-acp" "${cfg.antigravityAcpPackage}/bin/agy_acp_server")
          ]
        ) cfg.antigravity
      );
  };
}
