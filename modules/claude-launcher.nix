# Builds the launcher script for one Claude Code profile.
# With tokenFile set, the token is read at launch (never into the store) and
# exported as CLAUDE_CODE_OAUTH_TOKEN; a missing or empty file is a hard error.
{ pkgs, lib }:
{
  name,
  configDir,
  tokenFile ? null,
  exe,
}:
pkgs.writeShellScriptBin name ''
  export CLAUDE_CONFIG_DIR=${lib.escapeShellArg configDir}
  ${lib.optionalString (tokenFile != null) ''
    __token="$(${pkgs.coreutils}/bin/tr -d '[:space:]' < ${lib.escapeShellArg tokenFile} 2>/dev/null || true)"
    if [ -z "$__token" ]; then
      echo "${name}: token file ${tokenFile} missing or empty" >&2
      exit 1
    fi
    export CLAUDE_CODE_OAUTH_TOKEN="$__token"
    unset __token
  ''}
  exec ${exe} "$@"
''
