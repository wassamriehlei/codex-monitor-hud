using System.Runtime.InteropServices;
using System.Windows.Media;

namespace CodexMonitorHud.App;

internal static class WindowBackdrop
{
    private const int WindowCompositionAttributeAccentPolicy = 19;
    private const int AccentDisabled = 0;
    private const int AccentBlurBehind = 3;
    private const int AccentAcrylicBlurBehind = 4;

    [StructLayout(LayoutKind.Sequential)]
    private struct AccentPolicy
    {
        internal int State;
        internal int Flags;
        internal int GradientColor;
        internal int AnimationId;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct WindowCompositionAttributeData
    {
        internal int Attribute;
        internal nint Data;
        internal int SizeOfData;
    }

    internal static bool IsEnabled(string mode) => mode is "blur" or "acrylic";

    internal static bool Apply(nint handle, string mode, string background, double opacity)
    {
        if (handle == 0)
        {
            return false;
        }

        var state = mode switch
        {
            "blur" => AccentBlurBehind,
            "acrylic" => AccentAcrylicBlurBehind,
            _ => AccentDisabled
        };
        var policy = new AccentPolicy
        {
            State = state,
            Flags = state == AccentAcrylicBlurBehind ? 2 : 0,
            GradientColor = state == AccentDisabled ? 0 : ToAbgr(background, opacity, state == AccentAcrylicBlurBehind),
            AnimationId = 0
        };
        var size = Marshal.SizeOf<AccentPolicy>();
        var pointer = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(policy, pointer, false);
            var data = new WindowCompositionAttributeData
            {
                Attribute = WindowCompositionAttributeAccentPolicy,
                Data = pointer,
                SizeOfData = size
            };
            return NativeMethods.SetWindowCompositionAttribute(handle, ref data) != 0;
        }
        catch (Exception exception) when (exception is DllNotFoundException or EntryPointNotFoundException or MarshalDirectiveException)
        {
            return false;
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
        }
    }

    private static int ToAbgr(string value, double opacity, bool acrylic)
    {
        Color color;
        try
        {
            color = (Color)ColorConverter.ConvertFromString(value);
        }
        catch (FormatException)
        {
            color = Color.FromRgb(247, 248, 250);
        }
        var level = Math.Clamp(opacity, 0, 1);
        var alpha = acrylic
            ? (byte)Math.Round(32 + 80 * level)
            : (byte)Math.Round(1 + 47 * level);
        return unchecked((int)((uint)alpha << 24 | (uint)color.B << 16 | (uint)color.G << 8 | color.R));
    }
}
