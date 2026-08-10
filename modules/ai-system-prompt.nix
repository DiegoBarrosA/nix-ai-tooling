# Centralized system prompt sourced from the Notes vault.
#
# Sources:
#   - vaultPromptsDir/System/*.md  (sorted, concatenated — single source of truth)
#
# Staging:
#   ~/.local/share/ai-system-prompt/system-prompt.md  (merged result)
#
# Per-tool deployment:
#   - Claude Code:   ~/.claude/CLAUDE.md               (overwrite on activation)
#   - Cursor:        ~/.cursor/rules/00-system-prompt.mdc
#   - Antigravity:   ~/.gemini/AGENTS.md               (prepended before skills,
#                    runs after aiSkills activation so skills are already there)
#
# Live reload without rebuild:
#   sync-ai-system-prompt  — re-reads vault and redeploys to Claude + Cursor.
#   Note: Antigravity AGENTS.md requires a full activation (skills + prompt are
#   merged in a single pass at switch time) — run `home-manager switch` for that.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.ai-system-prompt;
  coreutils = pkgs.coreutils;
  bash = pkgs.bash;

  stagingFile = "${config.home.homeDirectory}/.local/share/ai-system-prompt/system-prompt.md";

  # Shell fragment that builds the merged system prompt into $STAGING.
  # Used in both the activation script and the helper package.
  buildStagingScript = ''
    mkdir -p "$(${coreutils}/bin/dirname "${stagingFile}")"
    : > "${stagingFile}"

    ${lib.optionalString (cfg.header != "") ''
      printf '%s\n\n' ${lib.escapeShellArg cfg.header} >> "${stagingFile}"
    ''}

    PROMPTS_DIR="${cfg.vaultPromptsDir}/System"
    if [ -d "$PROMPTS_DIR" ]; then
      while IFS= read -r -d "" f; do
        [ -f "$f" ] || continue
        ${coreutils}/bin/cat "$f" >> "${stagingFile}"
        printf '\n\n' >> "${stagingFile}"
      done < <(${pkgs.findutils}/bin/find "$PROMPTS_DIR" -maxdepth 1 -name "*.md" -print0 | sort -z)
    fi
  '';

  # Shell fragment that deploys the staged prompt to each enabled tool.
  deployScript = ''
    if [ ! -s "${stagingFile}" ]; then
      echo "ai-system-prompt: staging file is empty — nothing to deploy" >&2
    else
      ${lib.optionalString cfg.tools.claude ''
        ${coreutils}/bin/cp "${stagingFile}" "$HOME/.claude/CLAUDE.md"
      ''}
      ${lib.optionalString cfg.tools.cursor ''
        ${coreutils}/bin/mkdir -p "$HOME/.cursor/rules"
        {
          printf -- '---\ndescription: Global system prompt from Notes vault\nalwaysApply: true\n---\n\n'
          ${coreutils}/bin/cat "${stagingFile}"
        } > "$HOME/.cursor/rules/00-system-prompt.mdc"
      ''}
    fi
  '';

  # Antigravity is handled separately (must run after aiSkills wipes AGENTS.md).
  antigravityDeployScript = ''
    if [ -s "${stagingFile}" ]; then
      AG="$HOME/.gemini/AGENTS.md"
      ${coreutils}/bin/mkdir -p "$(${coreutils}/bin/dirname "$AG")"
      TMP="${stagingFile}.ag.tmp"
      ${coreutils}/bin/cat "${stagingFile}" > "$TMP"
      if [ -s "$AG" ]; then
        printf '\n\n---\n\n' >> "$TMP"
        ${coreutils}/bin/cat "$AG" >> "$TMP"
      fi
      ${coreutils}/bin/mv "$TMP" "$AG"
    fi
  '';
in
{
  options.programs.ai-system-prompt = {
    enable = lib.mkEnableOption "system prompt standardization from Notes vault";

    vaultPromptsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Notes/AI/Prompts";
      description = ''
        Vault prompts directory. All *.md files under System/ are concatenated
        (sorted alphabetically) to form the unified system prompt.
      '';
    };

    header = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Static Markdown content prepended before vault System/*.md files.
        Use for a persona context block that is not stored in the vault
        (e.g. "You are Diego's personal AI assistant...").
      '';
      example = ''
        You are Diego's personal AI assistant. You help with software engineering,
        PKM, and career development. Be concise and direct.
      '';
    };

    tools = {
      claude = lib.mkEnableOption "deploy system prompt to Claude Code (~/.claude/CLAUDE.md)" // {
        default = true;
      };
      cursor = lib.mkEnableOption "deploy system prompt to Cursor (~/.cursor/rules/)" // {
        default = true;
      };
      antigravity = lib.mkEnableOption "prepend system prompt to Antigravity AGENTS.md" // {
        default = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Build staging file and deploy to Claude + Cursor.
    # Must run after writeBoundary so home.file symlinks are in place.
    # Antigravity deploy is in a second activation step after aiSkills.
    home.activation.aiSystemPrompt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${buildStagingScript}
      ${deployScript}
    '';

    # Prepend to AGENTS.md after aiSkills has written its skills section.
    home.activation.aiSystemPromptAntigravity = lib.mkIf cfg.tools.antigravity (
      lib.hm.dag.entryAfter [ "aiSkills" "aiSystemPrompt" ] ''
        ${antigravityDeployScript}
      ''
    );

    # Helper script: live-reload Claude + Cursor without a full rebuild.
    # Antigravity requires `home-manager switch` (skills + prompt merged in one pass).
    home.packages = [
      (pkgs.writeShellScriptBin "sync-ai-system-prompt" ''
        #!${bash}/bin/bash
        set -euo pipefail

        ${buildStagingScript}

        if [ ! -s "${stagingFile}" ]; then
          echo "ai-system-prompt: no content found in ${cfg.vaultPromptsDir}/System — nothing synced" >&2
          exit 1
        fi

        echo "ai-system-prompt: synced from ${cfg.vaultPromptsDir}/System"

        ${lib.optionalString cfg.tools.claude ''
          ${coreutils}/bin/cp "${stagingFile}" "$HOME/.claude/CLAUDE.md"
          echo "  -> ~/.claude/CLAUDE.md"
        ''}
        ${lib.optionalString cfg.tools.cursor ''
          mkdir -p "$HOME/.cursor/rules"
          {
            printf -- '---\ndescription: Global system prompt from Notes vault\nalwaysApply: true\n---\n\n'
            ${coreutils}/bin/cat "${stagingFile}"
          } > "$HOME/.cursor/rules/00-system-prompt.mdc"
          echo "  -> ~/.cursor/rules/00-system-prompt.mdc"
        ''}

        echo ""
        echo "Note: Antigravity AGENTS.md (system prompt + skills) requires 'home-manager switch'."
      '')
    ];
  };
}
