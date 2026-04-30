[CmdletBinding()]
param(
    [ValidateSet("preflight","postflight")]
    [string]$Mode = "preflight"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-OfficeAutomationProcesses {
    $names = @("WINWORD.EXE", "EXCEL.EXE")
    $all = @()
    foreach ($name in $names) {
        try {
            $all += @(Get-CimInstance Win32_Process -Filter "Name='$name'" -ErrorAction Stop)
        } catch {
            continue
        }
    }

    return @(
        $all | Where-Object {
            $cmd = [string]$_.CommandLine
            $cmd -match '/Automation\s+-Embedding'
        }
    )
}

$procs = @(Get-OfficeAutomationProcesses)
$killed = @()

foreach ($p in $procs) {
    try {
        $procId = [int]([string]$p.ProcessId)
        if ($procId -le 0) { throw "Invalid process id: $($p.ProcessId)" }
        Stop-Process -Id $procId -Force -ErrorAction Stop
        $killed += "$($p.Name):$($p.ProcessId)"
    }
    catch {
        try {
            $pidFallback = [int]([string]$p.ProcessId)
            if ($pidFallback -gt 0) {
                & taskkill.exe /F /PID $pidFallback | Out-Null
                $killed += "$($p.Name):$($p.ProcessId)"
                continue
            }
        } catch {}
        Write-Host "[HYG] Failed to stop $($p.Name) pid=$($p.ProcessId): $($_.Exception.Message)"
    }
}

Write-Host "[HYG] mode=$Mode killed=$($killed.Count)"
foreach ($item in $killed) {
    Write-Host "[HYG] killed=$item"
}
