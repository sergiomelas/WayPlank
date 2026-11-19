#
#  Copyright (C) 2026 Sergio Melas
#
#  This file is part of WayPlank (GPLv3).
#  Windows FAT Tester: Fullscreen window toggle (press F11 or Space to toggle fullscreen, Esc to quit).
#
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "WayPlank Fullscreen Tester (Windows)"
$form.Size = New-Object System.Drawing.Size(720, 420)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 30, 42)
$form.KeyPreview = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = "Press F11 or SPACE to toggle Fullscreen`r`nPress ESC to exit`r`nVerify WayPlank FullscreenInhibit & ABN_FULLSCREENAPP."
$label.ForeColor = [System.Drawing.Color]::White
$label.Font = New-Object System.Drawing.Font("Segoe UI", 14)
$label.Dock = "Fill"
$label.TextAlign = "MiddleCenter"
$form.Controls.Add($label)

$script:isFull = $false
$form.Add_KeyDown({
    if ($_.KeyCode -eq "Escape") {
        $form.Close()
    } elseif ($_.KeyCode -eq "F11" -or $_.KeyCode -eq "Space") {
        $script:isFull = -not $script:isFull
        if ($script:isFull) {
            $form.FormBorderStyle = "None"
            $form.WindowState = "Maximized"
            $form.TopMost = $true
        } else {
            $form.TopMost = $false
            $form.FormBorderStyle = "Sizable"
            $form.WindowState = "Normal"
        }
    }
})

[void]$form.ShowDialog()
