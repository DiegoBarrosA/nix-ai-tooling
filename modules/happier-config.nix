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

    # Point the Claude Agent SDK at the Nix-managed Claude Code binary.
    # Systemd user services don't reliably carry ~/.nix-profile/bin on PATH,
    # which makes happier's remote claude dispatch fail to detect it.
    ${lib.optionalString cfg.providers.claude.enable ''
      export HAPPIER_CLAUDE_PATH="${pkgs.claude-code}/bin/claude"
    ''}

    # Same PATH problem as Claude above: the daemon spawns `codex` for
    # remote/phone sessions, and without ~/.nix-profile/bin on PATH it
    # can't find it, which surfaces client-side as an endless
    # "Reconnecting..." loop instead of a clear error.
    ${lib.optionalString cfg.providers.codex.enable ''
      export HAPPIER_CODEX_TUI_BIN="${pkgs.codex}/bin/codex"
    ''}

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
        # Install Happier package, and Claude Code itself (claude-code-config
        # only writes config, it doesn't install the binary).
        home.packages = [
          cfg.package
        ]
        ++ lib.optional config.programs.claude-code-config.enable pkgs.claude-code;

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

        # Create shell aliases for common Happier commands.
        # AI tool aliases route through Happier by default so sessions are
        # captured by the daemon and accessible from phone/web/desktop.
        home.shellAliases =
          {
            h = "happier";
            hs = "happier session";
            hsl = "happier session list";
            hsc = "happier session create";
          }
          // lib.optionalAttrs cfg.providers.claude.enable { claude = "happier claude"; }
          // lib.optionalAttrs cfg.providers.opencode.enable { opencode = "happier opencode"; }
          // lib.optionalAttrs cfg.providers.jcode.enable { jcode = "happier jcode"; }
          // lib.optionalAttrs cfg.providers.codex.enable { codex = "happier codex"; }
          // lib.optionalAttrs cfg.providers.gemini.enable { gemini = "happier gemini"; };
      }

      # Configure server if URL is provided
      (lib.mkIf (cfg.server.url != null) {
        # Note: Happier server config is typically done via CLI
        # This is a placeholder for future declarative config support
      })

      # Configure providers
      (lib.mkIf cfg.providers.claude.enable {
        # Point the Claude Agent SDK at the Nix-managed Claude Code binary for
        # interactive `happier`/`happier claude` invocations too. On Nix the
        # `claude` binary is a compiled wrapper with no cli.js entrypoint, so
        # happier's built-in SDK auto-detection fails with "Claude Code is not
        # installed (or not detectable)". The daemon start script already sets
        # this for daemon-spawned sessions; this covers foreground CLI runs.
        home.sessionVariables.HAPPIER_CLAUDE_PATH = "${pkgs.claude-code}/bin/claude";
      })

      # Codex: same PATH fix as Claude above, for foreground CLI runs.
      (lib.mkIf cfg.providers.codex.enable {
        home.sessionVariables.HAPPIER_CODEX_TUI_BIN = "${pkgs.codex}/bin/codex";
      })

      # OpenCode is NOT added here: opencode-config installs the wrapped
      # opencode-with-secrets binary, and adding plain pkgs.opencode to the same
      # home.packages would make buildEnv fail on the conflicting bin/opencode.
    ]
  );
}
