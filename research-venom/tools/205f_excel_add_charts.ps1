[CmdletBinding()]
param(
    [string]$WorkbookPath = "",
    [string]$ChartSpecJson = ""
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
    return @{
        WorkbookPath = $WorkbookPath
        ChartSpecJson = $ChartSpecJson
    }
}

function Get-ColumnIndexByHeader {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][string]$Header
    )
    $usedCols = $Worksheet.UsedRange.Columns.Count
    for ($c = 1; $c -le $usedCols; $c++) {
        $value = [string]$Worksheet.Cells.Item(1, $c).Value2
        if ($value.Trim() -eq $Header.Trim()) {
            return $c
        }
    }
    return -1
}

function Get-LastDataRow {
    param([Parameter(Mandatory = $true)]$Worksheet)
    $xlUp = -4162
    $last = $Worksheet.Cells.Item($Worksheet.Rows.Count, 1).End($xlUp).Row
    if ($last -lt 2) {
        $last = $Worksheet.UsedRange.Rows.Count
    }
    return [int]$last
}

function Get-ChartTypeCode {
    param([string]$Type)
    switch ($Type) {
        "line" { return 4 }
        "combo" { return 4 }
        "bar_horizontal" { return 57 }
        "column" { return 51 }
        default { return 4 }
    }
}

function Resolve-SeriesHeaderAlias {
    param([string]$Header)
    switch ($Header) {
        "opened_count" { return "pr_opened_count_daily" }
        "merged_count" { return "pr_merged_count_daily" }
        "active_count" { return "pr_active_daily" }
        "avg_comments_closed" { return "avg_comments_closed_daily" }
        "avg_comments_merged" { return "avg_comments_merged_daily" }
        default { return $Header }
    }
}

$paths = Resolve-DefaultPaths
$WorkbookPath = $paths.WorkbookPath
$ChartSpecJson = $paths.ChartSpecJson

if (-not (Test-Path -LiteralPath $WorkbookPath)) { throw "Missing workbook: $WorkbookPath" }
if (-not (Test-Path -LiteralPath $ChartSpecJson)) { throw "Missing chart spec: $ChartSpecJson" }

$chartSpec = Get-Content -LiteralPath $ChartSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Open($WorkbookPath)
    $chartsSheet = $wb.Worksheets.Item("charts")

    while ($chartsSheet.ChartObjects().Count -gt 0) {
        $chartsSheet.ChartObjects(1).Delete()
    }

    $index = 0
    foreach ($chartCfg in @($chartSpec.charts)) {
        $chartId = [string]$chartCfg.chart_id
        $sourceSheetName = [string]$chartCfg.source_sheet
        $xHeader = [string]$chartCfg.x_series
        $yHeaders = @($chartCfg.y_series)

        if (-not $chartId) { continue }
        if (-not $sourceSheetName) { continue }

        $srcSheet = $null
        try { $srcSheet = $wb.Worksheets.Item($sourceSheetName) } catch { $srcSheet = $null }
        if (-not $srcSheet) {
            Write-Warning "[S04] Missing source sheet for ${chartId}: $sourceSheetName"
            continue
        }

        $lastRow = Get-LastDataRow -Worksheet $srcSheet
        if ($lastRow -lt 2) {
            Write-Warning "[S04] Source sheet has no data for ${chartId}: $sourceSheetName"
            continue
        }

        $xCol = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header $xHeader
        if ($xCol -lt 1) {
            Write-Warning "[S04] Missing x_series '$xHeader' for $chartId"
            continue
        }

        $colIndex = [int]($index % 2)
        $rowIndex = [math]::Floor($index / 2)
        $left = 20 + (620 * $colIndex)
        $top = 20 + (360 * $rowIndex)
        $width = 580
        $height = 320

        $co = $chartsSheet.ChartObjects().Add($left, $top, $width, $height)
        $co.Name = $chartId
        $chart = $co.Chart
        $chart.ChartType = (Get-ChartTypeCode -Type ([string]$chartCfg.chart_type))
        $chart.HasTitle = $true
        $chart.ChartTitle.Text = [string]$chartCfg.title
        $chart.HasLegend = $true

        while ($chart.SeriesCollection().Count -gt 0) {
            $chart.SeriesCollection(1).Delete()
        }

        foreach ($yHeader in $yHeaders) {
            $yName = [string]$yHeader
            if (-not $yName) { continue }
            $lookupHeader = Resolve-SeriesHeaderAlias -Header $yName
            $yCol = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header $lookupHeader
            if ($yCol -lt 1) {
                Write-Warning "[S04] Missing y_series '$yName' (lookup '$lookupHeader') for $chartId"
                continue
            }

            $series = $chart.SeriesCollection().NewSeries()
            $series.Name = $yName
            $series.XValues = $srcSheet.Range($srcSheet.Cells.Item(2, $xCol), $srcSheet.Cells.Item($lastRow, $xCol))
            $series.Values = $srcSheet.Range($srcSheet.Cells.Item(2, $yCol), $srcSheet.Cells.Item($lastRow, $yCol))
        }

        $index++
    }

    $wb.Save()
    $wb.Close($true)
    Write-Host "[S04] Charts added to workbook: $WorkbookPath"
    Write-Host "[S04] Charts created: $index"
}
finally {
    if ($wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
    $excel.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
