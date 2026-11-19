#
#  Copyright (C) 2026 Sergio Melas
#
#  This file is part of WayPlank (GPLv3).
#  Windows FAT Tester: Triggers Win32 FlashWindowEx (DemandsAttention / Urgency) after 3 seconds.
#
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Flash {
    [StructLayout(LayoutKind.Sequential)]
    public struct FLASHWINFO {
        public uint cbSize;
        public IntPtr hwnd;
        public uint dwFlags;
        public uint uCount;
        public uint dwTimeout;
    }
    [DllImport("user32.dll")]
    public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
    public static void Flash(IntPtr hwnd) {
        FLASHWINFO f = new FLASHWINFO();
        f.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
        f.hwnd = hwnd;
        f.dwFlags = 3 | 12; // FLASHW_ALL | FLASHW_TIMERNOFG
        f.uCount = 5;
        f.dwTimeout = 0;
        FlashWindowEx(ref f);
    }
}
"@

$form = New-Object System.Windows.Forms.Form
$form.Text = "WayPlank Urgency Tester (Windows)"
$form.Size = New-Object System.Drawing.Size(520, 260)
$form.StartPosition = "CenterScreen"

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Flash Urgency in 3s (Switch focus away!)"
$btn.Dock = "Fill"
$btn.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$btn.Add_Click({
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 3000
    $timer.Add_Tick({
        $timer.Stop()
        [Win32Flash]::Flash($form.Handle)
    })
    $timer.Start()
})
$form.Controls.Add($btn)
[void]$form.ShowDialog()
