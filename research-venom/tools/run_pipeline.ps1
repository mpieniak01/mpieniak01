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
    $repoCandidate = Join-Path $toolsDir ".."
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

function New-PipelineLogPath {
    param(
        [string]$RepoRootValue,
        [string]$ConfigPathValue,
        [string]$ReportJsonValue
    )
    $logRoot = Join-Path $RepoRootValue "artifacts\log"
    if (-not (Test-Path -LiteralPath $logRoot)) {
        New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
    }
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $configStem = if ($ReportJsonValue) {
        [System.IO.Path]::GetFileNameWithoutExtension($ReportJsonValue)
    } elseif ($ConfigPathValue) {
        [System.IO.Path]::GetFileNameWithoutExtension($ConfigPathValue)
    } else {
        "pipeline"
    }
    $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    return (Join-Path $logRoot ("${configStem}_${stamp}_${suffix}.log"))
}

function Get-RunLabel {
    param([string]$ReportJsonValue)
    if ($ReportJsonValue) {
        return [System.IO.Path]::GetFileNameWithoutExtension($ReportJsonValue)
    }
    return "pipeline_run"
}

function Get-PipelineManifestPaths {
    param([string]$RepoRootValue)
    $logRoot = Join-Path $RepoRootValue "artifacts\log"
    if (-not (Test-Path -LiteralPath $logRoot)) {
        New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
    }
    return @{
        json = Join-Path $logRoot "manifest.json"
        md = Join-Path $logRoot "manifest.md"
    }
}

function Write-PipelineLog {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Add-Content -LiteralPath $Path -Value "$ts $Message" -Encoding UTF8
}

function Get-StepSummaryLines {
    param([string]$StdOutPath)
    $lines = @()
    if (-not (Test-Path -LiteralPath $StdOutPath)) { return $lines }
    $patterns = @(
        '^\[S01\] Row counts: ',
        '^\[S01\] Duplicate key counts: ',
        '^\[S02\] Chart source checks: ',
        '^\[S02\] Chart series checks: ',
        '^\[S07\] embedded=',
        '^\[S08\] Charts OK: ',
        '^\[S09\] final_status='
    )
    foreach ($line in @(Get-Content -LiteralPath $StdOutPath -ErrorAction SilentlyContinue)) {
        foreach ($pattern in $patterns) {
            if ($line -match $pattern) {
                $lines += $line
                break
            }
        }
    }
    return $lines
}

function Update-PipelineManifest {
    param(
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$ManifestJsonPath,
        [Parameter(Mandatory = $true)][string]$ManifestMdPath
    )
    $existing = @{
        generated_at = ""
        entries = @()
    }
    if (Test-Path -LiteralPath $ManifestJsonPath) {
        try {
            $existing = Get-Content -LiteralPath $ManifestJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            $existing = @{
                generated_at = ""
                entries = @()
            }
        }
    }

    function Get-FieldValue {
        param($Item, [string]$Name, $Default = $null)
        if ($null -eq $Item) { return $Default }
        if ($Item.PSObject.Properties.Name -contains $Name) {
            return $Item.$Name
        }
        return $Default
    }

    $newEntry = [ordered]@{
        generated_at = $Payload.generated_at
        run_name = $Payload.run_name
        log_file = [System.IO.Path]::GetFileName($Payload.log_path)
        log_path = $Payload.log_path
        report_json = $Payload.report_json
        report_md = $Payload.report_md
        config_path = $Payload.config_path
        duration_s = $Payload.duration_s
        steps_total = $Payload.totals.steps
        steps_ok = $Payload.totals.ok
        steps_failed = $Payload.totals.failed
        skip_word = [bool]$Payload.skip_word
        skip_bookmark_insert = [bool]$Payload.skip_bookmark_insert
        cleanup_office_orphans = [bool]$Payload.cleanup_office_orphans
        status = $(if ($Payload.totals.failed -gt 0) { "failed" } else { "ok" })
    }

    $entries = @()
    if ($existing -and $existing.entries) {
        foreach ($entry in @($existing.entries)) {
            $entries += [ordered]@{
                generated_at = (Get-FieldValue -Item $entry -Name "generated_at")
                run_name = (Get-FieldValue -Item $entry -Name "run_name" -Default "pipeline_run")
                log_file = (Get-FieldValue -Item $entry -Name "log_file" -Default ([System.IO.Path]::GetFileName((Get-FieldValue -Item $entry -Name "log_path"))))
                log_path = (Get-FieldValue -Item $entry -Name "log_path")
                report_json = (Get-FieldValue -Item $entry -Name "report_json")
                report_md = (Get-FieldValue -Item $entry -Name "report_md")
                config_path = (Get-FieldValue -Item $entry -Name "config_path")
                duration_s = (Get-FieldValue -Item $entry -Name "duration_s" -Default 0)
                steps_total = (Get-FieldValue -Item $entry -Name "steps_total" -Default (Get-FieldValue -Item $entry -Name "steps" -Default 0))
                steps_ok = (Get-FieldValue -Item $entry -Name "steps_ok" -Default (Get-FieldValue -Item $entry -Name "ok" -Default 0))
                steps_failed = (Get-FieldValue -Item $entry -Name "steps_failed" -Default (Get-FieldValue -Item $entry -Name "failed" -Default 0))
                skip_word = [bool](Get-FieldValue -Item $entry -Name "skip_word" -Default $false)
                skip_bookmark_insert = [bool](Get-FieldValue -Item $entry -Name "skip_bookmark_insert" -Default $false)
                cleanup_office_orphans = [bool](Get-FieldValue -Item $entry -Name "cleanup_office_orphans" -Default $false)
                status = (Get-FieldValue -Item $entry -Name "status" -Default "ok")
            }
        }
    }
    $entries = @($newEntry) + @($entries | Where-Object { [string]$_.log_path -ne [string]$newEntry.log_path })
    if ($entries.Count -gt 50) { $entries = $entries[0..49] }

    $manifest = [ordered]@{
        generated_at = $Payload.generated_at
        root = "artifacts/log"
        entries = $entries
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestJsonPath -Encoding UTF8

    $md = @()
    $md += "# Pipeline Log Manifest"
    $md += ""
    $md += "- generated_at: $($Payload.generated_at)"
    $md += "- entries: $($entries.Count)"
    $md += ""
    $md += "| generated_at | run_name | status | steps | ok | failed | duration_s | log_file |"
    $md += "|---|---|---|---:|---:|---:|---:|---|"
    foreach ($entry in $entries) {
        $md += "| $($entry.generated_at) | $($entry.run_name) | $($entry.status) | $($entry.steps_total) | $($entry.steps_ok) | $($entry.steps_failed) | $($entry.duration_s) | $($entry.log_file) |"
    }
    $md -join "`n" | Set-Content -LiteralPath $ManifestMdPath -Encoding UTF8
}

if (-not $RepoRoot) { $RepoRoot = Get-DefaultRepoRoot }

if (-not $ConfigPath) { $ConfigPath = Join-Path $RepoRoot "config\process_pipeline_v01.json" }
$cfg = $null
if (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$cfgRoots = $cfg.roots
$cfgArtifactsRoot = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgRoots.artifacts_root
if (-not $cfgArtifactsRoot) { $cfgArtifactsRoot = Join-Path $RepoRoot "artifacts" }

$cfgRuntime = $cfg.runtime
$cfgPaths = $cfg.paths

if ($cfgRuntime -and -not $PSBoundParameters.ContainsKey("StepTimeoutSec")) {
    $cfgTimeout = $cfgRuntime.step_timeout_sec
    if ($cfgTimeout) { $StepTimeoutSec = [int]$cfgTimeout }
}
if ($cfgRuntime -and -not $PSBoundParameters.ContainsKey("CleanupOfficeOrphans")) {
    if ($cfgRuntime.cleanup_office_orphans -eq $true) { $CleanupOfficeOrphans = $true }
}
if ($cfgRuntime -and -not $PSBoundParameters.ContainsKey("SkipBookmarkInsert")) {
    if ($cfgRuntime.skip_bookmark_insert -eq $true) { $SkipBookmarkInsert = $true }
}

if (-not $ReportJson) {
    $cfgReportJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.pipeline_report_json
    if ($cfgReportJson) { $ReportJson = $cfgReportJson } else { $ReportJson = Join-Path $cfgArtifactsRoot "products_light\visualization\pipeline_run_v02.json" }
}
if (-not $ReportMd) {
    $cfgReportMd = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.pipeline_report_md
    if ($cfgReportMd) { $ReportMd = $cfgReportMd } else { $ReportMd = Join-Path $cfgArtifactsRoot "products_light\visualization\pipeline_run_v02.md" }
}
$RunLabel = Get-RunLabel -ReportJsonValue $ReportJson
$LogPath = New-PipelineLogPath -RepoRootValue $RepoRoot -ConfigPathValue $ConfigPath -ReportJsonValue $ReportJson
$ManifestPaths = Get-PipelineManifestPaths -RepoRootValue $RepoRoot

$tools = Join-Path $RepoRoot "tools"
$cfgSourcesPackJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.sources_pack_json
$cfgSummaryCsv = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.summary_csv
$cfgLayoutCsv = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.excel_layout_csv
$cfgWorkbookLayoutJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.workbook_layout_json
$cfgChartSpecJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.chart_spec_json
$cfgChartStyleProfileJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.chart_style_profile_json
$cfgChartControlProfileJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.chart_control_profile_json
$cfgPatternsDoc = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.patterns_doc_md
$cfgWorkbook = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.excel_workbook
$cfgExcelVerifyJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.excel_verify_json
$cfgExcelVerifyMd = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.excel_verify_md
$cfgWordMapCsv = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.word_map_csv
$cfgWordInputDocx = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.word_input_docx
$cfgWordOutputDocx = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.word_output_docx
$cfgEmbedRunJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.embed_run_json
$cfgEmbedRunMd = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.embed_run_md
$cfgEmbedVerifyJson = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.embed_verify_json
$cfgEmbedVerifyMd = Resolve-ConfigPathValue -RepoRootValue $RepoRoot -PathValue $cfgPaths.embed_verify_md

$s06Args = @()
if ($cfgWordInputDocx) { $s06Args += @("-WordInputDocx", $cfgWordInputDocx) }
if ($cfgWordOutputDocx) { $s06Args += @("-WordOutputDocx", $cfgWordOutputDocx) }
if ($cfgWordMapCsv) { $s06Args += @("-WordMapCsv", $cfgWordMapCsv) }

$s07Args = @()
if ($cfgWorkbook) { $s07Args += @("-WorkbookPath", $cfgWorkbook) }
if ($cfgWordOutputDocx) { $s07Args += @("-WordInputDocx", $cfgWordOutputDocx) }
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

$s03Args = @()
if ($cfgSourcesPackJson) { $s03Args += @("-SourcesPackJson", $cfgSourcesPackJson) }
if ($cfgSummaryCsv) { $s03Args += @("-SummaryCsv", $cfgSummaryCsv) }
if ($cfgLayoutCsv) { $s03Args += @("-LayoutCsv", $cfgLayoutCsv) }
if ($cfgWorkbookLayoutJson) { $s03Args += @("-LayoutSpecJson", $cfgWorkbookLayoutJson) }
if ($cfgChartStyleProfileJson) { $s03Args += @("-StyleProfileJson", $cfgChartStyleProfileJson) }
if ($cfgWorkbook) { $s03Args += @("-OutWorkbook", $cfgWorkbook) }

$s04Args = @()
if ($cfgWorkbook) { $s04Args += @("-WorkbookPath", $cfgWorkbook) }
if ($cfgChartSpecJson) { $s04Args += @("-ChartSpecJson", $cfgChartSpecJson) }
if ($cfgWorkbookLayoutJson) { $s04Args += @("-LayoutSpecJson", $cfgWorkbookLayoutJson) }
if ($cfgChartStyleProfileJson) { $s04Args += @("-StyleProfileJson", $cfgChartStyleProfileJson) }
if ($cfgChartControlProfileJson) { $s04Args += @("-ControlProfileJson", $cfgChartControlProfileJson) }

$s05Args = @()
if ($cfgWorkbook) { $s05Args += @("-WorkbookPath", $cfgWorkbook) }
if ($cfgChartSpecJson) { $s05Args += @("-ChartSpecJson", $cfgChartSpecJson) }
if ($cfgPatternsDoc) { $s05Args += @("-PatternsDoc", $cfgPatternsDoc) }

$s08Args = @()
if ($cfgWorkbook) { $s08Args += @("-WorkbookPath", $cfgWorkbook) }
if ($cfgChartSpecJson) { $s08Args += @("-ChartSpecJson", $cfgChartSpecJson) }
if ($cfgWorkbookLayoutJson) { $s08Args += @("-LayoutSpecJson", $cfgWorkbookLayoutJson) }
if ($cfgChartStyleProfileJson) { $s08Args += @("-StyleProfileJson", $cfgChartStyleProfileJson) }
if ($cfgChartControlProfileJson) { $s08Args += @("-ControlProfileJson", $cfgChartControlProfileJson) }
if ($cfgExcelVerifyJson) { $s08Args += @("-OutJson", $cfgExcelVerifyJson) }
if ($cfgExcelVerifyMd) { $s08Args += @("-OutMd", $cfgExcelVerifyMd) }

$s01Args = @("--config", $ConfigPath)
$s02Args = @("--config", $ConfigPath)
if ($cfgChartStyleProfileJson) { $s02Args += @("--style-profile-json", $cfgChartStyleProfileJson) }
if ($cfgChartControlProfileJson) { $s02Args += @("--control-profile-json", $cfgChartControlProfileJson) }

$s06aArgs = @()
if ($cfgWordInputDocx) { $s06aArgs += @("-WordOutputDocx", $cfgWordInputDocx) }
if ($cfgWordMapCsv) { $s06aArgs += @("-WordMapCsv", $cfgWordMapCsv) }

$steps = @()
if ($CleanupOfficeOrphans) {
    $steps += @{ id = "S00"; type = "ps1"; script = (Join-Path $tools "office_hygiene.ps1"); args = @("-Mode", "preflight") }
}

$steps += @(
    @{ id = "S01"; type = "python"; script = (Join-Path $tools "prepare_sources.py"); args = $s01Args }
    @{ id = "S02"; type = "python"; script = (Join-Path $tools "build_summary_tables.py"); args = $s02Args }
    @{ id = "S03"; type = "ps1"; script = (Join-Path $tools "excel_build_workbook.ps1"); args = $s03Args }
    @{ id = "S04"; type = "ps1"; script = (Join-Path $tools "excel_add_charts.ps1"); args = $s04Args }
    @{ id = "S05"; type = "ps1"; script = (Join-Path $tools "excel_apply_advanced_patterns.ps1"); args = $s05Args }
)

if (-not $SkipWord) {
    if (-not $SkipBookmarkInsert -and $cfgWordInputDocx -and $cfgWordMapCsv -and -not (Test-Path -LiteralPath $cfgWordInputDocx)) {
        $steps += @{ id = "S06A"; type = "ps1"; script = (Join-Path $tools "word_create_embed_canvas.ps1"); args = $s06aArgs }
    }
    if (-not $SkipBookmarkInsert) {
        $steps += @{ id = "S06"; type = "ps1"; script = (Join-Path $tools "word_insert_bookmarks.ps1"); args = $s06Args }
    }
    $steps += @{ id = "S07"; type = "ps1"; script = (Join-Path $tools "word_embed_charts.ps1"); args = $s07Args }
    $steps += @{ id = "S09"; type = "ps1"; script = (Join-Path $tools "verify_word_embeddings.ps1"); args = $s09Args }
}

$steps += @{ id = "S08"; type = "ps1"; script = (Join-Path $tools "verify_excel_product.ps1"); args = $s08Args }
if ($CleanupOfficeOrphans) {
    $steps += @{ id = "S10"; type = "ps1"; script = (Join-Path $tools "office_hygiene.ps1"); args = @("-Mode", "postflight") }
}

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
        summary_lines = @()
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
            try { [void]$proc.WaitForExit() } catch {}
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
        $result.summary_lines = @(Get-StepSummaryLines -StdOutPath $tmpOut)
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

Write-PipelineLog -Path $LogPath -Message "PIPELINE START repo_root=$RepoRoot config_path=$ConfigPath report_json=$ReportJson report_md=$ReportMd"

foreach ($step in $steps) {
    if ($stopNow) { break }
    Write-Host "[S10] Running $($step.id) -> $($step.script)"
    Write-PipelineLog -Path $LogPath -Message "STEP START id=$($step.id) type=$($step.type) script=$($step.script)"
    $stepResult = Invoke-Step -Step $step
    $results += $stepResult
    $summaryParts = @()
    if ($stepResult.orphan_office_killed -and @($stepResult.orphan_office_killed).Count -gt 0) {
        $summaryParts += "orphan_office_killed=$(@($stepResult.orphan_office_killed).Count)"
    }
    $summaryLines = @($stepResult.summary_lines)
    if ($summaryLines.Count -gt 0) {
        $summaryParts += ($summaryLines -join " || ")
    }
    $summaryText = if ($summaryParts.Count -gt 0) { " summary=`"$($summaryParts -join ' ; ')`"" } else { "" }
    Write-PipelineLog -Path $LogPath -Message "STEP END id=$($stepResult.step_id) status=$($stepResult.status) duration_s=$($stepResult.duration_s) exit_code=$($stepResult.exit_code)$summaryText"
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
    run_name = $RunLabel
    report_json = $ReportJson
    report_md = $ReportMd
    started_at = $runStart.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    finished_at = $runEnd.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    duration_s = [math]::Round(($runEnd - $runStart).TotalSeconds, 3)
    log_path = $LogPath
    totals = @{
        steps = @($results).Count
        ok = @($results | Where-Object { $_.status -eq "ok" }).Count
        failed = $failed.Count
    }
    steps = @(
        $results | ForEach-Object {
            [pscustomobject]@{
                step_id = $_.step_id
                script = $_.script
                status = $_.status
                started_at = $_.started_at
                finished_at = $_.finished_at
                duration_s = $_.duration_s
                exit_code = $_.exit_code
                error = $_.error
                timeout_s = $_.timeout_s
                orphan_office_killed = $_.orphan_office_killed
            }
        }
    )
}

$reportDir = Split-Path -Parent $ReportJson
if (-not (Test-Path -LiteralPath $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportJson -Encoding UTF8

$md = @()
$md += "# Research Model Pipeline Run $RunLabel"
$md += ""
$md += "- generated_at: $($payload.generated_at)"
$md += "- duration_s: $($payload.duration_s)"
$md += "- log_path: $LogPath"
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
Update-PipelineManifest -Payload $payload -ManifestJsonPath $ManifestPaths.json -ManifestMdPath $ManifestPaths.md

Write-Host "[S10] Report JSON: $ReportJson"
Write-Host "[S10] Report MD:   $ReportMd"
Write-Host "[S10] Log path:     $LogPath"
Write-Host "[S10] Manifest MD:  $($ManifestPaths.md)"
if ($failed.Count -gt 0 -and -not $ContinueOnError) {
    exit 1
}
