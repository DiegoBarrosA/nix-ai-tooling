{
  description = "Reusable home-manager modules for AI agents: MCP registry, OpenCode / Jcode profiles, Claude Code / Cursor / Antigravity config generators, cross-agent skills";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    checks.x86_64-linux.claude-launcher =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        mk = import ./modules/claude-launcher.nix { inherit pkgs; inherit (nixpkgs) lib; };
        stub = pkgs.writeShellScript "stub" ''echo "token=$CLAUDE_CODE_OAUTH_TOKEN dir=$CLAUDE_CONFIG_DIR"'';
        missing = mk { name = "claude-m"; configDir = "/cfg"; tokenFile = "/nonexistent/tok"; exe = stub; };
        noTok = mk { name = "claude-n"; configDir = "/cfg"; exe = stub; };
        viaFile = mk { name = "claude-f"; configDir = "/cfg"; tokenFile = "/tmp/claude-launcher-check-tok"; exe = stub; };
      in
      pkgs.runCommand "claude-launcher-check" { } ''
        set -eu
        # missing token file: hard error that names the file
        if ${missing}/bin/claude-m 2>err; then echo "expected failure"; exit 1; fi
        grep -q "token file /nonexistent/tok missing or empty" err
        # no tokenFile: nothing exported, config dir kept, script has no token logic
        ${noTok}/bin/claude-n | grep -q "token= dir=/cfg"
        if grep -q CLAUDE_CODE_OAUTH_TOKEN ${noTok}/bin/claude-n; then echo "token logic leaked"; exit 1; fi
        # the token path is baked in, never its value
        grep -q "/tmp/claude-launcher-check-tok" ${viaFile}/bin/claude-f
        touch $out
      '';

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
      happier-config = import ./modules/happier-config.nix;
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
          happier-config
        ];
      };
    };
  };
}
