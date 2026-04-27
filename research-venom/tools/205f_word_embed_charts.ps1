[CmdletBinding()]
param(
    [string]$WorkbookPath = "",
    [string]$WordInputDocx = "",
    [string]$WordOutputDocx = "",
    [string]$WordMapCsv = "",
    [string]$StagingRoot = "C:\temp\205F_word_embed_staging",
    [int]$StepTimeoutSec = 180,
    [string]$OutRunJson = "",
    [string]$OutRunMd = "",
    [switch]$KeepStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { "" }
    if (-not $scriptPath) { throw "Cannot resolve script path for Get-RepoRoot" }
    $toolsDir = Split-Path -Parent $scriptPath
    $repoCandidate = Join-Path $toolsDir "..\..\..\.."
    $resolved = Resolve-Path -LiteralPath $repoCandidate -ErrorAction Stop
    if ($resolved -is [array]) { $resolved = $resolved[0] }
    if ($resolved.PSObject.Properties.Name -contains "ProviderPath") { return [string]$resolved.ProviderPath }
    if ($resolved.PSObject.Properties.Name -contains "Path") { return [string]$resolved.Path }
    return [string]$resolved
}

function Resolve-DefaultPaths {
    $repoRoot = Get-RepoRoot
    $base = Join-Path $repoRoot "docs_dev\_to_do\205_artifacts"
    if (-not $WorkbookPath) { $WorkbookPath = Join-Path $base "produkty\excel\workspace\205F_visualization_workspace_v01.xlsx" }
    if (-not $WordInputDocx) {
        $WordInputDocx = Join-Path $base "produkty\word\final\205F_embed_canvas_v01.docx"
    }
    if (-not $WordOutputDocx) {
        $WordOutputDocx = Join-Path $base "produkty\word\final\205F_embed_canvas_v02.docx"
    }
    if (-not $WordMapCsv) { $WordMapCsv = Join-Path $base "205F\inputs\205F_word_embed_map_v01.csv" }
    if (-not $OutRunJson) { $OutRunJson = Join-Path $base "205F\analysis\205F_word_embed_run_v01.json" }
    if (-not $OutRunMd) { $OutRunMd = Join-Path $base "205F\analysis\205F_word_embed_run_v01.md" }
    return @{
        WorkbookPath = $WorkbookPath
        WordInputDocx = $WordInputDocx
        WordOutputDocx = $WordOutputDocx
        WordMapCsv = $WordMapCsv
        OutRunJson = $OutRunJson
        OutRunMd = $OutRunMd
    }
}

function New-RunDir {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
    $dir = Join-Path $Root ("run_" + $stamp + "_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
    return $dir
}

function New-ChartResult {
    param(
        [string]$ChartId,
        [string]$Bookmark,
        [string]$Sheet,
        [string]$ChartName
    )
    return [ordered]@{
        chart_id = $ChartId
        word_bookmark = $Bookmark
        excel_sheet = $Sheet
        excel_chart_name = $ChartName
        started_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        finished_at = ""
        duration_s = 0
        stage = "start"
        status = "unknown"
        error = ""
    }
}

function Check-ChartTimeout {
    param(
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [int]$LimitSec
    )
    if ($LimitSec -gt 0 -and $Stopwatch.Elapsed.TotalSeconds -gt $LimitSec) {
        throw "timeout"
    }
}

function Ensure-ParentDir {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
}

$paths = Resolve-DefaultPaths
$WorkbookPath = $paths.WorkbookPath
$WordInputDocx = $paths.WordInputDocx
$WordOutputDocx = $paths.WordOutputDocx
$WordMapCsv = $paths.WordMapCsv
$OutRunJson = $paths.OutRunJson
$OutRunMd = $paths.OutRunMd

if (-not (Test-Path -LiteralPath $WorkbookPath)) { throw "Missing workbook: $WorkbookPath" }
if (-not (Test-Path -LiteralPath $WordInputDocx)) { throw "Missing Word input: $WordInputDocx" }
if (-not (Test-Path -LiteralPath $WordMapCsv)) { throw "Missing map csv: $WordMapCsv" }
if ($StepTimeoutSec -lt 0) { throw "StepTimeoutSec must be >= 0" }

$mapRows = @(
    Import-Csv -LiteralPath $WordMapCsv | Where-Object {
        $status = ([string]$_.status).Trim().ToLowerInvariant()
        $status -ne "disabled" -and $status -ne "skip" -and $status -ne "inactive"
    }
)

$runStarted = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$runDir = New-RunDir -Root $StagingRoot
$localWorkbook = Join-Path $runDir "workbook.xlsx"
$localInputDoc = Join-Path $runDir "input.docx"
$localOutputDoc = Join-Path $runDir "output.docx"

Ensure-ParentDir -Path $OutRunJson
Ensure-ParentDir -Path $OutRunMd
Ensure-ParentDir -Path $WordOutputDocx

Copy-Item -LiteralPath $WorkbookPath -Destination $localWorkbook -Force
Copy-Item -LiteralPath $WordInputDocx -Destination $localInputDoc -Force
Copy-Item -LiteralPath $localInputDoc -Destination $localOutputDoc -Force

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

$results = @()
$embedded = 0
$skipped = 0
$failed = 0
$invalidMapping = 0

Write-Host "[S07] Start step. staging=$runDir"

try {
    $wb = $excel.Workbooks.Open($localWorkbook, $false, $true)
    $doc = $word.Documents.Open($localOutputDoc)

    foreach ($row in $mapRows) {
        $chartId = [string]$row.chart_id
        $bmName = [string]$row.word_bookmark
        $sheetName = [string]$row.excel_sheet
        $chartName = [string]$row.excel_chart_name

        $r = New-ChartResult -ChartId $chartId -Bookmark $bmName -Sheet $sheetName -ChartName $chartName
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            Write-Host "[S07][$chartId] stage=find_bookmark"
            $r.stage = "find_bookmark"
            Check-ChartTimeout -Stopwatch $sw -LimitSec $StepTimeoutSec
            if (-not $doc.Bookmarks.Exists($bmName)) {
                $r.status = "skipped_missing_bookmark"
                $skipped++
                $invalidMapping++
                continue
            }

            Write-Host "[S07][$chartId] stage=find_chart"
            $r.stage = "find_chart"
            Check-ChartTimeout -Stopwatch $sw -LimitSec $StepTimeoutSec
            $sheet = $null
            try { $sheet = $wb.Worksheets.Item($sheetName) } catch { $sheet = $null }
            if (-not $sheet) {
                $r.status = "skipped_missing_sheet"
                $skipped++
                $invalidMapping++
                continue
            }
            $chartObj = $null
            try { $chartObj = $sheet.ChartObjects($chartName) } catch { $chartObj = $null }
            if (-not $chartObj) {
                $r.status = "skipped_missing_chart"
                $skipped++
                $invalidMapping++
                continue
            }

            Write-Host "[S07][$chartId] stage=export_png"
            $r.stage = "export_png"
            Check-ChartTimeout -Stopwatch $sw -LimitSec $StepTimeoutSec
            $tmpPng = Join-Path $runDir ("chart_" + [guid]::NewGuid().ToString("N") + ".png")
            [void]$chartObj.Chart.Export($tmpPng, "PNG")
            if (-not (Test-Path -LiteralPath $tmpPng)) {
                throw "failed_export_png"
            }

            Write-Host "[S07][$chartId] stage=insert_picture"
            $r.stage = "insert_picture"
            Check-ChartTimeout -Stopwatch $sw -LimitSec $StepTimeoutSec
            $range = $doc.Bookmarks.Item($bmName).Range
            $range.Text = ""
            $range.Collapse(0)
            $inline = $doc.InlineShapes.AddPicture($tmpPng, $false, $true, $range)
            [void]$doc.Bookmarks.Add($bmName, $inline.Range)
            Remove-Item -LiteralPath $tmpPng -Force -ErrorAction SilentlyContinue

            $r.status = "ok"
            $embedded++
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -eq "timeout") {
                $r.status = "failed_timeout"
                $r.error = "chart exceeded StepTimeoutSec=$StepTimeoutSec"
            } else {
                $safeStage = if ($r.stage) { $r.stage } else { "unknown" }
                $r.status = "failed_$safeStage"
                $r.error = $msg
            }
            $failed++
        }
        finally {
            $r.finished_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            $r.duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 3)
            $results += [pscustomobject]$r
            Write-Host "[S07][$chartId] status=$($r.status) duration_s=$($r.duration_s)"
        }
    }

    Write-Host "[S07] stage=save_doc"
    $doc.Save()
    $doc.Close()
    $wb.Close($false)

    Copy-Item -LiteralPath $localOutputDoc -Destination $WordOutputDocx -Force
}
finally {
    if ($doc) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) }
    if ($wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
    $word.Quit()
    $excel.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word)
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    if (-not $KeepStaging) {
        Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$runFinished = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$payload = [ordered]@{
    generated_at = $runFinished
    step = "S07"
    input_paths = @{
        workbook = $WorkbookPath
        word_input = $WordInputDocx
        map_csv = $WordMapCsv
    }
    output_paths = @{
        word_output = $WordOutputDocx
        report_json = $OutRunJson
        report_md = $OutRunMd
    }
    staging = @{
        root = $StagingRoot
        run_dir = $runDir
        kept = [bool]$KeepStaging
    }
    run = @{
        started_at = $runStarted
        finished_at = $runFinished
        step_timeout_sec = $StepTimeoutSec
        mapped_active = @($mapRows).Count
        embedded_count = $embedded
        skipped_count = $skipped
        failed_count = $failed
        invalid_mapping_count = $invalidMapping
    }
    per_chart = $results
}

$payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutRunJson -Encoding UTF8

$md = @()
$md += "# 205F Word Embed Run v01"
$md += ""
$md += "- generated_at: $($payload.generated_at)"
$md += "- mapped_active: $($payload.run.mapped_active)"
$md += "- embedded_count: $($payload.run.embedded_count)"
$md += "- skipped_count: $($payload.run.skipped_count)"
$md += "- failed_count: $($payload.run.failed_count)"
$md += "- step_timeout_sec: $($payload.run.step_timeout_sec)"
$md += "- staging_root: $StagingRoot"
$md += ""
$md += "| chart_id | status | stage | duration_s | error |"
$md += "|---|---|---|---:|---|"
foreach ($row in $results) {
    $err = ([string]$row.error).Replace("|", "/")
    $md += "| $($row.chart_id) | $($row.status) | $($row.stage) | $($row.duration_s) | $err |"
}
$md -join "`n" | Set-Content -LiteralPath $OutRunMd -Encoding UTF8

Write-Host "[S07] Run JSON: $OutRunJson"
Write-Host "[S07] Run MD:   $OutRunMd"
Write-Host "[S07] embedded=$embedded skipped=$skipped failed=$failed invalid_mapping=$invalidMapping"

if ($failed -gt 0 -or $invalidMapping -gt 0) {
    exit 1
}
