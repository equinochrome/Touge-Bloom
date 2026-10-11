# Saves screenshots of the Roblox Studio window as PNG files, e.g. for Design/Visual Review.md.
# It captures the window through PrintWindow, so other windows on top don't matter.
# Studio must not be minimized.
#
# Example: during Play, press P (photo-mode tour), then run:
#   powershell -ExecutionPolicy Bypass -File tools/capture-studio.ps1 -Prefix 2026-10-10-slice-r1 -Count 12 -IntervalSeconds 2
param(
    [string]$OutDir = "Design/References/Attachments",
    [string]$Prefix = "studio-capture",
    [int]$Count = 1,
    [double]$IntervalSeconds = 2
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class StudioCapture {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
}
"@
[StudioCapture]::SetProcessDPIAware() | Out-Null

$studio = Get-Process -Name RobloxStudioBeta -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1
if ($null -eq $studio) {
    Write-Error "Roblox Studio window not found."
    exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
for ($i = 1; $i -le $Count; $i++) {
    $rect = New-Object StudioCapture+RECT
    [StudioCapture]::GetWindowRect($studio.MainWindowHandle, [ref]$rect) | Out-Null
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    # 2 = PW_RENDERFULLCONTENT, needed for GPU-rendered windows.
    [StudioCapture]::PrintWindow($studio.MainWindowHandle, $hdc, 2) | Out-Null
    $graphics.ReleaseHdc($hdc)
    $path = Join-Path $OutDir ("{0}-{1:D2}.png" -f $Prefix, $i)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-Output $path
    if ($i -lt $Count) { Start-Sleep -Milliseconds ([int]($IntervalSeconds * 1000)) }
}
