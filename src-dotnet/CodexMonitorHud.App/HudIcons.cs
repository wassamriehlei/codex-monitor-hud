using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

namespace CodexMonitorHud.App;

// Lucide icons, ISC License. See THIRD_PARTY_NOTICES.md.
internal static class HudIcons
{
    internal const string ExternalLink = "M15,3 H21 V9 M10,14 L21,3 M18,13 V19 A2,2 0 0 1 16,21 H5 A2,2 0 0 1 3,19 V8 A2,2 0 0 1 5,6 H11";
    internal const string Minimize = "M14,10 L21,3 M20,10 H14 V4 M3,21 L10,14 M4,14 H10 V20";
    internal const string Close = "M18,6 L6,18 M6,6 L18,18";
    internal const string Monitor = "M4,3 H20 A2,2 0 0 1 22,5 V15 A2,2 0 0 1 20,17 H4 A2,2 0 0 1 2,15 V5 A2,2 0 0 1 4,3 M8,21 H16 M12,17 V21";
    internal const string CodeXml = "M18,16 L22,12 L18,8 M6,8 L2,12 L6,16 M14.5,4 L9.5,20";
    internal const string Terminal = "M12,19 H20 M4,17 L10,11 L4,5";
    internal const string WavesHorizontal = "M2,12 Q4.5,14 7,12 T12,12 T17,12 T22,12 M2,19 Q4.5,21 7,19 T12,19 T17,19 T22,19 M2,5 Q4.5,7 7,5 T12,5 T17,5 T22,5";
    internal const string ChevronDown = "M6,9 L12,15 L18,9";
    internal const string ChevronUp = "M18,15 L12,9 L6,15";

    internal static string Source(SessionState state)
    {
        if (string.Equals(state.ClientSurface, "vscode", StringComparison.OrdinalIgnoreCase))
        {
            return CodeXml;
        }
        if (string.Equals(state.ClientSurface, "desktop", StringComparison.OrdinalIgnoreCase))
        {
            return Monitor;
        }
        if (string.Equals(state.ModelProvider, "deepseek", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(state.ProfileId, SessionProfile.DeepSeekId, StringComparison.OrdinalIgnoreCase))
        {
            return WavesHorizontal;
        }
        return Terminal;
    }
}
