# Install with Codex

This is the canonical agent procedure. A repository URL plus “帮我安装” or “install this” is sufficient. Releases are Windows x64 Portable ZIPs only.

## Deterministic Portable procedure

1. Confirm the repository is `https://github.com/wassamriehlei/codex-monitor-hud` and read `install-manifest.json`.
2. Select `windows-x64`. Confirm that Microsoft .NET 10 Desktop Runtime x64 is installed. If it is missing, direct the user to `https://dotnet.microsoft.com/download/dotnet/10.0` and wait for them to install **Desktop Runtime**.
3. Download the manifest's exact-tag Portable ZIP and `SHA256SUMS.txt` from GitHub Releases.
4. Verify that the checksum file contains exactly the expected asset name, then verify the ZIP's SHA-256 before extraction.
5. Extract every file to a new user-writable directory. The HUD itself needs no administrator access; its system-wide Desktop Runtime prerequisite may request elevation through Microsoft's installer.
6. For an upgrade, close the old HUD, retain the existing `portable-data` directory, replace the remaining application files, and restore `portable-data` unchanged.
7. Start `CodexMonitorHUD.exe`. Open settings from the HUD or notification-area menu; automation can run `CodexMonitorHUD.exe --open-settings`.
8. Confirm that `portable-data\CodexMonitorHUD\hud.heartbeat` is fresh. Report the version, asset checksum, extraction directory, data directory, and heartbeat result.

Do not run the EXE from inside the ZIP. A checksum mismatch, archive traversal path, missing marker, missing root EXE, wrong architecture, or stale heartbeat must stop the operation. Do not upload local evidence or read prompts, replies, tool output, credentials, provider configuration, or settings values.

## Upgrade and rollback

- Upgrade: keep the old `portable-data` directory, fully extract the new ZIP, and place the retained data directory beside the new EXEs.
- Rollback: keep the previous extracted application directory or release ZIP, then pair it with the same retained `portable-data` directory.
- Reset: exit the HUD and rename `portable-data` only when the user explicitly asks to reset settings.

## Desktop, CLI, and WSL monitoring

The HUD can monitor independently selectable local sources:

- Codex Desktop and VS Code sessions under the normal `CODEX_HOME`;
- native Windows Codex CLI sessions;
- WSL Codex CLI sessions selected in **Settings > Sources**;
- the optional isolated `~/.codex-deepseek` CLI profile.

Source detection uses bounded session metadata. The HUD does not need provider configuration or authentication files. Future model IDs remain monitorable without an allowlist.

## Optional plugin and MCP connection

The Portable package includes `.codex-plugin` and `.mcp.json`. Connect these only when the user asks Codex to operate the HUD or send opt-in notices. A normal Portable HUD run does not require the plugin.

The bundled server exposes HUD operations and privacy-safe task number/source metadata. See [docs/MCP_INTEGRATION.md](docs/MCP_INTEGRATION.md).

## Language

Simplified Chinese is the default. English can be selected in Settings. Upgrades preserve the saved preference in `portable-data`.
