# Claude Code MCP configuration module for Home Manager
# Merges MCP servers into ~/.claude.json (user-scope)
# Consumes programs.mcp-config.standardFormat
#
# Note: ~/.claude.json is not fully managed by Nix because Claude Code
# stores runtime state there. This module uses an activation script to
# merge MCP servers into the existing file.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude-code-config;
  mcpCfg = config.programs.mcp-config;
  jsonFormat = pkgs.formats.json { };

  # Merge shared MCP servers with any Claude-specific extras
  mcpServersConfig = mcpCfg.standardFormat.mcpServers // cfg.extraMcpServers;

  # Generate the MCP servers JSON file (used by activation script)
  mcpServersJson = jsonFormat.generate "claude-code-mcp-servers.json" mcpServersConfig;

  # Generate commands JSON for custom slash commands
  commandsJson = jsonFormat.generate "claude-code-commands.json" cfg.commands;
in
{
  options.programs.claude-code-config = {
    enable = lib.mkEnableOption "Claude Code MCP configuration";

    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional MCP servers specific to Claude Code (in standard MCP format).";
      example = lib.literalExpression ''
        {
          "custom-server" = {
            command = "npx";
            args = [ "-y" "my-mcp-server" ];
            env = {
              API_KEY = "''${MY_API_KEY}";
            };
          };
        }
      '';
    };

    commands = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Description shown for the slash command.";
          };
          prompt = lib.mkOption {
            type = lib.types.str;
            description = "Prompt text to execute when the command is invoked.";
          };
        };
      });
      default = { };
      description = "Custom slash commands for Claude Code.";
      example = lib.literalExpression ''
        {
          "review" = {
            description = "Run CodeRabbit AI review on uncommitted changes";
            prompt = "Run `cr review --agent --type uncommitted` and present findings as Critical/Warning/Info tiers.";
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Store the MCP servers config for reference/debugging
    xdg.configFile."claude-code/mcp-servers.json" = {
      source = mcpServersJson;
    };

    # Activation script to merge MCP servers and commands into ~/.claude.json
    # mcpServers is REPLACED (not merged) with the declared set, so servers
    # removed from the Nix config are pruned here (including their envs).
    # A running Claude Code can rewrite the file from its own state afterwards;
    # restart it after switching for the cleanup to stick.
    home.activation.claudeCodeMcpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CLAUDE_CONFIG="$HOME/.claude.json"
      MCP_SERVERS_FILE="${mcpServersJson}"
      COMMANDS_FILE="${commandsJson}"

      if [ -f "$CLAUDE_CONFIG" ]; then
        # Report MCP servers present in the file but no longer declared
        REMOVED=$(${pkgs.jq}/bin/jq -r --slurpfile declared "$MCP_SERVERS_FILE" '
          (.mcpServers // {}) | keys[] as $k
          | select(($declared[0] | has($k)) | not)
          | $k
        ' "$CLAUDE_CONFIG")
        if [ -n "$REMOVED" ]; then
          run echo "Claude Code: pruning undeclared MCP servers: $(echo "$REMOVED" | tr '\n' ' ')"
        fi
        # Replace MCP servers wholesale (prunes stale/undeclared servers + envs)
        ${pkgs.jq}/bin/jq -s '.[0] * {mcpServers: .[1]}' "$CLAUDE_CONFIG" "$MCP_SERVERS_FILE" > "$CLAUDE_CONFIG.tmp"
        mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
        # Merge commands into existing config
        ${pkgs.jq}/bin/jq -s '.[0] * {commands: .[1]}' "$CLAUDE_CONFIG" "$COMMANDS_FILE" > "$CLAUDE_CONFIG.tmp"
        mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
        run echo "Claude Code: Updated MCP servers and commands in $CLAUDE_CONFIG"
      else
        # Create new config with MCP servers and commands
        ${pkgs.jq}/bin/jq -s '{mcpServers: .[0], commands: .[1]}' "$MCP_SERVERS_FILE" "$COMMANDS_FILE" > "$CLAUDE_CONFIG"
        run echo "Claude Code: Created $CLAUDE_CONFIG with MCP servers and commands"
      fi
    '';
  };
}
