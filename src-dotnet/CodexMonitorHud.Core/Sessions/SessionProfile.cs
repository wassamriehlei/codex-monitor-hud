using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Core.Sessions;

public sealed record SessionProfile(
    string Id,
    string Label,
    string SessionsRoot,
    string SessionIndexPath,
    string DefaultClientSurface,
    string DefaultProvider,
    string StateDatabasePath = "")
{
    public const string DefaultId = "codex";
    public const string DeepSeekId = "deepseek";
    public const string WslId = "wsl";

    public static IReadOnlyList<SessionProfile> CreateDefaultSet(HudPaths paths, string? wslHome = null)
    {
        var defaultProfileRoot = Path.GetDirectoryName(paths.SessionsRoot)
            ?? throw new InvalidOperationException("The default Codex profile root could not be resolved.");
        var home = Path.GetDirectoryName(defaultProfileRoot)
            ?? throw new InvalidOperationException("The user profile root could not be resolved.");
        var deepSeekProfileRoot = Path.Combine(home, ".codex-deepseek");
        var profiles = new List<SessionProfile>
        {
            new SessionProfile(
                DefaultId,
                "Codex",
                paths.SessionsRoot,
                Path.Combine(defaultProfileRoot, "session_index.jsonl"),
                "unknown",
                string.Empty,
                Path.Combine(defaultProfileRoot, "state_5.sqlite")),
            new SessionProfile(
                DeepSeekId,
                "DeepSeek",
                Path.Combine(deepSeekProfileRoot, "sessions"),
                Path.Combine(deepSeekProfileRoot, "session_index.jsonl"),
                "cli",
                "deepseek",
                Path.Combine(deepSeekProfileRoot, "state_5.sqlite"))
        };
        if (!string.IsNullOrWhiteSpace(wslHome))
        {
            var wslProfileRoot = Path.Combine(Path.GetFullPath(wslHome), ".codex");
            profiles.Add(new SessionProfile(
                WslId,
                "WSL",
                Path.Combine(wslProfileRoot, "sessions"),
                Path.Combine(wslProfileRoot, "session_index.jsonl"),
                "cli",
                string.Empty,
                Path.Combine(wslProfileRoot, "state_5.sqlite")));
        }
        return profiles;
    }
}
