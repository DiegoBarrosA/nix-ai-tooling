# Centralized AI skills sourced from the Notes vault plus optional extra
# skill repos.
#
# Sources:
#   - vaultSkillsDir:   <vaultSkillsDir>/<skill-name>/SKILL.md   (single source of truth)
#   - extraSkillSources: list of dirs, each containing <skill-name>/SKILL.md
#
# All sources are merged (per-skill symlinks) into a single staging directory,
# which is then wired into each tool:
#   - OpenCode:    ~/.config/opencode/skills            (symlink to merged dir)
#   - Jcode:       ~/.jcode/skills                      (symlink to merged dir)
#   - Codex:       ~/.codex/skills                      (symlink to merged dir)
#   - Claude Code: ~/.claude/skills                     (symlink to merged dir)
#   - Cursor:      ~/.cursor/rules/<name>.mdc           (best-effort copy)
#   - Antigravity: ~/.gemini/AGENTS.md                  (concatenated)
#
# Native SKILL.md tools (OpenCode/Jcode/Codex/Claude) get the real files;
# Cursor and Antigravity get derived representations because they do not
# consume SKILL.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.ai-skills;
  coreutils = pkgs.coreutils;
in
{
  options.programs.ai-skills = {
    enable = lib.mkEnableOption "Centralized AI skills sourced from the Notes vault";

    vaultSkillsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Notes/AI/Skills";
      description = "Canonical skills directory. Each skill is <name>/SKILL.md.";
    };

    extraSkillSources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''[ "''${inputs.extra-skills}/skills" ]'';
      description = ''
        Additional skill source directories. Each must contain
        <skill-name>/SKILL.md entries. Merged alongside vaultSkillsDir.
        On name collision, vaultSkillsDir wins (later sources do not clobber).
      '';
    };

    stagingDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/ai-skills/merged";
      description = ''
        Directory where all skill sources are merged (per-skill symlinks).
        Tools that consume a skills directory are symlinked to this path.
      '';
    };

    tools = {
      opencode = lib.mkEnableOption "wire skills into OpenCode" // {
        default = true;
      };
      jcode = lib.mkEnableOption "wire skills into Jcode" // {
        default = true;
      };
      codex = lib.mkEnableOption "wire skills into Codex" // {
        default = true;
      };
      claude = lib.mkEnableOption "wire skills into Claude Code" // {
        default = true;
      };
      cursor = lib.mkEnableOption "wire skills into Cursor" // {
        default = true;
      };
      antigravity = lib.mkEnableOption "wire skills into Antigravity" // {
        default = true;
      };
    };

    opencodeProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "OpenCode profile names whose skills dir should also symlink to the merged dir.";
    };

    jcodeProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Jcode profile names whose skills dir should also symlink to the merged dir.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.aiSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      VAULT="${cfg.vaultSkillsDir}"
      STAGING="${cfg.stagingDir}"

      # Ordered source list: vault first (wins on collisions), then extras.
      SOURCES=("$VAULT" ${lib.concatMapStringsSep " " (s: ''"${s}"'') cfg.extraSkillSources})

      # Build a fresh merged staging dir of per-skill symlinks. Vault takes
      # precedence: a skill name is only linked from the first source that has it.
      ${coreutils}/bin/rm -rf "$STAGING"
      ${coreutils}/bin/mkdir -p "$STAGING"
      any_source=0
      for SRC in "''${SOURCES[@]}"; do
        [ -d "$SRC" ] || continue
        any_source=1
        for d in "$SRC"/*/; do
          [ -f "$d/SKILL.md" ] || continue
          name="$(${coreutils}/bin/basename "$d")"
          # Skip if a higher-precedence source already provided this skill.
          [ -e "$STAGING/$name" ] && continue
          ${coreutils}/bin/ln -sfn "''${d%/}" "$STAGING/$name"
        done
      done

      if [ "$any_source" -eq 0 ]; then
        echo "ai-skills: no skill sources found (vault: $VAULT) — skipping" >&2
      else
        # Symlink a tool's skills directory to the merged staging dir.
        link_dir() {
          target="$1"
          ${coreutils}/bin/mkdir -p "$(${coreutils}/bin/dirname "$target")"
          if [ -e "$target" ] && [ ! -L "$target" ]; then
            ${coreutils}/bin/mv "$target" "$target.bak" 2>/dev/null || ${coreutils}/bin/rm -rf "$target"
          fi
          ${coreutils}/bin/ln -sfn "$STAGING" "$target"
        }

        ${lib.optionalString cfg.tools.opencode ''
          link_dir "$HOME/.config/opencode/skills"
        ''}
        ${lib.concatMapStringsSep "\n" (p: ''
          link_dir "$HOME/.config/opencode-profiles/${p}/opencode/skills"
        '') cfg.opencodeProfiles}
        ${lib.optionalString cfg.tools.jcode ''
          link_dir "$HOME/.jcode/skills"
        ''}
        ${lib.concatMapStringsSep "\n" (p: ''
          link_dir "$HOME/.jcode-profiles/${p}/.jcode/skills"
        '') cfg.jcodeProfiles}
        ${lib.optionalString cfg.tools.codex ''
          link_dir "$HOME/.codex/skills"
        ''}
        ${lib.optionalString cfg.tools.claude ''
          link_dir "$HOME/.claude/skills"
        ''}
        ${lib.optionalString cfg.tools.cursor ''
          RULES_DIR="$HOME/.cursor/rules"
          ${coreutils}/bin/mkdir -p "$RULES_DIR"
          for d in "$STAGING"/*/; do
            [ -f "$d/SKILL.md" ] || continue
            name="$(${coreutils}/bin/basename "$d")"
            ${coreutils}/bin/cp -fL "$d/SKILL.md" "$RULES_DIR/$name.mdc"
          done
        ''}
        ${lib.optionalString cfg.tools.antigravity ''
          AG="$HOME/.gemini/AGENTS.md"
          ${coreutils}/bin/mkdir -p "$(${coreutils}/bin/dirname "$AG")"
          : > "$AG"
          for d in "$STAGING"/*/; do
            [ -f "$d/SKILL.md" ] || continue
            name="$(${coreutils}/bin/basename "$d")"
            printf '## %s\n\n' "$name" >> "$AG"
            ${coreutils}/bin/cat "$d/SKILL.md" >> "$AG"
            printf '\n\n' >> "$AG"
          done
        ''}
      fi
    '';
  };
}
