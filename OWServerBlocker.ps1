$GamePathFile = "${PSScriptRoot}\.gamepath"
$WindowTitle = "Overwatch Server Blocker"

# Check for Admin rights and relaunch with 'RunAs' if needed
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-File", "`"$PSCommandPath`"") -Verb RunAs
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Check if .game_path exists
if (Test-Path -PathType Leaf -Path "$GamePathFile") {
    $GamePath = Get-Content -Path "$GamePathFile"
}
else {
    # Show an OpenFile dialog
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.InitialDirectory = $initialDirectory
    $openFileDialog.Filter = "Overwatch executable (*.exe)|*.exe"
    $openFileDialog.Title = "Select the path of Overwatch.exe"
    $result = $openFileDialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $GamePath = $openFileDialog.FileName
        $GamePath | Out-File -FilePath "$GamePathFile"
    }
    $openFileDialog.Dispose()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return }
}

# Check if .gamepath's content is a valid path
if (-not (Test-Path -PathType Leaf -Path "$GamePath")) {
    [void] [System.Windows.Forms.MessageBox]::Show(
        "You've selected an invalid Overwatch.exe path. Please remove `"${GamePathFile}`" and select the correct executable file.",
        "Invalid game path",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return
}

# Cleanup check: Ensure no stale firewall rules remain
if (Get-NetFirewallRule | Where-Object -Property "DisplayName" -Like -Value "$WindowTitle (*)") {
    $staleRulesList = (Get-NetFirewallRule | Where-Object -Property "DisplayName" -Like -Value "$WindowTitle (*)").DisplayName -join "`n - "
    if ([System.Windows.Forms.MessageBox]::Show(
        "It seems that some of the firewall rules are left from the last session (most likely due to an unexpected or force close). Do you want to open the settings and remove the rules?`n`nThese are the detected firewall rules:`n - ${staleRulesList}",
        "Stale firewall rules detected",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    ) -eq [System.Windows.Forms.DialogResult]::Yes) {
        & "wf.msc"
        [void] [System.Windows.Forms.MessageBox]::Show(
            "To remove the stale rules, go to [Outbound Rules] > Select all the stale rules > [Delete].",
            "Remove stale firewall rules"
        )
    }
}

# Load the server list
class ServerItem {
    [string] $Name
    [string] $FriendlyName
    [bool] $PeeringOnly
    [string] $GCPScope
    [string[]] $CIDR
}

$GCPIPRanges = (Invoke-RestMethod -Uri "https://www.gstatic.com/ipranges/cloud.json").prefixes
$ServerList = [System.Collections.Generic.List[ServerItem]] @()
(Get-Content -Raw -Path "${PSScriptRoot}\IPList.json" | ConvertFrom-Json) | ForEach-Object -Process {
    if ($_.gcp_scope) {
        $cidr = $GCPIPRanges | Where-Object -Property "scope" -EQ -Value "$($_.gcp_scope)" | ForEach-Object -Process {
            if ($_.ipv4Prefix) { $_.ipv4Prefix }
            else { $_.ipv6Prefix }
        }
    }
    else { $cidr = $_.cidr }
    $ServerList.Add([ServerItem] @{
        Name = $_.name
        FriendlyName = $_.friendly_name
        PeeringOnly = $_.peering_only
        GCPScope = $_.gcp_scope
        CIDR = $cidr
    })
}
if (-not $?) {
    [void] [System.Windows.Forms.MessageBox]::Show(
        "Make sure `"${PSScriptRoot}\IPList.json`" exists and the system is connected to Internet.",
        "Failed to load IP list",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return
}

# Create the Form
$form = New-Object System.Windows.Forms.Form
$form.Text = $WindowTitle
$form.AutoSize = $true
$form.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.Add_FormClosing({
    param($evSender, $e)

    if ($BlockedRules) {
        if ([System.Windows.Forms.MessageBox]::Show(
            "Some firewall rules are not removed from your system yet. If you close this window now, you will have to remove them manually.`nIt is STRONGLY NOT RECOMMENDED to do this!`n`nAre you sure you want to exit anyway?",
            "Some blocking rules are not removed yet",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) -ne [System.Windows.Forms.DialogResult]::Yes) {
            $e.Cancel = $true
        }
    }
})

# Create a Flow Layout Panel to handle positioning automatically
$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.AutoSize = $true
$panel.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$form.Controls.Add($panel)

# Add description Label
$descriptionText = New-Object System.Windows.Forms.Label
$descriptionText.Text = "Select the server(s) you want to block:"
$descriptionText.AutoSize = $true
$panel.Controls.Add($descriptionText)

# Add "Select All" CheckBox
$selectAll = New-Object System.Windows.Forms.CheckBox
$selectAll.Text = "Select All"
$selectAll.AutoSize = $true
$panel.Controls.Add($selectAll)

# Add CheckedListBox
$clb = New-Object System.Windows.Forms.CheckedListBox
$clb.CheckOnClick = $true
$clb.Width = 250
$clb.Height = 200
$clb.DataSource = $ServerList
$clb.DisplayMember = "FriendlyName"
$clb.ValueMember = "Name"
$clb.Sorted = $true
$panel.Controls.Add($clb)

# Logic: Select All toggle
$selectAll.Add_CheckedChanged({
    for ($i = 0; $i -lt $clb.Items.Count; $i++) {
        $clb.SetItemChecked($i, $selectAll.Checked)
    }
})

# Button Container (Horizontal layout for buttons)
$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.AutoSize = $true
$buttonPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Right
$panel.Controls.Add($buttonPanel)

# Block Button
$blockButton = New-Object System.Windows.Forms.Button
$blockButton.Text = "Block"
$buttonPanel.Controls.Add($blockButton)

# Unblock Button
$unblockButton = New-Object System.Windows.Forms.Button
$unblockButton.Text = "Unblock"
$unblockButton.Enabled = $false
$buttonPanel.Controls.Add($unblockButton)

# Buttons logic
$BlockedRules = [System.Collections.Generic.List[System.Object]] @()
$blockButton.Add_Click({
    if ($clb.CheckedItems.Count -ne 0) {
        $blockButton.Enabled = $false

        $failedItems = [System.Collections.Generic.List[string]]::new()
        $ServerList | ForEach-Object -Process {
            if (($clb.CheckedItems | Select-Object -Property "Name").Name -contains $_.name) {
                $blockedRule = New-NetFirewallRule -DisplayName "$WindowTitle ($($_.name))" -Program "$GamePath" -Direction Outbound -Action Block -RemoteAddress $_.CIDR
                if ($?) { [void] $BlockedRules.Add($blockedRule) }
                else { [void] $failedItems.Add($_) }
            }
        }
        if ($failedItems) {
            [void] [System.Windows.Forms.MessageBox]::Show("Failed to create the firewall rules for the following regions: $($failedItems -join '')", "$FormTitle", "OK", "Error")
        }
        else {
            [void] [System.Windows.Forms.MessageBox]::Show("Successfully blocked $($BlockedRules.Count) server(s).")
        }

        $selectAll.Enabled = $false
        $clb.Enabled = $false
        $unblockButton.Enabled = $true
    }
})
$unblockButton.Add_Click({
    $unblockButton.Enabled = $false

    $succeededItems = [System.Collections.Generic.List[object]]::new()
    $BlockedRules | ForEach-Object -Process {
        $_ | Remove-NetFirewallRule
        if ($?) { $succeededItems.Add($_) }
    }
    $succeededItems | ForEach-Object -Process { $BlockedRules.Remove($_) }
    if ($BlockedRules) {
        $unblockButton.Enabled = $true
    }
    else {
        [void] [System.Windows.Forms.MessageBox]::Show("Successfully removed all blocking rule(s).")

        $selectAll.Enabled = $true
        $clb.Enabled = $true
        $blockButton.Enabled = $true
    }
})

# Show the Form
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen;
$form.ShowDialog()
