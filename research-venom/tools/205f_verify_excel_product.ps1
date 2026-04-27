[CmdletBinding()]
param(
    [string]$WorkbookPath = "",
    [string]$ChartSpecJson = "",
    [string]$OutJson = "",
    [string]$OutMd = ""
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
    if (-not $ChartSpecJson) { $ChartSpecJson = Join-Path $base "205F\inputs\205F_chart_spec_v01.json" }
    if (-not $OutJson) { $OutJson = Join-Path $base "205F\analysis\205F_excel_verify_v01.json" }
    if (-not $OutMd) { $OutMd = Join-Path $base "205F\analysis\205F_excel_verify_v01.md" }
    return @{
        WorkbookPath = $WorkbookPath
        ChartSpecJson = $ChartSpecJson
        OutJson = $OutJson
        OutMd = $OutMd
    }
}

$paths = Resolve-DefaultPaths
$WorkbookPath = $paths.WorkbookPath
$ChartSpecJson = $paths.ChartSpecJson
$OutJson = $paths.OutJson
$OutMd = $paths.OutMd

if (-not (Test-Path -LiteralPath $WorkbookPath)) { throw "Missing workbook: $WorkbookPath" }
if (-not (Test-Path -LiteralPath $ChartSpecJson)) { throw "Missing chart spec: $ChartSpecJson" }

$chartSpec = Get-Content -LiteralPath $ChartSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Open($WorkbookPath, $false, $true)
    $sheetNames = @()
    foreach ($ws in @($wb.Worksheets)) { $sheetNames += [string]$ws.Name }

    $chartsSheet = $null
    try { $chartsSheet = $wb.Worksheets.Item("charts") } catch { $chartsSheet = $null }

    $chartChecks = @()
    foreach ($cfg in @($chartSpec.charts)) {
        $chartId = [string]$cfg.chart_id
        $sourceSheetName = [string]$cfg.source_sheet
        $check = [ordered]@{
            chart_id = $chartId
            source_sheet = $sourceSheetName
            source_sheet_exists = $false
            source_sheet_has_rows = $false
            chart_exists = $false
            series_count = 0
            status = "missing"
        }

        $sourceSheet = $null
        try { $sourceSheet = $wb.Worksheets.Item($sourceSheetName) } catch { $sourceSheet = $null }
        if ($sourceSheet) {
            $check.source_sheet_exists = $true
            $usedRows = [int]$sourceSheet.UsedRange.Rows.Count
            if ($usedRows -gt 1) { $check.source_sheet_has_rows = $true }
        }

        if ($chartsSheet) {
            $chartObj = $null
            try { $chartObj = $chartsSheet.ChartObjects($chartId) } catch { $chartObj = $null }
            if ($chartObj) {
                $check.chart_exists = $true
                $check.series_count = [int]$chartObj.Chart.SeriesCollection().Count
            }
        }

        if ($check.source_sheet_exists -and $check.source_sheet_has_rows -and $check.chart_exists -and $check.series_count -gt 0) {
            $check.status = "ok"
        } elseif ($check.chart_exists -and $check.series_count -eq 0) {
            $check.status = "chart_empty_series"
        } elseif (-not $check.chart_exists) {
            $check.status = "missing_chart"
        } elseif (-not $check.source_sheet_exists) {
            $check.status = "missing_source_sheet"
        } else {
            $check.status = "source_no_rows"
        }
        $chartChecks += [pscustomobject]$check
    }

    $failed = @($chartChecks | Where-Object { $_.status -ne "ok" })
    $payload = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        workbook_path = $WorkbookPath
        chart_spec_path = $ChartSpecJson
        sheets = $sheetNames
        chart_checks = $chartChecks
        totals = @{
            charts_spec = @($chartChecks).Count
            charts_ok = @($chartChecks | Where-Object { $_.status -eq "ok" }).Count
            charts_failed = $failed.Count
        }
    }

    $outDir = Split-Path -Parent $OutJson
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }

    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutJson -Encoding UTF8

    $md = @()
    $md += "# 205F Excel Verify v01"
    $md += ""
    $md += "- generated_at: $($payload.generated_at)"
    $md += "- workbook: $WorkbookPath"
    $md += "- charts_ok: $($payload.totals.charts_ok) / $($payload.totals.charts_spec)"
    $md += ""
    $md += "| chart_id | status | series_count | source_sheet |"
    $md += "|---|---|---:|---|"
    foreach ($row in $chartChecks) {
        $md += "| $($row.chart_id) | $($row.status) | $($row.series_count) | $($row.source_sheet) |"
    }
    $md += ""
    if ($failed.Count -gt 0) {
        $md += "## Failed"
        foreach ($f in $failed) { $md += "- $($f.chart_id): $($f.status)" }
    } else {
        $md += "## Result"
        $md += "- all checks passed"
    }
    $md -join "`n" | Set-Content -LiteralPath $OutMd -Encoding UTF8

    $wb.Close($false)
    Write-Host "[S08] Verify JSON: $OutJson"
    Write-Host "[S08] Verify MD:   $OutMd"
    Write-Host "[S08] Charts OK:   $($payload.totals.charts_ok)/$($payload.totals.charts_spec)"
}
finally {
    if ($wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
    $excel.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
