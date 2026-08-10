# Claude Desktop MCP configuration module for Home Manager
# Writes resolved MCP server configs to ~/.config/Claude/claude_desktop_config.json
# (the Linux path for Claude Desktop).
#
# Unlike Claude Code, Claude Desktop is a GUI app and does NOT expand ${VAR}
# references from the shell environment. This module reads secrets from
# /run/secrets/ files at home-manager activation time and substitutes them
# directly into the JSON, so the file contains real credentials.
#
# Usage:
#   programs.claude-desktop-config = {
#     enable = true;
#     excludeServers = ["netsuite"];  # omit servers that shouldn't auto-start
#     extraMcpServers = {
#       jira = {
#         command = "${customPkgs.jira-cloud-mcp}/bin/jira-cloud-mcp";
#         env.JIRA_BASE_URL = "\${JIRA_BASE_URL}";
#       };
#     };
#     secretEnv = {
#       JIRA_BASE_URL = /run/secrets/jira-base-url;
#     };
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude-desktop-config;
  mcpCfg = config.programs.mcp-config;
  jsonFormat = pkgs.formats.json { };

  # Start from the shared MCP registry, minus any servers we want to exclude,
  # then let extraMcpServers override/add entries (right side wins on conflict).
  filteredStandardServers = lib.filterAttrs
    (name: _: !builtins.elem name cfg.excludeServers)
    (mcpCfg.standardFormat.mcpServers or { });

  mcpServersConfig = filteredStandardServers // cfg.extraMcpServers;

  # JSON template stored in Nix store — env values contain ${VAR} placeholders
  # that the activation script resolves via envsubst + /run/secrets/ files.
  mcpServersJson = jsonFormat.generate "claude-desktop-mcp-servers.json" {
    mcpServers = mcpServersConfig;
  };

  # Build the shell snippet that exports each secret from its file.
  # Empty or placeholder values are skipped with a loud warning.
  secretEnvNames = lib.attrNames cfg.secretEnv;
  placeholderMatch = lib.concatMapStringsSep " | " (
    p: lib.escapeShellArg p
  ) cfg.secretPlaceholders;
  secretLoadScript = lib.concatMapStringsSep "\n" (name: ''
    if [ -r "${toString cfg.secretEnv.${name}}" ]; then
      __val="$(${pkgs.coreutils}/bin/cat "${toString cfg.secretEnv.${name}}" | ${pkgs.coreutils}/bin/tr -d '\n')"
      __trimmed="$(printf '%s' "$__val" | ${pkgs.coreutils}/bin/tr -d '[:space:]')"
      case "$__trimmed" in
        "" )
          echo "claude-desktop: WARNING: secret '${name}' (${toString cfg.secretEnv.${name}}) is empty; skipping." >&2
          ;;
        ${placeholderMatch} )
          echo "claude-desktop: WARNING: secret '${name}' (${toString cfg.secretEnv.${name}}) holds a placeholder; skipping." >&2
          ;;
        * )
          export ${name}="$__val"
          ;;
      esac
      unset __val __trimmed
    fi
  '') secretEnvNames;
in
{
  options.programs.claude-desktop-config = {
    enable = lib.mkEnableOption "Claude Desktop MCP configuration";

    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional MCP servers in standard format. Entries here override any server with the same name from programs.mcp-config.standardFormat. Use literal dollar-brace-VAR-brace placeholders in env values; they are resolved at activation time from secretEnv file paths.";
    };

    excludeServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Names of servers from programs.mcp-config.standardFormat to omit from
        the Claude Desktop config. Use to prevent auto-starting heavy servers
        (e.g. browser-automation MCPs) that have no "disabled" concept in
        Claude Desktop.
      '';
    };

    secretEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Map from environment variable name to a /run/secrets/ file path. At activation, each file is read and its content exported under the given name. envsubst then substitutes dollar-brace-NAME-brace placeholders in the generated MCP server JSON before writing the Claude Desktop config.";
    };

    secretPlaceholders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "PLACEHOLDER_REPLACE_ME"
        "REPLACE_ME"
        "CHANGEME"
        "CHANGE_ME"
      ];
      description = ''
        Sentinel values that indicate a secret file exists but hasn't been
        populated yet. Matching secrets are skipped with a warning instead of
        being exported as empty/invalid credentials.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Store the template for reference/debugging.
    xdg.configFile."claude-desktop/mcp-servers-template.json" = {
      source = mcpServersJson;
    };

    home.activation.claudeDesktopMcpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CLAUDE_CONFIG="$HOME/.config/Claude/claude_desktop_config.json"

      # Load secrets from /run/secrets/ files into environment variables.
      ${secretLoadScript}

      # Resolve dollar-brace-VAR-brace placeholders in the template via envsubst.
      # envsubst substitutes every $VAR it finds; values that
      # were not exported above (file missing or placeholder) become "".
      RESOLVED="$(${pkgs.gettext}/bin/envsubst < "${mcpServersJson}")"

      # Merge into the existing Claude Desktop config, replacing mcpServers
      # entirely but preserving all other keys (preferences, coworkUserFilesPath, …).
      # NB: use `+` not `*` — jq's `*` recursively merges the two mcpServers
      # objects, keeping servers removed from the Nix config forever. `+`
      # replaces the whole key.
      if [ -f "$CLAUDE_CONFIG" ]; then
        ${pkgs.jq}/bin/jq -s '.[0] + {mcpServers: .[1].mcpServers}' \
          "$CLAUDE_CONFIG" <(printf '%s' "$RESOLVED") \
          > "$CLAUDE_CONFIG.tmp" && mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
      else
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$CLAUDE_CONFIG")"
        printf '%s\n' "$RESOLVED" > "$CLAUDE_CONFIG"
      fi

      run echo "Claude Desktop: Updated MCP servers in $CLAUDE_CONFIG"
    '';
  };
}
