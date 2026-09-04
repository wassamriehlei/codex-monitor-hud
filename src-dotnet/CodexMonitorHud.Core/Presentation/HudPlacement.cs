namespace CodexMonitorHud.Core.Presentation;

public readonly record struct HudPoint(double Left, double Top);

public static class HudPlacement
{
    public static HudPoint GetPreset(
        string position,
        double screenLeft,
        double screenTop,
        double screenWidth,
        double screenHeight,
        double windowWidth,
        double windowHeight,
        double chromeInset)
    {
        var minLeft = screenLeft - chromeInset;
        var minTop = screenTop - chromeInset;
        var maxLeft = screenLeft + screenWidth - windowWidth + chromeInset;
        var maxTop = screenTop + screenHeight - windowHeight + chromeInset;
        var centerLeft = screenLeft + (screenWidth - windowWidth) / 2;

        return position switch
        {
            "top-left" => new HudPoint(minLeft, minTop),
            "top-center" => new HudPoint(centerLeft, minTop),
            "bottom-left" => new HudPoint(minLeft, maxTop),
            "bottom-center" => new HudPoint(centerLeft, maxTop),
            "bottom-right" => new HudPoint(maxLeft, maxTop),
            _ => new HudPoint(maxLeft, minTop)
        };
    }

    public static HudPoint ClampCustom(
        double left,
        double top,
        double screenLeft,
        double screenTop,
        double screenWidth,
        double screenHeight,
        double windowWidth,
        double windowHeight,
        double chromeInset)
    {
        var minLeft = screenLeft - chromeInset;
        var minTop = screenTop - chromeInset;
        var maxLeft = Math.Max(minLeft, screenLeft + screenWidth - windowWidth + chromeInset);
        var maxTop = Math.Max(minTop, screenTop + screenHeight - windowHeight + chromeInset);
        return new HudPoint(
            Math.Clamp(left, minLeft, maxLeft),
            Math.Clamp(top, minTop, maxTop));
    }

    public static HudPoint SnapCustom(
        double left,
        double top,
        double screenLeft,
        double screenTop,
        double screenWidth,
        double screenHeight,
        double windowWidth,
        double windowHeight,
        double chromeInset,
        double distance)
    {
        var clamped = ClampCustom(
            left,
            top,
            screenLeft,
            screenTop,
            screenWidth,
            screenHeight,
            windowWidth,
            windowHeight,
            chromeInset);
        var threshold = Math.Max(0, distance);
        var minLeft = screenLeft - chromeInset;
        var minTop = screenTop - chromeInset;
        var maxLeft = Math.Max(minLeft, screenLeft + screenWidth - windowWidth + chromeInset);
        var maxTop = Math.Max(minTop, screenTop + screenHeight - windowHeight + chromeInset);
        var snappedLeft = Math.Abs(clamped.Left - minLeft) <= threshold
            ? minLeft
            : Math.Abs(clamped.Left - maxLeft) <= threshold
                ? maxLeft
                : clamped.Left;
        var snappedTop = Math.Abs(clamped.Top - minTop) <= threshold
            ? minTop
            : Math.Abs(clamped.Top - maxTop) <= threshold
                ? maxTop
                : clamped.Top;
        return new HudPoint(snappedLeft, snappedTop);
    }

}
