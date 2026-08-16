# Happier configuration module for Home Manager
# Manages Happier CLI, daemon, and integration with AI tools
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.happier-config;

  # Build the daemon start script with secrets loaded
  daemonStartScript = pkgs.writeShellScript "happier-daemon-start" ''
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: path: ''
        if [ -r "${path}" ]; then
          export ${name}="$(${pkgs.coreutils}/bin/cat "${path}")"
        fi
      '') cfg.secretEnv
    )}

    # Start the daemon in the foreground (systemd manages it)
    exec ${cfg.package}/bin/happier daemon start-sync
  '';
in
{
  options.programs.happier-config = {
    enable = lib.mkEnableOption "Happier configuration management";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.happy-coder;
      defaultText = lib.literalExpression "pkgs.happy-coder";
      description = "The Happier package to use.";
    };

    # Server configuration
    server = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "happier-cloud";
        description = "Name of the server profile.";
      };

      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Server URL (null for Happier Cloud).";
      };

      webappUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Webapp URL (null for Happier Cloud).";
      };

      useByDefault = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to use this server by default.";
      };
    };

    # Daemon configuration
    daemon = {
      enable = lib.mkEnableOption "Happier daemon as a systemd user service";

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether the daemon should start automatically on login.";
      };
    };

    # Providers to configure
    providers = {
      claude = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Claude Code provider integration.";
        };
      };

      opencode = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable OpenCode provider integration.";
        };
      };

      jcode = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Jcode provider integration.";
        };
      };

      codex = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Codex provider integration.";
        };
      };

      gemini = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Gemini provider integration.";
        };
      };
    };

    # Secret environment variables
    secretEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Files whose contents should be exported into the environment before running Happier.";
    };

    # Extra configuration
    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra configuration to merge into Happier config.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Install Happier package
        home.packages = [ cfg.package ];

        # Create systemd user service for the daemon
        systemd.user.services.happier-daemon = lib.mkIf cfg.daemon.enable {
          Unit = {
            Description = "Happier daemon (mobile AI tool control)";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };

          Service = {
            ExecStart = "${daemonStartScript}";
            Restart = "on-failure";
            RestartSec = 5;
          };

          Install.WantedBy = [ "default.target" ];
        };

        # Create shell aliases for common Happier commands
        home.shellAliases = {
          h = "happier";
          hs = "happier session";
          hsl = "happier session list";
          hsc = "happier session create";
        };
      }

      # Configure server if URL is provided
      (lib.mkIf (cfg.server.url != null) {
        # Note: Happier server config is typically done via CLI
        # This is a placeholder for future declarative config support
      })

      # Configure providers
      (lib.mkIf cfg.providers.claude.enable {
        # Ensure Claude Code is available (claude-code-config only writes config)
        home.packages = lib.optional config.programs.claude-code-config.enable pkgs.claude-code;
      })

      # OpenCode is NOT added here: opencode-config installs the wrapped
      # opencode-with-secrets binary, and adding plain pkgs.opencode to the same
      # home.packages would make buildEnv fail on the conflicting bin/opencode.
    ]
  );
}
