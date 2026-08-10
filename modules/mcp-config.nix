# Shared MCP server configuration module for Home Manager
# Provides a common MCP server definition used by opencode, zed, claude-code, cursor, antigravity
{
  config,
  lib,
  pkgs,
  customPkgs,
  ...
}:
let
  cfg = config.programs.mcp-config;

  # Helper to convert env var syntax from internal format to standard MCP format
  # {env:VAR} -> ${VAR}
  convertEnvSyntax = str: builtins.replaceStrings [ "{env:" "}" ] [ "\${" "}" ] str;

  # Convert env attrset values
  convertEnvAttrs =
    env: lib.mapAttrs (_: v: if builtins.isString v then convertEnvSyntax v else toString v) env;

  # Build server entry in standard MCP format (for Claude Code, Cursor, Antigravity)
  # Standard format: { command = "string", args = [...], env = { KEY = "${VAR}" } }
  # or for SSE/HTTP servers: { url = "string"; }
  toStandardServer =
    name: srv:
    if (srv.url or null) != null && (srv.command or null) == null then
      { url = srv.url; } // lib.optionalAttrs ((srv.env or { }) != { }) { env = convertEnvAttrs srv.env; }
    else
      let
        cmdList = if builtins.isList srv.command then srv.command else [ srv.command ];
        hasArgs = (srv.args or [ ]) != [ ] || builtins.length cmdList > 1;
        combinedArgs =
          (if builtins.length cmdList > 1 then builtins.tail cmdList else [ ]) ++ (srv.args or [ ]);
      in
      {
        command = builtins.head cmdList;
      }
      // lib.optionalAttrs hasArgs { args = combinedArgs; }
      // lib.optionalAttrs ((srv.env or { }) != { }) { env = convertEnvAttrs srv.env; };
in
{
  options.programs.mcp-config = {
    enable = lib.mkEnableOption "shared MCP server configuration";

    # mcp-nixos
    mcpNixos = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable mcp-nixos MCP server.";
      };
    };

    # JobSpy MCP (job search via LinkedIn, Indeed, Google Jobs)
    jobspy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable JobSpy MCP server for job searching.";
      };
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether opencode should auto-start this server on launch.
          Set to false to keep it defined but lazily disabled (reduces
          context creep); enable on demand via `opencode mcp`.
        '';
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = customPkgs.jobspy-mcp;
        defaultText = lib.literalExpression "customPkgs.jobspy-mcp";
        description = "The JobSpy MCP package to use.";
      };
    };

    # GitHub MCP
    github = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable GitHub MCP server.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.github-mcp-server;
        defaultText = lib.literalExpression "pkgs.github-mcp-server";
        description = "The GitHub MCP package to use.";
      };
    };

    # Playwright MCP (web scraping/browser automation)
    playwright = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Playwright MCP server for web scraping.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.playwright-mcp;
        defaultText = lib.literalExpression "pkgs.playwright-mcp";
        description = "The Playwright MCP package to use.";
      };
      browserPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Custom browser executable path for Playwright. If null, uses Playwright's default browser.";
        example = lib.literalExpression ''
          "${pkgs.firefox-devedition}/bin/firefox"
        '';
      };
    };

    # Thunderbird MCP (email integration)
    thunderbird = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Thunderbird MCP server for email integration.";
      };
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether opencode should auto-start this server on launch.
          Set to false to keep it defined but lazily disabled (reduces
          context creep); enable on demand via `opencode mcp`.
        '';
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.thunderbird-mcp;
        defaultText = lib.literalExpression "pkgs.thunderbird-mcp";
        description = "The Thunderbird MCP package to use.";
      };
    };

    # ZenNotes MCP — native vault MCP via the `zn mcp` CLI
    # Exposes ~/Notes (or any ZenNotes vault) to AI tools as a knowledge base.
    zennotes = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable the ZenNotes MCP server (zn mcp).
          Gives all AI tools structured read/write access to the Notes vault.
        '';
      };
      cliPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/.config/ZenNotes/cli/zen";
        description = "Path to the ZenNotes CLI binary (zn).";
      };
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether tools that support per-server autostart (OpenCode, JCode) should
          start this server automatically. Set false to enable on demand and reduce
          startup latency.
        '';
      };
    };

    # Supermercados CL MCP (Chilean supermarket price search/comparison)
    # https://github.com/NLACE-COM/mcp-supermercados-cl
    # No nix package published upstream; runs via npx like the notes server.
    supermercados = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable the Supermercados CL MCP server: search products, compare
          prices, and build shopping lists across Chilean supermarket chains
          (Jumbo, Santa Isabel, Unimarc, Tottus, Lider). Runs locally over
          stdio; no server-side credentials required.
        '';
      };
      command = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "npx"
          "-y"
          "mcp-supermercados-cl"
        ];
        description = "Command to run the Supermercados CL MCP server.";
      };
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether tools that support per-server autostart (OpenCode, JCode) should
          start this server automatically. Set false to enable on demand and reduce
          startup latency.
        '';
      };
    };

    # Extra MCP servers
    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional MCP servers.";
    };

    # Output: Standard MCP format for other tools (read-only, set by config)
    standardFormat = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      readOnly = true;
      description = ''
        MCP servers in standard format for Claude Code, Cursor, and Antigravity.
        This is automatically generated from the enabled servers.
        Format: { mcpServers = { name = { command = "..."; args = [...]; env = {...}; }; }; }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.mcp = {
      enable = true;
      servers = lib.filterAttrs (_: v: v != null) (
        lib.optionalAttrs cfg.mcpNixos.enable {
          nixos = {
            command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
          };
        }
        // lib.optionalAttrs cfg.jobspy.enable {
          jobspy = {
            command = "${cfg.jobspy.package}/bin/jobspy-mcp";
          };
        }
        // lib.optionalAttrs cfg.github.enable {
          github = {
            command = "${cfg.github.package}/bin/github-mcp-server";
            env = {
              GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_TOKEN}";
            };
          };
        }
        // lib.optionalAttrs cfg.playwright.enable {
          playwright = {
            command = "${cfg.playwright.package}/bin/playwright-mcp";
          }
          // lib.optionalAttrs (cfg.playwright.browserPath != null) {
            args = [
              "--executable-path"
              cfg.playwright.browserPath
            ];
          };
        }
        // lib.optionalAttrs cfg.thunderbird.enable {
          thunderbird = {
            command = "${cfg.thunderbird.package}/bin/thunderbird-mcp";
          };
        }
        // lib.optionalAttrs cfg.zennotes.enable {
          notes = {
            command = cfg.zennotes.cliPath;
            args = [ "mcp" ];
          } // lib.optionalAttrs (!cfg.zennotes.autostart) {
            enabled = false;
          };
        }
        // lib.optionalAttrs cfg.supermercados.enable {
          supermercados = {
            command = builtins.head cfg.supermercados.command;
            args = builtins.tail cfg.supermercados.command;
          } // lib.optionalAttrs (!cfg.supermercados.autostart) {
            enabled = false;
          };
        }
        // cfg.extraMcpServers
      );
    };

    # Output: Standard MCP format for Claude Code, Cursor, Antigravity
    # These tools use { command = "string", args = [...], env = { KEY = "${VAR}" } }
    programs.mcp-config.standardFormat = {
      mcpServers = lib.mapAttrs toStandardServer config.programs.mcp.servers;
    };

    home.packages =
      lib.optional cfg.mcpNixos.enable pkgs.mcp-nixos
      ++ lib.optional cfg.jobspy.enable cfg.jobspy.package
      ++ lib.optional cfg.github.enable cfg.github.package
      ++ lib.optional cfg.playwright.enable cfg.playwright.package
      ++ lib.optional cfg.thunderbird.enable cfg.thunderbird.package;
  };
}
