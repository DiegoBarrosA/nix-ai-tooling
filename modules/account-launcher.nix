# Builds a launcher script for one agent account.
#   env:   VAR -> secret file path. Read at launch (never into the store),
#          whitespace stripped; a missing or empty file is a hard error.
#   fixed: VAR -> literal value (config/data dirs, HOME).
#   pre:   shell run after the exports and before exec (for example, seeding a settings file).
{ pkgs, lib }:
{
  name,
  exe,
  env ? { },
  fixed ? { },
  pre ? "",
}:
pkgs.writeShellScriptBin name ''
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") fixed)}
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: file: ''
      __v="$(${pkgs.coreutils}/bin/tr -d '[:space:]' < ${lib.escapeShellArg file} 2>/dev/null || true)"
      if [ -z "$__v" ]; then
        echo "${name}: token file ${file} missing or empty" >&2
        exit 1
      fi
      export ${k}="$__v"
      unset __v
    '') env
  )}
  ${pre}
  exec ${exe} "$@"
''
