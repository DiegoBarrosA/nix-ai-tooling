# Claude Code MCP configuration module for Home Manager
# Merges MCP servers into ~/.claude.json (user-scope)
# Consumes programs.mcp-config.standardFormat
#
# Note: ~/.claude.json is not fully managed by Nix because Claude Code
# stores runtime state there. This module uses an activation script to
# merge MCP servers into the existing file.
#
# Extra profiles (programs.claude-code-config.profiles.<name>) each get a
# config dir under XDG_CONFIG_HOME and a `claude-<name>` launcher that sets
# CLAUDE_CONFIG_DIR; Claude Code then keeps .claude.json inside that dir.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  hmConfig = config;
  cfg = config.programs.claude-code-config;
  mcpCfg = config.programs.mcp-config;
  jsonFormat = pkgs.formats.json { };
  mkLauncher = import ./account-launcher.nix { inherit pkgs lib; };

  # Merge shared MCP servers with any Claude-specific extras
  mcpServersConfig = mcpCfg.standardFormat.mcpServers // cfg.extraMcpServers;

  # Generate the MCP servers JSON file (used by activation script)
  mcpServersJson = jsonFormat.generate "claude-code-mcp-servers.json" mcpServersConfig;

  # Generate commands JSON for custom slash commands
  commandsJson = jsonFormat.generate "claude-code-commands.json" cfg.commands;

  # Generate plugin/marketplace JSON for settings.json
  enabledPluginsJson = jsonFormat.generate "claude-code-enabled-plugins.json" cfg.enabledPlugins;
  marketplacesJson = jsonFormat.generate "claude-code-marketplaces.json" cfg.extraKnownMarketplaces;

  # Shell for one profile. claudeJson/dir are shell words (already quoted).
  # mcpServers is REPLACED (not merged) with the declared set, so servers
  # removed from the Nix config are pruned (including their envs). A running
  # Claude Code can rewrite the file from its own state afterwards; restart
  # it after switching for the cleanup to stick. enabledPlugins and
  # extraKnownMarketplaces are replaced wholesale in settings.json too.
  syncScript =
    {
      label,
      claudeJson,
      dir,
      mcpFile,
      pluginsFile,
      marketplacesFile,
      agentSources,
      withCommands,
      shareDefaults,
    }:
    ''
      CLAUDE_CONFIG=${claudeJson}
      CLAUDE_DIR=${dir}
      ${pkgs.coreutils}/bin/mkdir -p "$CLAUDE_DIR/agents"

      if [ -f "$CLAUDE_CONFIG" ]; then
        REMOVED=$(${pkgs.jq}/bin/jq -r --slurpfile declared "${mcpFile}" '
          (.mcpServers // {}) | keys[] as $k
          | select(($declared[0] | has($k)) | not)
          | $k
        ' "$CLAUDE_CONFIG")
        if [ -n "$REMOVED" ]; then
          run echo "Claude Code (${label}): pruning undeclared MCP servers: $(echo "$REMOVED" | tr '\n' ' ')"
        fi
        # NB: use `+` not `*`, jq's `*` recursively merges the two mcpServers
        # objects and keeps servers removed from the Nix config forever.
        ${pkgs.jq}/bin/jq -s '.[0] + {mcpServers: .[1]}' "$CLAUDE_CONFIG" "${mcpFile}" > "$CLAUDE_CONFIG.tmp"
        mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
      else
        ${pkgs.jq}/bin/jq '{mcpServers: .}' "${mcpFile}" > "$CLAUDE_CONFIG"
      fi
      ${lib.optionalString withCommands ''
        # Keep commands present only in the existing file; declared ones override.
        ${pkgs.jq}/bin/jq -s '.[0] + {commands: ((.[0].commands // {}) + .[1])}' "$CLAUDE_CONFIG" "${commandsJson}" > "$CLAUDE_CONFIG.tmp"
        mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
      ''}
      run echo "Claude Code (${label}): updated MCP servers in $CLAUDE_CONFIG"

      SETTINGS="$CLAUDE_DIR/settings.json"
      if [ -f "$SETTINGS" ]; then
        ${pkgs.jq}/bin/jq -s '.[0] + {enabledPlugins: .[1], extraKnownMarketplaces: .[2]}' \
          "$SETTINGS" "${pluginsFile}" "${marketplacesFile}" > "$SETTINGS.tmp"
        mv "$SETTINGS.tmp" "$SETTINGS"
      else
        ${pkgs.jq}/bin/jq -n --slurpfile p "${pluginsFile}" --slurpfile m "${marketplacesFile}" \
          '{enabledPlugins: $p[0], extraKnownMarketplaces: $m[0]}' > "$SETTINGS"
      fi

      ${lib.concatMapStringsSep "\n" (src: ''
        if [ -d "${src}" ]; then
          for f in "${src}"/*.md; do
            [ -e "$f" ] || continue
            ${pkgs.coreutils}/bin/ln -sfn "$f" "$CLAUDE_DIR/agents/$(${pkgs.coreutils}/bin/basename "$f")"
          done
        fi
      '') agentSources}
      ${lib.optionalString shareDefaults ''
        ${pkgs.coreutils}/bin/ln -sfn "$HOME/.claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
        ${pkgs.coreutils}/bin/ln -sfn "$HOME/.claude/skills" "$CLAUDE_DIR/skills"
      ''}
    '';
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

    enabledPlugins = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = { };
      description = ''
        Claude Code plugins to enable, keyed by "<plugin>@<marketplace>"
        (matches the `enabledPlugins` shape in ~/.claude/settings.json).
      '';
      example = lib.literalExpression ''
        { "superpowers@claude-plugins-official" = true; }
      '';
    };

    extraKnownMarketplaces = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra plugin marketplaces to register (extraKnownMarketplaces in settings.json).";
      example = lib.literalExpression ''
        {
          ponytail = {
            source = {
              source = "github";
              repo = "DietrichGebert/ponytail";
            };
          };
        }
      '';
    };

    extraAgentSources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Directories of extra *.md subagent files to symlink into ~/.claude/agents.";
      example = lib.literalExpression ''[ "''${inputs.impeccable}/.claude/agents" ]'';
    };

    acpPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "claude-agent-acp package. When set, token profiles also get a `<alias>-acp` launcher.";
    };

    profiles = lib.mkOption {
      default = { };
      description = ''
        Extra Claude Code profiles. Each gets its own config dir under
        XDG_CONFIG_HOME (own login, history, MCP servers, plugins) and a
        launcher command that sets CLAUDE_CONFIG_DIR. Profiles do NOT inherit
        the default profile's MCP servers, so customer-specific servers stay
        isolated.
      '';
      example = lib.literalExpression ''
        {
          work = {
            mcpServers.jira = { command = "jira-mcp"; };
            enabledPlugins."superpowers@claude-plugins-official" = true;
          };
        }
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              configDir = lib.mkOption {
                type = lib.types.str;
                default = "${hmConfig.xdg.configHome}/claude-code-${name}";
                description = "CLAUDE_CONFIG_DIR for this profile (absolute path, XDG by default).";
              };
              alias = lib.mkOption {
                type = lib.types.str;
                default = "claude-${name}";
                description = "Command that launches Claude Code with this profile.";
              };
              mcpServers = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
                description = "MCP servers (standard format) for this profile only.";
              };
              enabledPlugins = lib.mkOption {
                type = lib.types.attrsOf lib.types.bool;
                default = { };
                description = "Plugins to enable in this profile's settings.json.";
              };
              extraKnownMarketplaces = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
                description = "Plugin marketplaces to register in this profile's settings.json.";
              };
              extraAgentSources = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Directories of *.md subagent files to symlink into this profile's agents dir.";
              };
              tokenFile = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Path to a file holding a `claude setup-token` token (for example a
                  sops secret under /run/secrets). The launcher exports it as
                  CLAUDE_CODE_OAUTH_TOKEN at start and fails if the file is missing
                  or empty. The token is never written to the Nix store.
                '';
              };
              shareDefaults = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Symlink the default profile's CLAUDE.md and skills dir into this profile.";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    # Store the MCP servers config for reference/debugging
    xdg.configFile."claude-code/mcp-servers.json" = {
      source = mcpServersJson;
    };

    home.packages = lib.concatLists (
      lib.mapAttrsToList (
        _: p:
        let
          mk = name: exe: mkLauncher {
            inherit name exe;
            fixed.CLAUDE_CONFIG_DIR = p.configDir;
            env = lib.optionalAttrs (p.tokenFile != null) { CLAUDE_CODE_OAUTH_TOKEN = p.tokenFile; };
          };
        in
        [ (mk p.alias "${pkgs.claude-code}/bin/claude") ]
        ++ lib.optional (p.tokenFile != null && cfg.acpPackage != null) (
          mk "${p.alias}-acp" "${cfg.acpPackage}/bin/claude-agent-acp"
        )
      ) cfg.profiles
    );

    home.activation = {
      claudeCodeSync-default = lib.hm.dag.entryAfter [ "writeBoundary" ] (syncScript {
        label = "default";
        claudeJson = ''"$HOME/.claude.json"'';
        dir = ''"$HOME/.claude"'';
        mcpFile = mcpServersJson;
        pluginsFile = enabledPluginsJson;
        marketplacesFile = marketplacesJson;
        agentSources = cfg.extraAgentSources;
        withCommands = true;
        shareDefaults = false;
      });
    }
    // lib.mapAttrs' (
      name: p:
      lib.nameValuePair "claudeCodeSync-${name}" (
        lib.hm.dag.entryAfter [ "writeBoundary" "claudeCodeSync-default" ] (syncScript {
          label = name;
          claudeJson = lib.escapeShellArg "${p.configDir}/.claude.json";
          dir = lib.escapeShellArg p.configDir;
          mcpFile = jsonFormat.generate "claude-code-${name}-mcp-servers.json" p.mcpServers;
          pluginsFile = jsonFormat.generate "claude-code-${name}-plugins.json" p.enabledPlugins;
          marketplacesFile = jsonFormat.generate "claude-code-${name}-marketplaces.json" p.extraKnownMarketplaces;
          agentSources = p.extraAgentSources;
          withCommands = false;
          inherit (p) shareDefaults;
        })
      )
    ) cfg.profiles;
  };
}
