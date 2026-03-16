param(
    [switch] $PreferPS5,
    [switch] $CreateShortcut
)

$GamePathFile = "${PSScriptRoot}\.gamepath"
$WindowTitle = "Overwatch Server Blocker"

# Relaunch check
$ShellExecutable = & {
    if ($PreferPS5) {
        (Get-Command -Name "powershell.exe").Source
    }
    elseif ($PSVersionTable.PSVersion.Major -lt 7 -and (Get-Command -Name "pwsh.exe")) {
        (Get-Command -Name "pwsh.exe").Source
    }
}
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or $ShellExecutable) {
    if (-not $ShellExecutable) {
        $ShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    }
    $boundParams = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process {
        "-$($_.Key)", "'$([System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($_.Value))'"
    }
    $argList = @("-ExecutionPolicy", "Unrestricted", "-File", "`"$PSCommandPath`"") + $boundParams
    Start-Process -FilePath "$ShellExecutable" `
            -ArgumentList $argList `
            -Verb RunAs
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Enable high DPI awareness on PowerShell 7+
# The reason for applying this to PowerShell 7+ only but not 5 is PowerShell 5 DOES NOT support automatic HiDPI scaling. The form will be set to 96 DPI and looks really small on HiDPI displays with PowerShell 5.
# To prevent this, enable HiDPI support only when the script is executed with PowerShell 7+.
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class ProcessDPI {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetProcessDPIAware();
}
'@
    [ProcessDPI]::SetProcessDPIAware() | Out-Null
}
[System.Windows.Forms.Application]::EnableVisualStyles()

# Handle Create Shortcut logic
if ($CreateShortcut) {
    $saveFileDialog = [System.Windows.Forms.SaveFileDialog] @{
        Title = "Select a location to save the shortcut" # Sets the dialog box title
        OverwritePrompt = $true # Asks for confirmation if the file already exists
        InitialDirectory = "${Env:USERPROFILE}\Desktop"
        FileName = "$WindowTitle.lnk"
        Filter = "Shortcut (*.lnk)|*.lnk" # Sets file type filters
    }

    # Show the dialog and capture the result
    $result = $saveFileDialog.ShowDialog()

    # Process the user's choice
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $filePath = $saveFileDialog.FileName

        if (Test-Path -Path $filePath -PathType Leaf) { Remove-Item -Path $filePath }

        $ShortcutFile = (New-Object -COM WScript.Shell).CreateShortcut($filePath)
        $ShortcutFile.TargetPath = "powershell.exe"
        $ShortcutFile.Arguments = "-ExecutionPolicy Unrestricted -File `"${PSScriptRoot}\OWServerBlocker.ps1`""
        $ShortcutFile.Save()

        # Modify the binary data to enable "Run as administrator"
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $bytes[0x15] = $bytes[0x15] -bor 0x20 
        [System.IO.File]::WriteAllBytes($filePath, $bytes)

        [System.Windows.Forms.MessageBox]::Show(
            "Shortcut created successfully! You can use this shortcut to launch the blocker directly without going through the file selection and admin prompt steps.`n`nNote: The shortcut is set to run as administrator by default, so you will still see the UAC prompt when launching it.",
            "Shortcut Created",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "No file was selected. The shortcut creation has been cancelled.",
            "Operation Cancelled",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    return
}

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
    [System.Windows.Forms.MessageBox]::Show(
        "You've selected an invalid Overwatch.exe path. Please remove `"${GamePathFile}`" and select the correct executable file.",
        "Invalid game path",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
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
        [System.Windows.Forms.MessageBox]::Show(
            "To remove the stale rules, go to [Outbound Rules] > Select all the stale rules > [Delete].",
            "Remove stale firewall rules"
        ) | Out-Null
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
    [System.Windows.Forms.MessageBox]::Show(
        "Make sure `"${PSScriptRoot}\IPList.json`" exists and the system is connected to Internet.",
        "Failed to load IP list",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    return
}

# Create the Form
$form = [System.Windows.Forms.Form] @{
    Text = $WindowTitle
    AutoSize = $true
    AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    MaximizeBox = $false
    StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
}
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
$panel = [System.Windows.Forms.FlowLayoutPanel] @{
    AutoSize = $true
    FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
}
$form.Controls.Add($panel)

# Add description Label
$panel.Controls.Add([System.Windows.Forms.Label] @{
    Text = "Select the server(s) you want to block:"
    AutoSize = $true
})

# Add "Select All" CheckBox
$selectAll = [System.Windows.Forms.CheckBox] @{
    Text = "Select All"
    AutoSize = $true
}
$panel.Controls.Add($selectAll)

# Add CheckedListBox
$clb = [System.Windows.Forms.CheckedListBox] @{
    Width = 250 * ($form.DeviceDpi / 96)
    Height = 200 * ($form.DeviceDpi / 96)
    DataSource = $ServerList
    DisplayMember = "FriendlyName"
    ValueMember = "Name"
    Sorted = $true
    CheckOnClick = $true
}
$panel.Controls.Add($clb)

# Logic: Select All toggle
$selectAll.Add_CheckedChanged({
    for ($i = 0; $i -lt $clb.Items.Count; $i++) {
        $clb.SetItemChecked($i, $selectAll.Checked)
    }
})

# Button Container (Horizontal layout for buttons)
$buttonPanel = [System.Windows.Forms.FlowLayoutPanel] @{
    AutoSize = $true
    Anchor = [System.Windows.Forms.AnchorStyles]::Right
}
$panel.Controls.Add($buttonPanel)

# Block Button
$blockButton = [System.Windows.Forms.Button] @{
    Text = "Block"
    Width = 100 * ($form.DeviceDpi / 96)
    Height = 30 * ($form.DeviceDpi / 96)
}
$buttonPanel.Controls.Add($blockButton)

# Unblock Button
$unblockButton = [System.Windows.Forms.Button] @{
    Text = "Unblock"
    Width = 100 * ($form.DeviceDpi / 96)
    Height = 30 * ($form.DeviceDpi / 96)
    Enabled = $false
}
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
            [System.Windows.Forms.MessageBox]::Show("Failed to create the firewall rules for the following regions: $($failedItems -join '')", "$FormTitle", "OK", "Error") | Out-Null
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Successfully blocked $($BlockedRules.Count) server(s).") | Out-Null
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
        [System.Windows.Forms.MessageBox]::Show("Successfully removed all blocking rule(s).") | Out-Null

        $selectAll.Enabled = $true
        $clb.Enabled = $true
        $blockButton.Enabled = $true
    }
})

# Show the Form
[System.Windows.Forms.Application]::Run($form)
