Add-Type -AssemblyName System.Windows.Forms
$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog

# Optional: Set properties for the dialog box
$saveFileDialog.Filter = "Shortcut (*.lnk)|*.lnk" # Sets file type filters
$saveFileDialog.Title = "Select a location to save the shortcut" # Sets the dialog box title
$saveFileDialog.OverwritePrompt = $true # Asks for confirmation if the file already exists
$saveFileDialog.InitialDirectory = "${Env:USERPROFILE}\Desktop"

# Show the dialog and capture the result
$result = $saveFileDialog.ShowDialog()

# Process the user's choice
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $filePath = $saveFileDialog.FileName
    Write-Host "File will be saved to: ${filePath}"

    if (Test-Path -Path $filePath -PathType Leaf) { Remove-Item -Path $filePath }

    $ShortcutFile = (New-Object -COM WScript.Shell).CreateShortcut($filePath)
    $ShortcutFile.TargetPath = "powershell.exe"
    $ShortcutFile.Arguments = "-ExecutionPolicy Unrestricted -File `"${PSScriptRoot}\OWServerBlocker.ps1`""
    $ShortcutFile.Save()

    # Modify the binary data to enable "Run as administrator"
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20 
    [System.IO.File]::WriteAllBytes($filePath, $bytes)
}
else {
    Write-Host "Save operation cancelled by user."
}

Read-Host -Prompt "Press ENTER to exit..."
