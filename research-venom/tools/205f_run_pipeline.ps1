[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [string]$ConfigPath = "",
    [string]$ReportJson = "",
    [string]$ReportMd = "",
    [int]$StepTimeoutSec = 600,
    [switch]$CleanupOfficeOrphans,
    [switch]$SkipWord,
    [switch]$SkipBookmarkInsert,
    [switch]$ContinueOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DefaultRepoRoot {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { "" }
    if (-not $scriptPath) { throw "Cannot resolve script path for Get-DefaultRepoRoot" }
    $toolsDir = Split-Path -Parent $scriptPath
    $repoCandidate = Join-Path $toolsDir "..\..\..\.."
    $resolved = Resolve-Path -LiteralPath $repoCandidate -ErrorAction Stop
    if ($resolved -is [array]) { $resolved = $resolved[0] }
    if ($resolved.PSObject.Properties.Name -contains "ProviderPath") { return [string]$resolved.ProviderPath }
    if ($resolved.PSObject.Properties.Name -contains "Path") { return [string]$resolved.Path }
    return [string]$resolved
}

function Resolve-ConfigPathValue {
    param(
        [string]$RepoRootValue,
        [string]$PathValue
    )
    if (-not $PathValue) { return "" }
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $RepoRootValue $PathValue)
}

function Get-JsonProp {
    param(
        [object]$Obj,
        [string]$Name
    )
    if ($null -eq $Obj) { return $null }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $null
}

if (-not $RepoRoot) { $RepoRoot = Get-DefaultRepoRoot }
$artifacts = Join-Path $RepoRoot "docs_dev\_to_do\205_artifacts"

if (-not $ConfigPath) { $ConfigPath = Join-Path $artifacts "config\205f_pipeline_config_v01.json" }
$cfg = $null
if (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$cfgRuntime = Get-JsonProp -Obj $cfg -Name "runtime"
$cfgPaths = Get-JsonProp -Obj $cfg -Name "paths"

if ($cfgRuntime -and -not $PSBoundParameters.ContainsKey("StepTimeoutSec")) {
    $cfgTimeout = Get-JsonProp -Obj $cfgRuntime -Name "step_timeout_sec"
    if ($cfgTimeout) { $StepTimeoutSec = [int]$cfgTimeout }
}
if ($cfgRuntime -and -not $PSBoundParameters.ContainsKey("CleanupOfficeOrphans")) {
    if ((Get-JsonProp -Obj $cfgRuntime -Name "cleanup_office_orphans") -eq $true) { $CleanupOfficeOrphans = $true }
}
if ($cfgRuntime -and -not $PSBoundParameters.ContainsKey("SkipBookmarkInsert")) {
    if ((Get-JsonProp -Obj $cfgRuntime -Name "skip_bookmark_insert") -eq $true) { $SkipBookmarkInsert = $true }
}

if (-not $ReportJson) {
    $cfgReportJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "pipeline_report_json")
    if ($cfgReportJson) { $ReportJson = $cfgReportJson } else { $ReportJson = Join-Path $artifacts "205F\analysis\205F_pipeline_run_v01.json" }
}
if (-not $ReportMd) {
    $cfgReportMd = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "pipeline_report_md")
    if ($cfgReportMd) { $ReportMd = $cfgReportMd } else { $ReportMd = Join-Path $artifacts "205F\analysis\205F_pipeline_run_v01.md" }
}

$tools = Join-Path $artifacts "tools"
$cfgWorkbook = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "excel_workbook")
$cfgWordMapCsv = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "word_map_csv")
$cfgWordInputDocx = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "word_input_docx")
$cfgWordOutputDocx = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "word_output_docx")
$cfgEmbedRunJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "embed_run_json")
$cfgEmbedRunMd = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "embed_run_md")
$cfgEmbedVerifyJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "embed_verify_json")
$cfgEmbedVerifyMd = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue (Get-JsonProp -Obj $cfgPaths -Name "embed_verify_md")

$s06Args = @()
if ($cfgWordInputDocx) { $s06Args += @("-WordInputDocx", $cfgWordInputDocx) }
if ($cfgWordOutputDocx) { $s06Args += @("-WordOutputDocx", $cfgWordOutputDocx) }
if ($cfgWordMapCsv) { $s06Args += @("-WordMapCsv", $cfgWordMapCsv) }

$s07Args = @()
if ($cfgWorkbook) { $s07Args += @("-WorkbookPath", $cfgWorkbook) }
if ($cfgWordInputDocx) { $s07Args += @("-WordInputDocx", $cfgWordInputDocx) }
if ($cfgWordOutputDocx) { $s07Args += @("-WordOutputDocx", $cfgWordOutputDocx) }
if ($cfgWordMapCsv) { $s07Args += @("-WordMapCsv", $cfgWordMapCsv) }
if ($cfgEmbedRunJson) { $s07Args += @("-OutRunJson", $cfgEmbedRunJson) }
if ($cfgEmbedRunMd) { $s07Args += @("-OutRunMd", $cfgEmbedRunMd) }

$s09Args = @()
if ($cfgWordOutputDocx) { $s09Args += @("-WordDocx", $cfgWordOutputDocx) }
if ($cfgWordMapCsv) { $s09Args += @("-WordMapCsv", $cfgWordMapCsv) }
if ($cfgEmbedRunJson) { $s09Args += @("-S07RunJson", $cfgEmbedRunJson) }
if ($cfgEmbedVerifyJson) { $s09Args += @("-OutJson", $cfgEmbedVerifyJson) }
if ($cfgEmbedVerifyMd) { $s09Args += @("-OutMd", $cfgEmbedVerifyMd) }

$steps = @(
    @{ id = "S01"; type = "python"; script = (Join-Path $tools "205f_prepare_sources.py"); args = @() }
    @{ id = "S02"; type = "python"; script = (Join-Path $tools "205f_build_summary_tables.py"); args = @() }
    @{ id = "S03"; type = "ps1"; script = (Join-Path $tools "205f_excel_build_workbook.ps1"); args = @() }
    @{ id = "S04"; type = "ps1"; script = (Join-Path $tools "205f_excel_add_charts.ps1"); args = @() }
    @{ id = "S05"; type = "ps1"; script = (Join-Path $tools "205f_excel_apply_advanced_patterns.ps1"); args = @() }
)

if (-not $SkipWord) {
    if (-not $SkipBookmarkInsert) {
        $steps += @{ id = "S06"; type = "ps1"; script = (Join-Path $tools "205f_word_insert_bookmarks.ps1"); args = $s06Args }
    }
    $steps += @{ id = "S07"; type = "ps1"; script = (Join-Path $tools "205f_word_embed_charts.ps1"); args = $s07Args }
    $steps += @{ id = "S09"; type = "ps1"; script = (Join-Path $tools "205f_verify_word_embeddings.ps1"); args = $s09Args }
}

$steps += @{ id = "S08"; type = "ps1"; script = (Join-Path $tools "205f_verify_excel_product.ps1"); args = @() }

function Get-OfficePidSet {
    $set = @{}
    $names = @("WINWORD", "EXCEL")
    foreach ($name in $names) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($p in @($procs)) { $set[[string]$p.Id] = $true }
    }
    return $set
}

function Stop-NewOfficeProcesses {
    param(
        [Parameter(Mandatory = $true)]$BeforeSet
    )
    $killed = @()
    $names = @("WINWORD", "EXCEL")
    foreach ($name in $names) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($p in @($procs)) {
            $pidKey = [string]$p.Id
            if (-not $BeforeSet.ContainsKey($pidKey)) {
                try {
                    Stop-Process -Id $p.Id -Force -ErrorAction Stop
                    $killed += "${name}:$($p.Id)"
                }
                catch {
                    Write-Host "[S10] Office cleanup warning: failed to stop $name pid=$($p.Id): $($_.Exception.Message)"
                }
            }
        }
    }
    return $killed
}

function Emit-ProcessLogs {
    param(
        [string]$StdOutPath,
        [string]$StdErrPath
    )
    if (Test-Path -LiteralPath $StdOutPath) {
        Get-Content -LiteralPath $StdOutPath -ErrorAction SilentlyContinue | ForEach-Object { if ($_ -ne "") { Write-Host $_ } }
    }
    if (Test-Path -LiteralPath $StdErrPath) {
        Get-Content -LiteralPath $StdErrPath -ErrorAction SilentlyContinue | ForEach-Object { if ($_ -ne "") { Write-Host $_ } }
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]$Step
    )
    $start = Get-Date
    $result = [ordered]@{
        step_id = $Step.id
        script = $Step.script
        status = "ok"
        started_at = $start.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        finished_at = ""
        duration_s = 0
        exit_code = 0
        error = ""
        timeout_s = $StepTimeoutSec
        orphan_office_killed = @()
    }

    $beforeOffice = Get-OfficePidSet
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $proc = $null

    try {
        $filePath = ""
        $argList = @()
        if ($Step.type -eq "python") {
            $filePath = "python"
            $argList = @($Step.script)
            if ($Step.args -and @($Step.args).Count -gt 0) { $argList += @($Step.args) }
        }
        elseif ($Step.type -eq "ps1") {
            $filePath = "powershell.exe"
            $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Step.script)
            if ($Step.args -and @($Step.args).Count -gt 0) { $argList += @($Step.args) }
        }
        else {
            throw "unsupported step type: $($Step.type)"
        }

        $proc = Start-Process -FilePath $filePath -ArgumentList $argList -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -WindowStyle Hidden
        $timedOut = $false
        try {
            Wait-Process -Id $proc.Id -Timeout $StepTimeoutSec -ErrorAction Stop
        }
        catch {
            $timedOut = $true
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        }

        Emit-ProcessLogs -StdOutPath $tmpOut -StdErrPath $tmpErr

        $proc.Refresh()
        $exitCode = if ($null -eq $proc.ExitCode) { 0 } else { [int]$proc.ExitCode }

        if ($timedOut) {
            throw "step timeout after ${StepTimeoutSec}s"
        }
        if ($exitCode -ne 0) {
            throw "process exit code: $exitCode"
        }
    }
    catch {
        $result.status = "failed"
        $result.exit_code = 1
        $result.error = $_.Exception.Message
        if (-not $ContinueOnError) {
            $end = Get-Date
            $result.finished_at = $end.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            $result.duration_s = [math]::Round(($end - $start).TotalSeconds, 3)
            return [pscustomobject]$result
        }
    }
    finally {
        if ($CleanupOfficeOrphans) {
            $killed = Stop-NewOfficeProcesses -BeforeSet $beforeOffice
            $result.orphan_office_killed = @($killed)
        }
        Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue
    }

    $end = Get-Date
    $result.finished_at = $end.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $result.duration_s = [math]::Round(($end - $start).TotalSeconds, 3)
    return [pscustomobject]$result
}

$runStart = Get-Date
$results = @()
$stopNow = $false

foreach ($step in $steps) {
    if ($stopNow) { break }
    Write-Host "[S10] Running $($step.id) -> $($step.script)"
    $stepResult = Invoke-Step -Step $step
    $results += $stepResult
    if ($stepResult.status -ne "ok" -and -not $ContinueOnError) {
        $stopNow = $true
    }
}

$runEnd = Get-Date
$failed = @($results | Where-Object { $_.status -ne "ok" })

$payload = [ordered]@{
    generated_at = $runEnd.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    repo_root = $RepoRoot
    config_path = $ConfigPath
    skip_word = [bool]$SkipWord
    skip_bookmark_insert = [bool]$SkipBookmarkInsert
    step_timeout_sec = $StepTimeoutSec
    cleanup_office_orphans = [bool]$CleanupOfficeOrphans
    continue_on_error = [bool]$ContinueOnError
    started_at = $runStart.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    finished_at = $runEnd.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    duration_s = [math]::Round(($runEnd - $runStart).TotalSeconds, 3)
    totals = @{
        steps = @($results).Count
        ok = @($results | Where-Object { $_.status -eq "ok" }).Count
        failed = $failed.Count
    }
    steps = $results
}

$reportDir = Split-Path -Parent $ReportJson
if (-not (Test-Path -LiteralPath $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportJson -Encoding UTF8

$md = @()
$md += "# 205F Pipeline Run v01"
$md += ""
$md += "- generated_at: $($payload.generated_at)"
$md += "- duration_s: $($payload.duration_s)"
$md += "- ok: $($payload.totals.ok) / $($payload.totals.steps)"
$md += ""
$md += "| step | status | duration_s | script |"
$md += "|---|---|---:|---|"
foreach ($row in $results) {
    $md += "| $($row.step_id) | $($row.status) | $($row.duration_s) | $($row.script) |"
}
if ($failed.Count -gt 0) {
    $md += ""
    $md += "## Failed"
    foreach ($f in $failed) {
        $md += "- $($f.step_id): $($f.error)"
    }
}
$md -join "`n" | Set-Content -LiteralPath $ReportMd -Encoding UTF8

Write-Host "[S10] Report JSON: $ReportJson"
Write-Host "[S10] Report MD:   $ReportMd"
if ($failed.Count -gt 0 -and -not $ContinueOnError) {
    exit 1
}
