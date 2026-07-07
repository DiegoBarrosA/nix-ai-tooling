# OpenCode configuration module for Home Manager
# Manages OpenCode config including MCP servers (Jira, Obsidian, mcp-nixos)
# Expects programs.mcp-config (from flake homeModules `mcp-config`, or import mcp-config.nix).
# No hardcoded personal info - all paths/secrets via options or env vars
{
  config,
  lib,
  pkgs,
  customPkgs,
  ...
}:
let
  cfg = config.programs.opencode-config;
  mcpCfg = config.programs.mcp-config;
  jsonFormat = pkgs.formats.json { };

  # Names of servers that opencode-config manages explicitly (from programs.mcp-config options).
  # Any programs.mcp.servers entry NOT in this set is auto-included below.
  explicitServerNames = lib.concatLists [
    (lib.optional mcpCfg.mcpNixos.enable "nixos")
    (lib.optional mcpCfg.mcpTelegram.enable "telegram")
    (lib.optional mcpCfg.jobspy.enable "jobspy")
    (lib.optional mcpCfg.github.enable "github")
    (lib.optional mcpCfg.playwright.enable "playwright")
    (lib.optional mcpCfg.thunderbird.enable "thunderbird")
  ];

  # Convert a programs.mcp.servers entry to opencode MCP format.
  # programs.mcp.servers stores command as a string + optional args list;
  # opencode expects command as a flat list.  The env field uses {env:VAR}
  # syntax in both formats, so it passes through unchanged as `environment`.
  toOpencodeEntry =
    _name: srv:
    let
      cmdList = if builtins.isList srv.command then srv.command else [ srv.command ];
      fullCmd = cmdList ++ (srv.args or [ ]);
    in
    {
      type = "local";
      command = fullCmd;
      # Honor an optional per-server `enabled` flag (defaults to true). Setting
      # a server to `enabled = false` keeps it defined but stops opencode from
      # starting it — useful for rarely-used servers to avoid context creep.
      # NB: the mcp submodule's `enabled` option defaults to `null` (attribute
      # present), so `srv.enabled or true` would yield `null` — which OpenCode
      # rejects (expects a boolean). Coerce null → true explicitly.
      enabled = if (srv.enabled or null) == null then true else srv.enabled;
    }
    // lib.optionalAttrs ((srv.env or { }) != { }) {
      environment = srv.env;
    };

  # Servers from programs.mcp.servers not already handled by mcpCfg options.
  # This picks up work/customer MCP servers (jira, confluence, trello, tempo, …)
  # added by external modules (e.g. a private work MCP config module) without
  # requiring any changes to those modules.
  additionalMcpServers = lib.mapAttrs toOpencodeEntry (
    lib.filterAttrs (name: _: !builtins.elem name explicitServerNames) (
      config.programs.mcp.servers or { }
    )
  );

  # Build MCP servers configuration from shared mcp-config
  mcpServers =
    lib.optionalAttrs mcpCfg.mcpNixos.enable {
      nixos = {
        type = "local";
        command = [
          "${pkgs.mcp-nixos}/bin/mcp-nixos"
        ];
        enabled = true;
      };
    }
    // lib.optionalAttrs mcpCfg.mcpTelegram.enable {
      telegram = {
        type = "local";
        command = [
          "uvx"
          "simple-telegram-mcp"
        ];
        enabled = true;
      };
    }
    // lib.optionalAttrs mcpCfg.jobspy.enable {
      jobspy = {
        type = "local";
        command = [ "${mcpCfg.jobspy.package}/bin/jobspy-mcp" ];
        enabled = mcpCfg.jobspy.autostart;
      };
    }
    // lib.optionalAttrs mcpCfg.github.enable {
      github = {
        type = "local";
        command = [ "${mcpCfg.github.package}/bin/github-mcp-server" ];
        enabled = true;
        environment = {
          GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_TOKEN}";
        };
      };
    }
    // lib.optionalAttrs mcpCfg.playwright.enable {
      playwright = {
        type = "local";
        command = [
          "${mcpCfg.playwright.package}/bin/playwright-mcp"
        ]
        ++ lib.optionals (mcpCfg.playwright.browserPath != null) [
          "--executable-path"
          mcpCfg.playwright.browserPath
        ];
        enabled = true;
      };
    }
    // lib.optionalAttrs mcpCfg.thunderbird.enable {
      thunderbird = {
        type = "local";
        command = [ "${mcpCfg.thunderbird.package}/bin/thunderbird-mcp" ];
        enabled = mcpCfg.thunderbird.autostart;
      };
    }
    // additionalMcpServers
    // cfg.extraMcpServers;

  # Build provider configuration combining Go, Zen, and custom providers
  providerConfig =
    lib.optionalAttrs cfg.opencodeGo.enable {
      "opencode-go" = {
        npm = "@ai-sdk/openai-compatible";
        name = "OpenCode Go";
        options = {
          baseURL = "https://opencode.ai/zen/go/v1";
          apiKey = "{env:${cfg.opencodeGo.apiKeyEnvVar}}";
        };
        models = {
          "deepseek-v4-pro" = {
            name = "DeepSeek V4 Pro";
          };
          "deepseek-v4-flash" = {
            name = "DeepSeek V4 Flash";
          };
          "glm-5.1" = {
            name = "GLM 5.1";
          };
          "glm-5" = {
            name = "GLM 5";
          };
          "kimi-k2.6" = {
            name = "Kimi K2.6";
          };
          "kimi-k2.5" = {
            name = "Kimi K2.5";
          };
          "mimo-v2.5-pro" = {
            name = "MiMo V2.5 Pro";
          };
          "mimo-v2.5" = {
            name = "MiMo V2.5";
          };
          "minimax-m2.7" = {
            name = "MiniMax M2.7";
          };
          "minimax-m2.5" = {
            name = "MiniMax M2.5";
          };
          "qwen3.6-plus" = {
            name = "Qwen 3.6 Plus";
          };
          "qwen3.5-plus" = {
            name = "Qwen 3.5 Plus";
          };
        };
      };
    }
    // lib.optionalAttrs cfg.opencodeZen.enable {
      "opencode" = {
        npm = "@ai-sdk/openai-compatible";
        name = "OpenCode Zen";
        options = {
          baseURL = "https://opencode.ai/zen/v1";
          apiKey = "{env:${cfg.opencodeZen.apiKeyEnvVar}}";
        };
        models = {
          "deepseek-v4-flash-free" = {
            name = "DeepSeek V4 Flash Free";
          };
          "minimax-m2.5-free" = {
            name = "MiniMax M2.5 Free";
          };
          "ring-2.6-1t-free" = {
            name = "Ring 2.6 1T Free";
          };
          "nemotron-3-super-free" = {
            name = "Nemotron 3 Super Free";
          };
          "big-pickle" = {
            name = "Big Pickle";
          };
          "gpt-5-nano" = {
            name = "GPT 5 Nano";
          };
          "claude-haiku-4-5" = {
            name = "Claude Haiku 4.5";
          };
          "qwen3.5-plus" = {
            name = "Qwen 3.5 Plus (Zen)";
          };
          "claude-sonnet-4-5" = {
            name = "Claude Sonnet 4.5";
          };
          "claude-opus-4-5" = {
            name = "Claude Opus 4.5";
          };
          "gpt-5.4" = {
            name = "GPT 5.4";
          };
        };
      };
    }
    // lib.optionalAttrs cfg.groq.enable {
      "groq" = {
        npm = "@ai-sdk/openai-compatible";
        name = "Groq";
        options = {
          baseURL = "https://api.groq.com/openai/v1";
          apiKey = "{env:${cfg.groq.apiKeyEnvVar}}";
        };
        models = {
          "llama-3.3-70b-versatile" = {
            name = "Llama 3.3 70B Versatile";
          };
          "llama-3.1-8b-instant" = {
            name = "Llama 3.1 8B Instant";
          };
          "qwen3-32b" = {
            name = "Qwen3 32B";
          };
          "gpt-oss-20b" = {
            name = "GPT OSS 20B";
          };
        };
      };
    }
    // (if cfg.provider.enable then cfg.provider.config else { });

  # Determine the default model
  defaultModel =
    if cfg.opencodeGo.enable then "opencode-go/deepseek-v4-flash" else cfg.provider.defaultModel;

  # Build the full opencode.json config.
  # Use recursiveUpdate so cfg.extraConfig.provider merges with (instead of
  # replacing) the providers built from opencodeGo/opencodeZen options.
  baseConfig = {
    "$schema" = "https://opencode.ai/config.json";
  }
  // lib.optionalAttrs (mcpServers != { }) { mcp = mcpServers; }
  // lib.optionalAttrs (providerConfig != { } || defaultModel != null) {
    provider = providerConfig;
    model = defaultModel;
  };

  # Merge baseConfig with extraConfig, ensuring plugin lists are concatenated
  opencodeConfig =
    let
      merged = lib.recursiveUpdate baseConfig cfg.extraConfig;
      # Concatenate plugin lists if both exist (don't replace, merge)
      finalPlugins = (baseConfig.plugin or [ ]) ++ (cfg.extraConfig.plugin or [ ]);
    in
    lib.filterAttrs (k: v: v != null && v != { }) (
      merged // lib.optionalAttrs (finalPlugins != [ ]) { plugin = finalPlugins; }
    );
in
{
  options.programs.opencode-config = {
    enable = lib.mkEnableOption "OpenCode configuration management";

    # OpenCode Go subscription configuration
    opencodeGo = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable OpenCode Go provider configuration.
          OpenCode Go is a $10/month subscription for reliable access to popular open coding models.
        '';
      };

      apiKeyEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "OPENCODE_API_KEY";
        description = ''
          Environment variable containing the OpenCode API key.
          OpenCode uses a single API key for both Go and Zen providers
          (same subscription, same auth backend).
        '';
      };
    };

    # OpenCode Zen pay-per-use configuration
    opencodeZen = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable OpenCode Zen provider configuration.
          OpenCode Zen is a pay-per-use gateway with curated, tested models.
        '';
      };

      apiKeyEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "OPENCODE_API_KEY";
        description = ''
          Environment variable containing the OpenCode API key.
          OpenCode uses a single API key for both Go and Zen providers
          (same subscription, same auth backend).
        '';
      };
    };

    # Groq free tier configuration
    groq = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable Groq provider configuration.
          Groq offers free-tier access to fast LLM inference.
        '';
      };

      apiKeyEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "GROQ_API_KEY";
        description = ''
          Environment variable containing the Groq API key.
          Get your free API key at https://console.groq.com
        '';
      };
    };

    # Provider configuration (optional, for manual override)
    provider = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable provider configuration in opencode.json.
          When disabled, provider config is not managed by Nix (edit manually).
        '';
      };

      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Provider configuration. Keys are provider names, values are provider config.
        '';
        example = lib.literalExpression ''
          {
            anthropic = {
              npm = "@ai-sdk/anthropic";
              name = "Anthropic";
              models = {
                "claude-sonnet-4" = {
                  name = "Claude Sonnet 4";
                };
              };
            };
          }
        '';
      };

      defaultModel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default model to use.";
      };
    };

    # Extra MCP servers (user-defined, merged with shared MCP config)
    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional MCP servers to configure.";
    };

    # Extra config (merged into opencode.json)
    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra configuration to merge into opencode.json.";
    };

    # Telegram channel configuration (for OpenClaw)
    channels.telegram = {
      enable = lib.mkEnableOption "Telegram notification channel for OpenCode";

      botTokenEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "TELEGRAM_BOT_TOKEN";
        description = "Environment variable containing the Telegram bot token.";
      };

      userIdEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "TELEGRAM_USER_ID";
        description = "Environment variable containing the Telegram user ID.";
      };

      dmPolicy = lib.mkOption {
        type = lib.types.enum [
          "allowlist"
          "open"
          "disabled"
        ];
        default = "allowlist";
        description = "Policy for direct messages.";
      };

      groupPolicy = lib.mkOption {
        type = lib.types.enum [
          "open"
          "disabled"
          "allowlist"
        ];
        default = "disabled";
        description = "Policy for group chat messages.";
      };
    };

    # Telegram notification scripts (for opencode CLI)
    notifications.telegram = {
      enable = lib.mkEnableOption "send-telegram-message helper script for Telegram notifications";

      enableShellHook = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install opencode-with-notifications wrapper script.";
      };
    };

    secretEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Files whose contents should be exported into the environment before running opencode.";
    };

    # Sentinel strings that indicate a secret has not been populated yet.
    # When a secretEnv file's content matches one of these (or is empty), the
    # value is NOT exported and a clear warning is printed to stderr. This
    # prevents a placeholder secret (e.g. a freshly-scaffolded sops entry that
    # was never filled in) from silently feeding an MCP server, which would
    # then fail to start and get dropped with no obvious signal.
    secretPlaceholders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "PLACEHOLDER_REPLACE_ME"
        "REPLACE_ME"
        "CHANGEME"
        "CHANGE_ME"
      ];
      description = ''
        Sentinel values treated as "unpopulated secret". A secretEnv whose file
        content exactly matches one of these (after trimming) is skipped with a
        loud stderr warning instead of being exported.
      '';
    };

    # Named profiles — each generates an opencode-{name} wrapper script with its own config dir
    profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            scriptName = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Override the generated script name. Defaults to opencode-{profile-name}.";
            };
            config = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = "opencode.json content for this profile. MCP servers and plugins are inherited from the shared config.";
            };
            mcpServers = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = ''
                Allowlist of MCP server names to include in this profile.
                When null (default), the profile inherits ALL configured MCP
                servers (backwards-compatible). When set to a list, only the
                named servers are injected into this profile's opencode.json —
                this is the primary lever for reducing per-profile context
                creep (e.g. keep work/customer MCPs out of the personal profile).
              '';
              example = lib.literalExpression ''[ "obsidian" "nixos" "jira" ]'';
            };
          };
        }
      );
      default = { };
      description = ''
        Named opencode profiles. Each profile gets its own config dir under
        ~/.config/opencode-profiles/<name>/ (separate sessions/history) and a
        wrapper script opencode-<name> that launches opencode with that profile.
        MCP servers are shared from the main config.
      '';
      example = lib.literalExpression ''
        {
          work = {
            config = {
              model = "my-work-provider/some-model";
              provider."my-work-provider" = { ... };
            };
          };
          personal = {
            config = {
              model = "opencode/big-pickle";
              provider.groq = { ... };
            };
          };
        }
      '';
    };

    # Billing-context dispatcher (`oc` script)
    dispatcher = {
      enable = lib.mkEnableOption "the `oc` billing-context dispatcher script" // {
        default = true;
      };

      defaultContext = lib.mkOption {
        type = lib.types.str;
        default = "personal";
        description = "Billing context used when OPENCODE_BILLING_CONTEXT is unset.";
      };

      contexts = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              scriptName = lib.mkOption {
                type = lib.types.str;
                description = "Name of the profile wrapper script this context dispatches to (e.g. \"ocp\").";
              };
              apiKeyEnvVar = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Environment variable that must be populated (or have a matching
                  file under /run/secrets/) for this context. When null, no
                  API-key check is performed for the context.
                '';
              };
            };
          }
        );
        default = { };
        description = ''
          Billing contexts for the `oc` dispatcher. Each key is a context name
          (matched against OPENCODE_BILLING_CONTEXT) and maps to a profile
          wrapper script plus an optional required API-key env var. No
          customer-specific contexts are defined by default; consumers add their
          own (e.g. personal/groq contexts, or a work context that dispatches to
          a work wrapper script and requires a work API key). The `oc` script is
          only generated when at least one context is defined.
        '';
        example = lib.literalExpression ''
          {
            personal = { scriptName = "ocp"; apiKeyEnvVar = "OPENCODE_API_KEY"; };
            groq = { scriptName = "ocg"; apiKeyEnvVar = "GROQ_API_KEY"; };
          }
        '';
      };
    };

    # Skills configuration
    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        OpenCode skills to install. Keys are skill names (directory names),
        values are the content of the SKILL.md file.

        Skills are installed to ~/.config/opencode/skills/<name>/SKILL.md
      '';
      example = lib.literalExpression ''
        {
          "my-skill" = '''
            ---
            name: my-skill
            description: A custom skill
            ---
            # My Skill
            Instructions here...
          ''';
        }
      '';
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        OpenCode agents to install. Keys are agent filenames (without .md),
        values are the markdown content.
        Deployed to ~/.config/opencode/agents/<name>.md
      '';
    };

    commands = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        OpenCode commands to install. Keys are command filenames (without .md),
        values are the markdown content.
        Deployed to ~/.config/opencode/commands/<name>.md
      '';
    };

    references = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        OpenCode GSD-Core reference files to install. Keys are filenames,
        values are the file content.
        Deployed to ~/.config/opencode/gsd-core/references/<name>
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = ''
        OpenCode plugin files to install. Keys are filenames (relative to
        the plugins/ directory), values are store paths to the source files.
        Local plugin files are auto-loaded by OpenCode from this directory.
      '';
      example = lib.literalExpression ''
        let
          scv = pkgs.fetchFromGitHub {
            owner = "Caffa";
            repo = "Session-Character-Visualizer";
            rev = "v1.3.0";
            hash = "...";
          };
        in {
          "blob-office.ts" = "''${scv}/blob-office.ts";
          "blob-office.html" = "''${scv}/blob-office.html";
          "package.json" = "''${scv}/package.json";
        }
      '';
    };

    # ---- Exposed helpers (read-only, for other modules e.g. Zed ACP) ----
    # These let other home-manager modules reuse the sops secret-loading and
    # per-profile XDG_CONFIG_HOME logic without duplicating it. Set in `config`.
    _secretEnvScript = lib.mkOption {
      type = lib.types.str;
      internal = true;
      default = "";
      description = "Shell snippet that exports opencode sops secrets. Reusable by ACP wrappers.";
    };
    _mkAcpWrapper = lib.mkOption {
      type = lib.types.functionTo lib.types.package;
      internal = true;
      default = _: throw "opencode-config._mkAcpWrapper used before config eval (module disabled?)";
      defaultText = lib.literalMD "internal builder";
      description = ''
        Builder: given a profile name, returns a package whose binary launches
        `opencode acp` with that profile's XDG_CONFIG_HOME and secrets loaded.
        Usage: config.programs.opencode-config._mkAcpWrapper "work".
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      secretEnvNames = lib.attrNames cfg.secretEnv;
      # Shell-quoted, newline-separated list of placeholder sentinels used by the
      # guard below to detect unpopulated secrets.
      placeholderMatch = lib.concatMapStringsSep " | " (
        p: "${lib.escapeShellArg p}"
      ) cfg.secretPlaceholders;
      secretEnvScript = lib.concatMapStringsSep "\n" (name: ''
        if [ -r "${cfg.secretEnv.${name}}" ]; then
          __val="$( ${pkgs.coreutils}/bin/cat "${cfg.secretEnv.${name}}" )"
          # Trim surrounding whitespace/newlines for the placeholder comparison.
          __trimmed="$( printf '%s' "$__val" | ${pkgs.coreutils}/bin/tr -d '[:space:]' )"
          case "$__trimmed" in
            "" )
              echo "opencode: WARNING: secret '${name}' (${toString cfg.secretEnv.${name}}) is empty; not exporting. The dependent MCP server/provider may be disabled." >&2
              ;;
            ${placeholderMatch} )
              echo "opencode: WARNING: secret '${name}' (${toString cfg.secretEnv.${name}}) still holds a placeholder value; not exporting. Populate it in sops and rebuild. The dependent MCP server/provider will be unavailable until then." >&2
              ;;
            * )
              export ${name}="$__val"
              ;;
          esac
          unset __val __trimmed
        fi
      '') secretEnvNames;
      opencodeWrapper = pkgs.writeShellScriptBin "opencode" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        ${secretEnvScript}
        exec ${pkgs.opencode}/bin/opencode "$@"
      '';
      opencodePackage =
        if secretEnvNames == [ ] then
          pkgs.opencode
        else
          pkgs.symlinkJoin {
            name = "opencode-with-secrets";
            paths = [
              opencodeWrapper
              pkgs.opencode
            ];
          };

      # Build the per-profile shared base (MCP).
      # A profile may set `mcpServers` to an allowlist of server names; when set,
      # only those servers are injected into that profile (primary context-creep
      # lever). When null, the profile inherits all configured MCP servers.
      profileSharedBase =
        profileCfg:
        let
          selected =
            if profileCfg.mcpServers == null then
              mcpServers
            else
              lib.filterAttrs (name: _: builtins.elem name profileCfg.mcpServers) mcpServers;
        in
        lib.optionalAttrs (selected != { }) { mcp = selected; };

      # Generate a wrapper script for each profile (name defaults to opencode-{profileName})
      profileScripts = lib.mapAttrsToList (
        profileName: profileCfg:
        let
          scriptName =
            if profileCfg.scriptName != null then profileCfg.scriptName else "opencode-${profileName}";
        in
        pkgs.writeShellScriptBin scriptName ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail
          ${secretEnvScript}
          # Default to build agent unless --agent is explicitly passed
          if [[ ! " $* " =~ " --agent " ]]; then
            exec env XDG_CONFIG_HOME="$HOME/.config/opencode-profiles/${profileName}" \
              ${pkgs.opencode}/bin/opencode --agent build "$@"
          else
            exec env XDG_CONFIG_HOME="$HOME/.config/opencode-profiles/${profileName}" \
              ${pkgs.opencode}/bin/opencode "$@"
          fi
        ''
      ) cfg.profiles;

      # Generate the oc dispatcher script that reads OPENCODE_BILLING_CONTEXT.
      # Contexts (name -> {scriptName, apiKeyEnvVar}) come entirely from
      # programs.opencode-config.dispatcher.contexts — no customer-specific
      # contexts are baked in here; the consumer supplies them.
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

      ocDispatcher = pkgs.writeShellScriptBin "oc" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        # Available contexts and their required API keys
        declare -A CONTEXT_KEYS=(
        ${contextKeysLines}
        )

        # Map context to profile script
        declare -A CONTEXT_SCRIPTS=(
        ${contextScriptsLines}
        )

        # Default context
        CONTEXT="''${OPENCODE_BILLING_CONTEXT:-${cfg.dispatcher.defaultContext}}"

        # Handle --print-context flag
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

        # Validate context
        SCRIPT="''${CONTEXT_SCRIPTS[$CONTEXT]:-}"
        if [[ -z "$SCRIPT" ]]; then
          echo "ERROR: Invalid billing context '$CONTEXT'" >&2
          echo "Available contexts: ${availableContexts}" >&2
          exit 1
        fi

        # Check required API key (only if this context declares one)
        REQUIRED_KEY="''${CONTEXT_KEYS[$CONTEXT]:-}"
        if [[ -n "$REQUIRED_KEY" ]] && [[ -z "''${!REQUIRED_KEY:-}" ]]; then
          # Check if there's a secret file for it
          SECRET_FILE="/run/secrets/$(echo "$REQUIRED_KEY" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
          if [[ ! -r "$SECRET_FILE" ]]; then
            echo "ERROR: $REQUIRED_KEY not set (required for context '$CONTEXT')" >&2
            echo "Set the environment variable or ensure $SECRET_FILE exists" >&2
            exit 1
          fi
        fi

        echo "[BILLING CONTEXT: $CONTEXT]" >&2

        # Dispatch to the profile script
        exec "$SCRIPT" "$@"
      '';

      # Generate xdg.configFile entries for each profile (opencode.json)
      profileConfigFiles = lib.foldlAttrs (
        acc: profileName: profileCfg:
        let
          profileJson = lib.filterAttrs (k: v: v != null && v != { }) (
            lib.recursiveUpdate (profileSharedBase profileCfg) profileCfg.config
          );
        in
        acc
        // {
          "opencode-profiles/${profileName}/opencode/opencode.json" = {
            source = jsonFormat.generate "opencode-${profileName}.json" profileJson;
            force = true;
          };
        }
        // lib.mapAttrs' (
          skillName: content:
          lib.nameValuePair "opencode-profiles/${profileName}/opencode/skills/${skillName}/SKILL.md" {
            text = content;
          }
        ) cfg.skills
        // lib.mapAttrs' (
          name: content:
          lib.nameValuePair "opencode-profiles/${profileName}/opencode/agents/${name}.md" {
            text =
              builtins.replaceStrings [ "/tmp/gsd-capture/opencode/" ] [ "${config.xdg.configHome}/opencode/" ]
                content;
            force = true;
          }
        ) cfg.agents
        // lib.mapAttrs' (
          name: content:
          lib.nameValuePair "opencode-profiles/${profileName}/opencode/commands/${name}.md" {
            text =
              builtins.replaceStrings [ "/tmp/gsd-capture/opencode/" ] [ "${config.xdg.configHome}/opencode/" ]
                content;
            force = true;
          }
        ) cfg.commands
        // lib.mapAttrs' (
          name: content:
          lib.nameValuePair "opencode-profiles/${profileName}/opencode/gsd-core/references/${name}" {
            text = content;
            force = true;
          }
        ) cfg.references
        // lib.mapAttrs' (
          name: source:
          lib.nameValuePair "opencode-profiles/${profileName}/opencode/plugins/${name}" {
            source = source;
            force = true;
          }
        ) cfg.plugins
      ) { } cfg.profiles;
    in
    lib.mkMerge [
      {
        # Expose the secret-loader + ACP wrapper builder for other modules
        # (e.g. Zed ACP agent entries) to reuse without duplicating logic.
        programs.opencode-config._secretEnvScript = secretEnvScript;
        programs.opencode-config._mkAcpWrapper =
          profileName:
          pkgs.writeShellScriptBin "opencode-acp-${profileName}" ''
            #!${pkgs.bash}/bin/bash
            set -euo pipefail
            ${secretEnvScript}
            exec env XDG_CONFIG_HOME="$HOME/.config/opencode-profiles/${profileName}" \
              ${pkgs.opencode}/bin/opencode acp "$@"
          '';

        home.packages = [
          opencodePackage
        ]
        ++ lib.optional (cfg.dispatcher.enable && cfg.dispatcher.contexts != { }) ocDispatcher
        ++ lib.optional mcpCfg.mcpNixos.enable pkgs.mcp-nixos
        ++ profileScripts;

        # Purge a stray ~/opencode.json on every rebuild.
        #
        # OpenCode loads the managed global config from ~/.config/opencode (or a
        # profile's XDG_CONFIG_HOME), but it ALSO walks up from the current
        # working directory looking for a project-level opencode.json. A file at
        # $HOME root is found by that walk-up from any session started under
        # $HOME and SHADOWS the managed config — silently pinning agents/models
        # to stale values (e.g. compaction -> meta/llama-3.1-8b-instruct, which
        # the active provider key cannot access). Such a file is never something Nix
        # creates here, so remove it if it exists as a plain file (never touch a
        # symlink, which would be a deliberate user/HM-managed link).
        home.activation.opencodePurgeStrayConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          STRAY="$HOME/opencode.json"
          if [ -f "$STRAY" ] && [ ! -L "$STRAY" ]; then
            run mv "$STRAY" "$STRAY.stale.bak"
            run echo "opencode: moved stray $STRAY (shadowed managed config) -> $STRAY.stale.bak"
          fi
        '';

        xdg.configFile = {
          "opencode/opencode.json" = {
            source = jsonFormat.generate "opencode.json" opencodeConfig;
            force = true;
          };
        }
        // lib.mapAttrs' (
          name: content:
          lib.nameValuePair "opencode/skills/${name}/SKILL.md" {
            text = content;
          }
        ) cfg.skills
        // lib.mapAttrs' (
          name: content:
          lib.nameValuePair "opencode/agents/${name}.md" {
            text =
              builtins.replaceStrings [ "/tmp/gsd-capture/opencode/" ] [ "${config.xdg.configHome}/opencode/" ]
                content;
            force = true;
          }
        ) cfg.agents
        // lib.mapAttrs' (
          name: content:
          lib.nameValuePair "opencode/commands/${name}.md" {
            text =
              builtins.replaceStrings [ "/tmp/gsd-capture/opencode/" ] [ "${config.xdg.configHome}/opencode/" ]
                content;
            force = true;
          }
        ) cfg.commands
        // lib.mapAttrs' (
          name: content:
          lib.nameValuePair "opencode/gsd-core/references/${name}" {
            text = content;
            force = true;
          }
        ) cfg.references
        // lib.mapAttrs' (
          name: source:
          lib.nameValuePair "opencode/plugins/${name}" {
            source = source;
            force = true;
          }
        ) cfg.plugins
        // profileConfigFiles;
      }

      (lib.mkIf cfg.notifications.telegram.enable {
        home.packages = [
          (pkgs.writeShellScriptBin "send-telegram-message" ''
            TOKEN=$(cat /run/secrets/telegram-bot-token 2>/dev/null)
            CHAT_ID=$(cat /run/secrets/telegram-user-id 2>/dev/null)
            if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
              echo "Error: Telegram secrets not found at /run/secrets/" >&2
              exit 1
            fi
            if [ $# -gt 0 ]; then
              MESSAGE="$*"
            else
              MESSAGE=$(cat)
            fi
            curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
              -d "chat_id=$CHAT_ID" \
              -d "text=$MESSAGE" \
              -d "parse_mode=markdown" > /dev/null
          '')
        ]
        ++ lib.optionals cfg.notifications.telegram.enableShellHook [
          (pkgs.writeShellScriptBin "opencode-with-notifications" ''
            opencode "$@"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
              send-telegram-message "opencode: Task completed successfully"
            else
              send-telegram-message "opencode: Task failed (exit $EXIT_CODE)"
            fi
            exit $EXIT_CODE
          '')
        ];
      })
    ]
  );
}
