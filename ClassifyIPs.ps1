param(
    [Parameter(Mandatory = $true)]
    [string] $IPListCsv
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7+"
    return
}

Get-Content -Raw -Path "$IPListCsv" | ConvertFrom-Csv -Header @("TargetIP") | ForEach-Object -ThrottleLimit 16 -Parallel {
    $ClosestTestPoint = (Test-Connection -Traceroute -MaxHops 30 -TimeoutSeconds 1 -TargetName "$($_.TargetIP)" | Where-Object -Property "Hostname" -NE -Value "0.0.0.0")[-1].Hostname
    $Latency = ((Test-Connection -Count 8 -TargetName "$ClosestTestPoint" | Where-Object -Property "Status" -EQ -Value "Success").Latency | Measure-Object -Average).Average
    [PSCustomObject]@{
        IPAddress = $_.TargetIP
        ClosestTestPoint = $ClosestTestPoint
        Latency = $Latency
    }
} | Sort-Object -Property "Latency"
