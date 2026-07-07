# Cursor CLI MCP configuration module for Home Manager
# Generates ~/.cursor/mcp.json
# Consumes programs.mcp-config.standardFormat
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.cursor-config;
  mcpCfg = config.programs.mcp-config;
  jsonFormat = pkgs.formats.json { };

  # Merge shared MCP servers with any Cursor-specific extras
  fullConfig = {
    mcpServers = mcpCfg.standardFormat.mcpServers // cfg.extraMcpServers;
  };
in
{
  options.programs.cursor-config = {
    enable = lib.mkEnableOption "Cursor CLI MCP configuration";

    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional MCP servers specific to Cursor (in standard MCP format).";
      example = lib.literalExpression ''
        {
          "custom-server" = {
            command = "npx";
            args = [ "-y" "my-mcp-server" ];
            env = {
              API_KEY = "''${MY_API_KEY}";
            };
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".cursor/mcp.json" = {
      source = jsonFormat.generate "mcp.json" fullConfig;
    };
  };
}
