# Google Antigravity MCP configuration module for Home Manager
# Generates ~/.gemini/config/mcp_config.json
# Consumes programs.mcp-config.standardFormat
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.antigravity-config;
  mcpCfg = config.programs.mcp-config;
  jsonFormat = pkgs.formats.json { };

  # Merge shared MCP servers with any Antigravity-specific extras
  mcpServersConfig = mcpCfg.standardFormat.mcpServers // cfg.extraMcpServers;
  fullConfig = {
    mcpServers = mcpServersConfig;
  };
  # Servers-only JSON used by the activation merge into the Antigravity-owned file
  mcpServersJson = jsonFormat.generate "antigravity-mcp-servers.json" mcpServersConfig;
in
{
  options.programs.antigravity-config = {
    enable = lib.mkEnableOption "Google Antigravity MCP configuration";

    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Additional MCP servers specific to Antigravity (in standard MCP format).
        Note: For remote servers, Antigravity uses 'serverUrl' instead of 'url'.
      '';
      example = lib.literalExpression ''
        {
          # Local stdio server
          "local-docs" = {
            command = "uvx";
            args = [ "--from" "mcpdoc" "mcpdoc" "--urls" "docs:https://example.com/llms.txt" ];
          };
          # Remote HTTP server (Antigravity uses serverUrl, not url)
          "remote-api" = {
            serverUrl = "https://api.example.com/mcp";
            headers = {
              "x-api-key" = "your-key";
            };
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Gemini CLI reads this path (declarative symlink).
    home.file.".gemini/config/mcp_config.json" = {
      source = jsonFormat.generate "mcp_config.json" fullConfig;
    };

    # Antigravity IDE reads ~/.gemini/antigravity/mcp_config.json and owns/rewrites it at
    # runtime, so a nix symlink would be clobbered. Merge our servers into the real file
    # via an activation script (same approach as claude-code-config for ~/.claude.json).
    home.activation.antigravityMcpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      AG_CONFIG="$HOME/.gemini/antigravity/mcp_config.json"
      MCP_SERVERS_FILE="${mcpServersJson}"
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$AG_CONFIG")"
      if [ -s "$AG_CONFIG" ] && ${pkgs.jq}/bin/jq -e . "$AG_CONFIG" >/dev/null 2>&1; then
        # Existing valid config: merge/overwrite the mcpServers key, preserve other keys.
        ${pkgs.jq}/bin/jq -s '.[0] * {mcpServers: .[1]}' "$AG_CONFIG" "$MCP_SERVERS_FILE" > "$AG_CONFIG.tmp" \
          && ${pkgs.coreutils}/bin/mv "$AG_CONFIG.tmp" "$AG_CONFIG"
      else
        # Empty or invalid file: write a fresh config.
        ${pkgs.jq}/bin/jq '{mcpServers: .}' "$MCP_SERVERS_FILE" > "$AG_CONFIG"
      fi
    '';
  };
}
