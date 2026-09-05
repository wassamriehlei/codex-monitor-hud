using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;

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

    // Track the native window shape, not just WPF pixels. Known limitation:
    // Accent composition can still paint outside this region on Windows;
    // a successful GetWindowRgn probe alone does not verify glass clipping.
    internal static void TrackShell(Window window, Border shell, Func<string> mode)
    {
        (int, int, int, int, int, int)? previous = null;
        void Update(object? sender, EventArgs args)
        {
            var handle = new WindowInteropHelper(window).Handle;
            if (handle == 0) return;
            if (!IsEnabled(mode()))
            {
                if (previous is not null && NativeMethods.SetWindowRgn(handle, 0, true) != 0) previous = null;
                return;
            }
            if (!shell.IsArrangeValid || shell.ActualWidth <= 0 || shell.ActualHeight <= 0) return;
            var dpi = VisualTreeHelper.GetDpi(window);
            var bounds = shell.TransformToAncestor(window).TransformBounds(new Rect(shell.RenderSize));
            var radius = Math.Min(shell.CornerRadius.TopLeft, Math.Min(bounds.Width, bounds.Height) / 2);
            var regionBounds = (
                (int)Math.Round(bounds.Left * dpi.DpiScaleX),
                (int)Math.Round(bounds.Top * dpi.DpiScaleY),
                (int)Math.Round(bounds.Right * dpi.DpiScaleX) + 1,
                (int)Math.Round(bounds.Bottom * dpi.DpiScaleY) + 1,
                (int)Math.Round(radius * 2 * dpi.DpiScaleX),
                (int)Math.Round(radius * 2 * dpi.DpiScaleY));
            if (previous == regionBounds) return;
            var region = NativeMethods.CreateRoundRectRgn(regionBounds.Item1, regionBounds.Item2,
                regionBounds.Item3, regionBounds.Item4, regionBounds.Item5, regionBounds.Item6);
            if (region == 0) return;
            // Windows owns the HRGN only after a successful SetWindowRgn.
            if (NativeMethods.SetWindowRgn(handle, region, true) != 0) previous = regionBounds;
            else NativeMethods.DeleteObject(region);
        }
        window.LayoutUpdated += Update;
        window.SourceInitialized += Update;
        window.Closed += (_, _) =>
        {
            window.LayoutUpdated -= Update;
            window.SourceInitialized -= Update;
        };
    }

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
