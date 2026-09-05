param([Parameter(Mandatory = $true)][int]$ProcessId, [switch]$ExpectUnclipped)
# Native geometry only: Accent/DWM pixels may still spill outside the region.
# Glass visual correctness needs a separate desktop-composition pixel check.
$ErrorActionPreference = 'Stop'
if (-not ('HudRegionProbe' -as [type])) {
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class HudRegionProbe {
    public delegate bool Callback(IntPtr h, IntPtr p);
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool EnumWindows(Callback cb, IntPtr p);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder text, int length);
    [DllImport("user32.dll")] static extern int GetWindowRgn(IntPtr h, IntPtr r);
    [DllImport("gdi32.dll")] static extern IntPtr CreateRectRgn(int l, int t, int r, int b);
    [DllImport("gdi32.dll")] static extern int GetRgnBox(IntPtr r, out Rect box);
    [DllImport("gdi32.dll")] static extern bool PtInRegion(IntPtr r, int x, int y);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr r);
    public static int Verify(int target, bool unclipped) {
        var windows = new List<IntPtr>();
        EnumWindows((h,p) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            var title = new StringBuilder(256); GetWindowText(h,title,256);
            var name = title.ToString();
            if(pid == target && IsWindowVisible(h) && (name == "Codex Monitor HUD" || name == "Codex Monitor HUD Task")) windows.Add(h);
            return true;
        }, IntPtr.Zero);
        if(windows.Count == 0) throw new Exception("No visible HUD surfaces found.");
        foreach(var h in windows) {
            var r = CreateRectRgn(0,0,0,0);
            try {
                int kind = GetWindowRgn(h,r);
                if(unclipped) { if(kind != 0) throw new Exception("Glass-off surface retained native clipping."); continue; }
                if(kind != 3) throw new Exception("HUD region is missing or rectangular.");
                Rect box; GetRgnBox(r,out box);
                if(box.Left <= 0 || box.Top <= 0) throw new Exception("Glass still includes the transparent outer margin.");
                int cx=(box.Left+box.Right)/2, cy=(box.Top+box.Bottom)/2;
                if(!PtInRegion(r,cx,cy) || !PtInRegion(r,cx,box.Top+1)) throw new Exception("HUD content was clipped.");
                if(PtInRegion(r,box.Left,box.Top) || PtInRegion(r,box.Right-1,box.Top) ||
                   PtInRegion(r,box.Left,box.Bottom-1) || PtInRegion(r,box.Right-1,box.Bottom-1))
                    throw new Exception("Glass corners are not rounded.");
            } finally { DeleteObject(r); }
        }
        return windows.Count;
    }
}
'@
}
$count = [HudRegionProbe]::Verify($ProcessId, [bool]$ExpectUnclipped)
Write-Output "Native HUD region: OK ($count surfaces; glass off=$ExpectUnclipped)"
