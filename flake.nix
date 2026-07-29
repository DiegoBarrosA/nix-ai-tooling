{
  description = "Reusable home-manager modules for AI agents: MCP registry, OpenCode / Jcode profiles, Claude Code / Cursor / Antigravity config generators, cross-agent skills";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    homeManagerModules = rec {
      mcp-config = import ./modules/mcp-config.nix;
      opencode-config = import ./modules/opencode-config.nix;
      jcode-config = import ./modules/jcode-config.nix;
      claude-code-config = import ./modules/claude-code-config.nix;
      claude-desktop-config = import ./modules/claude-desktop-config.nix;
      cursor-config = import ./modules/cursor-config.nix;
      antigravity-config = import ./modules/antigravity-config.nix;
      ai-skills = import ./modules/ai-skills.nix;
      ai-system-prompt = import ./modules/ai-system-prompt.nix;
      default = { ... }: {
        imports = [
          mcp-config
          opencode-config
          jcode-config
          claude-code-config
          claude-desktop-config
          cursor-config
          antigravity-config
          ai-skills
          ai-system-prompt
        ];
      };
    };
  };
}
