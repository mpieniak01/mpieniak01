[CmdletBinding()]
param(
    [string]$WorkbookPath = "",
    [string]$ChartSpecJson = "",
    [string]$PatternsDoc = ""
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
    if (-not $PatternsDoc) { $PatternsDoc = Join-Path $base "205F\inputs\205F_excel_advanced_patterns_v01.md" }
    return @{
        WorkbookPath = $WorkbookPath
        ChartSpecJson = $ChartSpecJson
        PatternsDoc = $PatternsDoc
    }
}

function Get-OrCreateWorksheet {
    param(
        [Parameter(Mandatory = $true)]$Workbook,
        [Parameter(Mandatory = $true)][string]$Name
    )
    try {
        return $Workbook.Worksheets.Item($Name)
    }
    catch {
        $ws = $Workbook.Worksheets.Add()
        $ws.Name = $Name
        return $ws
    }
}

function Has-AnyItems {
    param($Value)
    if ($null -eq $Value) { return $false }
    $arr = @($Value)
    return $arr.Count -gt 0
}

function Get-ArrayPropertyOrEmpty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )
    $prop = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $prop) { return @() }
    if ($null -eq $prop.Value) { return @() }
    return @($prop.Value)
}

$paths = Resolve-DefaultPaths
$WorkbookPath = $paths.WorkbookPath
$ChartSpecJson = $paths.ChartSpecJson
$PatternsDoc = $paths.PatternsDoc

if (-not (Test-Path -LiteralPath $WorkbookPath)) { throw "Missing workbook: $WorkbookPath" }
if (-not (Test-Path -LiteralPath $ChartSpecJson)) { throw "Missing chart spec: $ChartSpecJson" }

$chartSpec = Get-Content -LiteralPath $ChartSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json
$patternsText = ""
if (Test-Path -LiteralPath $PatternsDoc) {
    $patternsText = Get-Content -LiteralPath $PatternsDoc -Raw -Encoding UTF8
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Open($WorkbookPath)
    $chartsSheet = $wb.Worksheets.Item("charts")
    $metaSheet = Get-OrCreateWorksheet -Workbook $wb -Name "meta"

    $metaSheet.Cells.Item(1, 1).Value2 = "chart_id"
    $metaSheet.Cells.Item(1, 2).Value2 = "has_background_series"
    $metaSheet.Cells.Item(1, 3).Value2 = "has_label_series"
    $metaSheet.Cells.Item(1, 4).Value2 = "has_reference_lines"
    $metaSheet.Cells.Item(1, 5).Value2 = "has_annotation_shapes"
    $metaSheet.Cells.Item(1, 6).Value2 = "applied_at_utc"
    $metaSheet.Cells.Item(1, 7).Value2 = "patterns_doc_attached"
    $metaSheet.Rows.Item(1).Font.Bold = $true

    $r = 2
    $appliedCount = 0
    foreach ($chartCfg in @($chartSpec.charts)) {
        $chartId = [string]$chartCfg.chart_id
        if (-not $chartId) { continue }

        $hasBg = Has-AnyItems (Get-ArrayPropertyOrEmpty -Object $chartCfg -PropertyName "background_series")
        $hasLbl = Has-AnyItems (Get-ArrayPropertyOrEmpty -Object $chartCfg -PropertyName "label_series")
        $hasRef = Has-AnyItems (Get-ArrayPropertyOrEmpty -Object $chartCfg -PropertyName "reference_lines")
        $hasAnn = Has-AnyItems (Get-ArrayPropertyOrEmpty -Object $chartCfg -PropertyName "annotation_shapes")
        $isTypeB = $hasBg -or $hasLbl -or $hasRef -or $hasAnn

        $metaSheet.Cells.Item($r, 1).Value2 = $chartId
        $metaSheet.Cells.Item($r, 2).Value2 = $(if ($hasBg) { "true" } else { "false" })
        $metaSheet.Cells.Item($r, 3).Value2 = $(if ($hasLbl) { "true" } else { "false" })
        $metaSheet.Cells.Item($r, 4).Value2 = $(if ($hasRef) { "true" } else { "false" })
        $metaSheet.Cells.Item($r, 5).Value2 = $(if ($hasAnn) { "true" } else { "false" })
        $metaSheet.Cells.Item($r, 6).Value2 = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $metaSheet.Cells.Item($r, 7).Value2 = $(if ($patternsText.Length -gt 0) { "true" } else { "false" })

        if ($isTypeB) {
            $co = $null
            try { $co = $chartsSheet.ChartObjects($chartId) } catch { $co = $null }
            if ($co) {
                $left = [double]$co.Left
                $top = [double]$co.Top
                $width = [double]$co.Width
                $height = [double]$co.Height

                $tb = $chartsSheet.Shapes.AddTextbox(1, $left + 8, $top + $height - 24, 260, 18)
                $tb.TextFrame2.TextRange.Text = "Type-B overlays: BG/LBL/REF/ANN"
                $tb.Name = "ANN_$chartId"

                $line = $chartsSheet.Shapes.AddLine($left + 8, $top + ($height / 2), $left + $width - 8, $top + ($height / 2))
                $line.Name = "REF_$chartId"
                $line.Line.DashStyle = 4
            }
            $appliedCount++
        }
        $r++
    }

    $metaSheet.Columns.AutoFit() | Out-Null
    $wb.Save()
    $wb.Close($true)
    Write-Host "[S05] Advanced pattern metadata stored in 'meta' sheet"
    Write-Host "[S05] Type-B charts processed: $appliedCount"
}
finally {
    if ($wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
    $excel.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
