{
  description = "Reusable home-manager modules for AI agents: MCP registry, OpenCode / Jcode profiles, Claude Code / Cursor / Antigravity config generators, cross-agent skills";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    checks.x86_64-linux.account-launcher =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        mk = import ./modules/account-launcher.nix { inherit pkgs; inherit (nixpkgs) lib; };
        stub = pkgs.writeShellScript "stub" ''echo "a=$A b=$B dir=$D"'';
        keyA = pkgs.writeText "keyA" "alpha\n";
        keyB = pkgs.writeText "keyB" "  beta  \n";
        empty = pkgs.writeText "empty" "  \n";
        two = mk { name = "t-two"; exe = stub; env = { A = keyA; B = keyB; }; fixed.D = "/cfg"; };
        missing = mk { name = "t-miss"; exe = stub; env.A = "/nonexistent/tok"; };
        emptyF = mk { name = "t-empty"; exe = stub; env.A = empty; };
        bare = mk { name = "t-bare"; exe = stub; fixed.D = "/cfg"; };
        withPre = mk { name = "t-pre"; exe = stub; pre = "echo pre-ran >&2"; };
      in
      pkgs.runCommand "account-launcher-check" { } ''
        set -eu
        # two secrets (whitespace stripped) plus a fixed var
        [ "$(${two}/bin/t-two)" = "a=alpha b=beta dir=/cfg" ]
        # missing and empty files are hard errors that name the file
        if ${missing}/bin/t-miss 2>err; then echo "expected failure"; exit 1; fi
        grep -q "token file /nonexistent/tok missing or empty" err
        if ${emptyF}/bin/t-empty 2>err; then echo "expected failure"; exit 1; fi
        grep -q "missing or empty" err
        # no secrets: no token logic at all
        [ "$(${bare}/bin/t-bare)" = "a= b= dir=/cfg" ]
        if grep -q "missing or empty" ${bare}/bin/t-bare; then echo "token logic leaked"; exit 1; fi
        # pre hook runs before exec
        preout="$(${withPre}/bin/t-pre 2>&1)"; case "$preout" in *pre-ran*) ;; *) echo "pre hook did not run"; exit 1;; esac
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
