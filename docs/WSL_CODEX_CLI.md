# Monitor a WSL Codex CLI from the Windows HUD

The HUD remains a native Windows application. Its optional Codex plugin can bridge a Codex CLI running inside WSL to that Windows process, while the session records stay inside the Linux distribution.

## Recommended setup: connect from Settings

Open **Settings → Sources**, enable **Codex in WSL**, choose a distribution, and click **Detect distribution and home**. You may also enter `\\wsl.localhost\Ubuntu\home\your-user` manually.

When the status says connected, the HUD restarts automatically and scans the Windows default profile and the independent WSL profile together. The two sources can be toggled independently. If `.codex/sessions` does not exist yet, run Codex CLI once in that distribution and detect again.

A path supplied to older versions through `CODEX_MONITOR_HUD_HOME` appears in the new UI and migrates on the next settings save. Windows startup also captures the current WSL path.

## WSL-side plugin configuration

Install the Windows HUD first. In the plugin source used by the WSL Codex CLI, set `.mcp.json` to the following shape and replace `WINDOWS_USER`, `DISTRO`, and `WSL_USER`:

```json
{
  "mcpServers": {
    "codex-monitor-hud": {
      "command": "node.exe",
      "args": [
        "C:\\Users\\WINDOWS_USER\\plugins\\codex-monitor-hud\\src\\mcp-server.mjs"
      ],
      "env": {
        "CODEX_MONITOR_HUD_STATE_ROOT": "C:\\Users\\WINDOWS_USER\\AppData\\Local\\CodexMonitorHUD",
        "CODEX_MONITOR_HUD_HOME": "\\\\wsl.localhost\\DISTRO\\home\\WSL_USER",
        "WSLENV": "CODEX_MONITOR_HUD_STATE_ROOT/w:CODEX_MONITOR_HUD_HOME/w"
      }
    }
  }
}
```

`WSLENV` is required. WSL does not forward arbitrary Linux environment variables to a launched Windows executable; the `/w` entries explicitly carry these two values from WSL into `node.exe`, PowerShell, and the compiled HUD.

The configured home must contain `.codex/sessions`. WSL is an independent read-only source; the HUD does not change that profile.

After updating or reinstalling the plugin, start a new Codex task so a changed MCP configuration is loaded. Monitoring sessions alone does not require the WSL CLI to load the MCP server; the WSL-side MCP is used for status tools and notices. Changing the monitored path in Settings automatically restarts the single HUD instance.

## Verification

The installed compiled host supports `--self-test`; a working bridge reports `visible_tasks` greater than zero while a recent task exists. The MCP `monitor_hud_status` result should report a fresh heartbeat, `wsl: true`, and identify WSL tasks as `profile: "wsl"` under `active_tasks`.

This is a Windows-hosted WSL bridge, not a Linux GUI build. Blur/Acrylic, fonts, audio, notification-area controls, and shortcuts are still provided by Windows.
