#
#  Copyright (C) 2026 Sergio Melas
#
#  This file is part of WayPlank (GPLv3).
#  Windows FAT Tester: Sends a native Windows notification balloon/toast to test DND / Focus Assist.
#
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
$notify.BalloonTipTitle = "WayPlank FAT Notification Test"
$notify.BalloonTipText = "Verify Windows Focus Assist / Do Not Disturb docklet behavior."
$notify.Visible = $true
$notify.ShowBalloonTip(5000)

Start-Sleep -Seconds 6
$notify.Visible = $false
$notify.Dispose()
