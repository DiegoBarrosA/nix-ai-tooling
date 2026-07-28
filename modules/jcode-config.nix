# Jcode configuration module for Home Manager
# Manages Jcode config (~/.jcode/config.toml) and MCP servers (~/.jcode/mcp.json).
# Expects programs.mcp-config (from flake homeModules `mcp-config`, or import mcp-config.nix).
# No hardcoded personal info - all paths/secrets via options or env vars.
#
# jcode config format:
#   ~/.jcode/config.toml  — providers, models, display, features
#   ~/.jcode/mcp.json     — MCP servers (separate from config.toml)
#   ~/.jcode/skills/      — skill directories with SKILL.md
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.jcode-config;
  mcpCfg = config.programs.mcp-config;
  tomlFormat = pkgs.formats.toml { };
  jsonFormat = pkgs.formats.json { };

  # ---- MCP server conversion ----
  # jcode uses standard MCP format: { command, args, env }
  # and ${VAR} syntax for env var references (not {env:VAR}).
  convertEnvSyntax = str: builtins.replaceStrings [ "{env:" "}" ] [ "\${" "}" ] str;
  convertEnvAttrs = env: lib.mapAttrs (_: v: if builtins.isString v then convertEnvSyntax v else toString v) env;

  # Convert programs.mcp.servers entries to jcode MCP format (mcp.json).
  toMcpJsonEntry =
    _name: srv:
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

  # All MCP servers from mcp-config, plus any extra servers from other modules.
  allMcpServers = config.programs.mcp.servers or { };

  # Build the full MCP servers attrset for jcode's mcp.json.
  mcpServersJson = lib.mapAttrs toMcpJsonEntry allMcpServers;

  # ---- Secret loading ----
  secretEnvNames = lib.attrNames cfg.secretEnv;
  placeholderMatch = lib.concatMapStringsSep " | " (
    p: "${lib.escapeShellArg p}"
  ) cfg.secretPlaceholders;
  secretEnvScript = lib.concatMapStringsSep "\n" (name: ''
    if [ -r "${cfg.secretEnv.${name}}" ]; then
      __val="$( ${pkgs.coreutils}/bin/cat "${cfg.secretEnv.${name}}" )"
      __trimmed="$( printf '%s' "$__val" | ${pkgs.coreutils}/bin/tr -d '[:space:]' )"
      case "$__trimmed" in
        "" )
          echo "jcode: WARNING: secret '${name}' (${toString cfg.secretEnv.${name}}) is empty; not exporting." >&2
          ;;
        ${placeholderMatch} )
          echo "jcode: WARNING: secret '${name}' (${toString cfg.secretEnv.${name}}) still holds a placeholder value; not exporting." >&2
          ;;
        * )
          export ${name}="$__val"
          ;;
      esac
      unset __val __trimmed
    fi
  '') secretEnvNames;

  # ---- Profile scripts ----
  # Each profile gets its own JCODE_HOME (~/.jcode-profiles/<name>/)
  # so sessions/history/config are isolated per billing context.
  profileSharedMcp =
    profileCfg:
    let
      selected =
        if profileCfg.mcpServers == null then
          mcpServersJson
        else
          lib.filterAttrs (name: _: builtins.elem name profileCfg.mcpServers) mcpServersJson;
    in
    selected;

  # ---- Dispatcher script (jc) ----
  dispatcherContexts = cfg.dispatcher.contexts;
  contextKeysLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: c:
      "          [${name}]=${lib.escapeShellArg (if c.apiKeyEnvVar == null then "" else c.apiKeyEnvVar)}"
    ) dispatcherContexts
  );
  contextScriptsLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: c: "          [${name}]=${lib.escapeShellArg c.scriptName}") dispatcherContexts
  );
  availableContexts = lib.concatStringsSep ", " (lib.attrNames dispatcherContexts);

  # ---- Config.toml generation ----
  providerConfig =
    lib.optionalAttrs cfg.opencodeGo.enable {
      "opencode-go" = {
        type = "openai-compatible";
        base_url = "https://opencode.ai/zen/go/v1";
        api_key_env = cfg.opencodeGo.apiKeyEnvVar;
        models = [
          { id = "deepseek-v4-pro"; name = "DeepSeek V4 Pro"; }
          { id = "deepseek-v4-flash"; name = "DeepSeek V4 Flash"; }
          { id = "glm-5.1"; name = "GLM 5.1"; }
          { id = "glm-5"; name = "GLM 5"; }
          { id = "kimi-k2.6"; name = "Kimi K2.6"; }
          { id = "kimi-k2.5"; name = "Kimi K2.5"; }
          { id = "mimo-v2.5-pro"; name = "MiMo V2.5 Pro"; }
          { id = "mimo-v2.5"; name = "MiMo V2.5"; }
          { id = "minimax-m2.7"; name = "MiniMax M2.7"; }
          { id = "minimax-m2.5"; name = "MiniMax M2.5"; }
          { id = "qwen3.6-plus"; name = "Qwen 3.6 Plus"; }
          { id = "qwen3.5-plus"; name = "Qwen 3.5 Plus"; }
        ];
      };
    }
    // lib.optionalAttrs cfg.opencodeZen.enable {
      "opencode" = {
        type = "openai-compatible";
        base_url = "https://opencode.ai/zen/v1";
        api_key_env = cfg.opencodeZen.apiKeyEnvVar;
        models = [
          { id = "big-pickle"; name = "Big Pickle"; }
          { id = "deepseek-v4-flash-free"; name = "DeepSeek V4 Flash Free"; }
          { id = "minimax-m2.5-free"; name = "MiniMax M2.5 Free"; }
          { id = "ring-2.6-1t-free"; name = "Ring 2.6 1T Free"; }
          { id = "nemotron-3-super-free"; name = "Nemotron 3 Super Free"; }
          { id = "gpt-5-nano"; name = "GPT 5 Nano"; }
          { id = "claude-haiku-4-5"; name = "Claude Haiku 4.5"; }
          { id = "claude-sonnet-4-5"; name = "Claude Sonnet 4.5"; }
          { id = "claude-opus-4-5"; name = "Claude Opus 4.5"; }
          { id = "gpt-5.4"; name = "GPT 5.4"; }
          { id = "qwen3.5-plus"; name = "Qwen 3.5 Plus"; }
        ];
      };
    }
    // lib.optionalAttrs cfg.groq.enable {
      "groq" = {
        type = "openai-compatible";
        base_url = "https://api.groq.com/openai/v1";
        api_key_env = cfg.groq.apiKeyEnvVar;
        models = [
          { id = "llama-3.3-70b-versatile"; name = "Llama 3.3 70B Versatile"; }
          { id = "llama-3.1-8b-instant"; name = "Llama 3.1 8B Instant"; }
          { id = "qwen3-32b"; name = "Qwen3 32B"; }
          { id = "gpt-oss-20b"; name = "GPT OSS 20B"; }
        ];
      };
    }
    // (if cfg.provider.enable then cfg.provider.config else { });

  defaultProvider =
    if cfg.opencodeGo.enable then "opencode-go"
    else if cfg.opencodeZen.enable then "opencode"
    else if cfg.groq.enable then "groq"
    else cfg.provider.defaultProvider;

  defaultModel = cfg.provider.defaultModel;

  jcodeConfig = {
    provider = lib.optionalAttrs (defaultProvider != null) {
      default_provider = defaultProvider;
    }
    // lib.optionalAttrs (defaultModel != null) {
      default_model = defaultModel;
    };
  }
  // lib.optionalAttrs (providerConfig != { }) {
    providers = providerConfig;
  }
  // lib.optionalAttrs (cfg.extraConfig != { }) cfg.extraConfig;

  filteredConfig = lib.filterAttrs (k: v: v != null && v != { }) jcodeConfig;
in
{
  options.programs.jcode-config = {
    enable = lib.mkEnableOption "Jcode configuration management";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.jcode;
      defaultText = lib.literalExpression "pkgs.jcode";
      description = "The jcode package to use.";
    };

    # OpenCode Go subscription
    opencodeGo = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable OpenCode Go provider configuration for jcode.";
      };
      apiKeyEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "OPENCODE_API_KEY";
        description = "Environment variable containing the OpenCode API key.";
      };
    };

    # OpenCode Zen pay-per-use
    opencodeZen = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable OpenCode Zen provider configuration for jcode.";
      };
      apiKeyEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "OPENCODE_API_KEY";
        description = "Environment variable containing the OpenCode API key.";
      };
    };

    # Groq free tier
    groq = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Groq provider configuration for jcode.";
      };
      apiKeyEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "GROQ_API_KEY";
        description = "Environment variable containing the Groq API key.";
      };
    };

    # Custom provider (manual override)
    provider = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable manual provider configuration in config.toml.";
      };
      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Provider configuration (jcode TOML format). Keys are provider names.";
      };
      defaultProvider = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default provider name.";
      };
      defaultModel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default model ID.";
      };
    };

    # Extra config merged into config.toml
    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra configuration to merge into config.toml (display, features, keybindings, etc.).";
    };

    # Named profiles
    profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            scriptName = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Override the generated script name. Defaults to jcode-{profile-name}.";
            };
            config = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = "config.toml content for this profile.";
            };
            mcpServers = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = ''
                Allowlist of MCP server names to include in this profile.
                When null (default), inherits ALL configured MCP servers.
                When set to a list, only those servers are written to mcp.json.
              '';
            };
          };
        }
      );
      default = { };
      description = "Named jcode profiles, each with isolated JCODE_HOME.";
    };

    # Billing-context dispatcher (jc script)
    dispatcher = {
      enable = lib.mkEnableOption "the `jc` billing-context dispatcher script" // {
        default = true;
      };
      defaultContext = lib.mkOption {
        type = lib.types.str;
        default = "personal";
        description = "Billing context used when JCODE_BILLING_CONTEXT is unset.";
      };
      contexts = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              scriptName = lib.mkOption {
                type = lib.types.str;
                description = "Name of the profile wrapper script this context dispatches to.";
              };
              apiKeyEnvVar = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Environment variable required for this context.";
              };
            };
          }
        );
        default = { };
        description = "Billing contexts for the jc dispatcher.";
      };
    };

    # Extra MCP servers (merged with mcp-config registry)
    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional MCP servers for jcode (standard MCP format).";
    };

    # Skills
    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Jcode skills. Keys are directory names, values are SKILL.md content.";
    };

    # Secret env vars
    secretEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Files whose contents are exported as env vars before running jcode.";
    };

    secretPlaceholders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "PLACEHOLDER_REPLACE_ME"
        "REPLACE_ME"
        "CHANGEME"
        "CHANGE_ME"
      ];
      description = "Sentinel values treated as unpopulated secrets.";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      jcodeBin = cfg.package;
      jcodeWrapper = pkgs.writeShellScriptBin "jcode" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        ${secretEnvScript}
        exec ${jcodeBin}/bin/jcode "$@"
      '';
      jcodePackage =
        if secretEnvNames == [ ] then
          jcodeBin
        else
          pkgs.symlinkJoin {
            name = "jcode-with-secrets";
            paths = [
              jcodeWrapper
              jcodeBin
            ];
          };

      profileScripts = lib.mapAttrsToList (
        profileName: profileCfg:
        let
          scriptName =
            if profileCfg.scriptName != null then profileCfg.scriptName else "jcode-${profileName}";
        in
        pkgs.writeShellScriptBin scriptName ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail
          ${secretEnvScript}
          export JCODE_HOME="$HOME/.jcode-profiles/${profileName}"
          mkdir -p "$JCODE_HOME"
          exec ${jcodeBin}/bin/jcode "$@"
        ''
      ) cfg.profiles;

      jcDispatcher = pkgs.writeShellScriptBin "jc" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        declare -A CONTEXT_KEYS=(
        ${contextKeysLines}
        )

        declare -A CONTEXT_SCRIPTS=(
        ${contextScriptsLines}
        )

        CONTEXT="''${JCODE_BILLING_CONTEXT:-${cfg.dispatcher.defaultContext}}"

        if [[ "''${1:-}" == "--print-context" ]]; then
          echo "[BILLING CONTEXT: $CONTEXT]"
          SCRIPT="''${CONTEXT_SCRIPTS[$CONTEXT]:-}"
          if [[ -z "$SCRIPT" ]]; then
            echo "ERROR: Invalid billing context '$CONTEXT'" >&2
            echo "Available contexts: ${availableContexts}" >&2
            exit 1
          fi
          echo "Profile script: $SCRIPT"
          exit 0
        fi

        SCRIPT="''${CONTEXT_SCRIPTS[$CONTEXT]:-}"
        if [[ -z "$SCRIPT" ]]; then
          echo "ERROR: Invalid billing context '$CONTEXT'" >&2
          echo "Available contexts: ${availableContexts}" >&2
          exit 1
        fi

        REQUIRED_KEY="''${CONTEXT_KEYS[$CONTEXT]:-}"
        if [[ -n "$REQUIRED_KEY" ]] && [[ -z "''${!REQUIRED_KEY:-}" ]]; then
          SECRET_FILE="/run/secrets/$(echo "$REQUIRED_KEY" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
          if [[ ! -r "$SECRET_FILE" ]]; then
            echo "ERROR: $REQUIRED_KEY not set (required for context '$CONTEXT')" >&2
            echo "Set the environment variable or ensure $SECRET_FILE exists" >&2
            exit 1
          fi
        fi

        echo "[BILLING CONTEXT: $CONTEXT]" >&2
        exec "$SCRIPT" "$@"
      '';

      profileConfigFiles = lib.foldlAttrs (
        acc: profileName: profileCfg:
        let
          profileMcp = profileSharedMcp profileCfg;
          profileToml = lib.filterAttrs (k: v: v != null && v != { }) (
            lib.recursiveUpdate profileCfg.config { }
          );
        in
        acc
        // {
          ".jcode-profiles/${profileName}/.jcode/config.toml" = {
            source = tomlFormat.generate "jcode-${profileName}-config.toml" profileToml;
            force = true;
          };
          ".jcode-profiles/${profileName}/.jcode/mcp.json" = {
            source = jsonFormat.generate "jcode-${profileName}-mcp.json" {
              mcpServers = profileMcp;
            };
            force = true;
          };
        }
        // lib.mapAttrs' (
          skillName: content:
          lib.nameValuePair ".jcode-profiles/${profileName}/.jcode/skills/${skillName}/SKILL.md" {
            text = content;
          }
        ) cfg.skills
      ) { } cfg.profiles;
    in
    lib.mkMerge [
      {
        home.packages = [
          jcodePackage
        ]
        ++ lib.optional (cfg.dispatcher.enable && cfg.dispatcher.contexts != { }) jcDispatcher
        ++ profileScripts;

        home.file =
          {
            ".jcode/config.toml" = {
              source = tomlFormat.generate "jcode-config.toml" filteredConfig;
              force = true;
            };
            ".jcode/mcp.json" = {
              source = jsonFormat.generate "jcode-mcp.json" {
                mcpServers = mcpServersJson // (lib.mapAttrs toMcpJsonEntry cfg.extraMcpServers);
              };
              force = true;
            };
          }
          // lib.mapAttrs' (
            skillName: content:
            lib.nameValuePair ".jcode/skills/${skillName}/SKILL.md" {
              text = content;
            }
          ) cfg.skills
          // profileConfigFiles;
      }
    ]
  );
}
