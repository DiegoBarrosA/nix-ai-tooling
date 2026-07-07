{
  description = "Reusable home-manager modules for AI agents: MCP registry, OpenCode profiles, Claude Code / Cursor / Antigravity config generators, cross-agent skills";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    homeManagerModules = rec {
      mcp-config = import ./modules/mcp-config.nix;
      opencode-config = import ./modules/opencode-config.nix;
      claude-code-config = import ./modules/claude-code-config.nix;
      cursor-config = import ./modules/cursor-config.nix;
      antigravity-config = import ./modules/antigravity-config.nix;
      ai-skills = import ./modules/ai-skills.nix;
      default = { ... }: {
        imports = [
          mcp-config
          opencode-config
          claude-code-config
          cursor-config
          antigravity-config
          ai-skills
        ];
      };
    };
  };
}
