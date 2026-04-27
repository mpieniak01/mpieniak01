[CmdletBinding()]
param(
    [string]$SourcesPackJson = "",
    [string]$SummaryCsv = "",
    [string]$LayoutCsv = "",
    [string]$OutWorkbook = ""
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
    if (-not $SourcesPackJson) { $SourcesPackJson = Join-Path $base "produkty\meta\205F_sources_pack_v01.json" }
    if (-not $SummaryCsv) { $SummaryCsv = Join-Path $base "produkty\meta\205F_summary_tables_v01.csv" }
    if (-not $LayoutCsv) { $LayoutCsv = Join-Path $base "205F\inputs\205F_excel_sheet_layout_v01.csv" }
    if (-not $OutWorkbook) { $OutWorkbook = Join-Path $base "produkty\excel\workspace\205F_visualization_workspace_v01.xlsx" }
    return @{
        SourcesPackJson = $SourcesPackJson
        SummaryCsv = $SummaryCsv
        LayoutCsv = $LayoutCsv
        OutWorkbook = $OutWorkbook
    }
}

function Write-ObjectsToSheet {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)]$Rows
    )

    $Worksheet.Cells.Clear() | Out-Null
    $rowsArray = @($Rows)
    if ($rowsArray.Count -eq 0) {
        $Worksheet.Cells.Item(1, 1).Value2 = "no_data"
        return
    }

    $headers = @($rowsArray[0].PSObject.Properties.Name)
    if ($headers.Count -eq 0) {
        $Worksheet.Cells.Item(1, 1).Value2 = "no_columns"
        return
    }

    for ($c = 0; $c -lt $headers.Count; $c++) {
        $Worksheet.Cells.Item(1, $c + 1).Value2 = $headers[$c]
    }

    for ($r = 0; $r -lt $rowsArray.Count; $r++) {
        $row = $rowsArray[$r]
        for ($c = 0; $c -lt $headers.Count; $c++) {
            $name = $headers[$c]
            $value = $row.$name
            if ($null -eq $value) {
                $Worksheet.Cells.Item($r + 2, $c + 1).Value2 = ""
            } elseif ($value -is [bool]) {
                $Worksheet.Cells.Item($r + 2, $c + 1).Value2 = $(if ($value) { "true" } else { "false" })
            } else {
                $Worksheet.Cells.Item($r + 2, $c + 1).Value2 = [string]$value
            }
        }
    }

    $Worksheet.Rows.Item(1).Font.Bold = $true
    $Worksheet.Columns.AutoFit() | Out-Null
}

function Get-PackTableRows {
    param(
        [Parameter(Mandatory = $true)]$Pack,
        [Parameter(Mandatory = $true)][string]$TableName
    )
    $table = $Pack.tables.PSObject.Properties[$TableName]
    if ($null -eq $table) { return @() }
    return @($table.Value)
}

$paths = Resolve-DefaultPaths
$SourcesPackJson = $paths.SourcesPackJson
$SummaryCsv = $paths.SummaryCsv
$LayoutCsv = $paths.LayoutCsv
$OutWorkbook = $paths.OutWorkbook

if (-not (Test-Path -LiteralPath $SourcesPackJson)) { throw "Missing SourcesPackJson: $SourcesPackJson" }
if (-not (Test-Path -LiteralPath $SummaryCsv)) { throw "Missing SummaryCsv: $SummaryCsv" }
if (-not (Test-Path -LiteralPath $LayoutCsv)) { throw "Missing LayoutCsv: $LayoutCsv" }

$pack = Get-Content -LiteralPath $SourcesPackJson -Raw -Encoding UTF8 | ConvertFrom-Json
$layout = Import-Csv -LiteralPath $LayoutCsv
$summaryRows = Import-Csv -LiteralPath $SummaryCsv

$outDir = Split-Path -Parent $OutWorkbook
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Add()

    while ($wb.Worksheets.Count -gt 1) {
        $wb.Worksheets.Item(2).Delete()
    }
    $defaultSheet = $wb.Worksheets.Item(1)

    $orderedLayout = @($layout | Sort-Object { [int]$_.order })
    $createdSheets = @{}
    foreach ($entry in $orderedLayout) {
        $name = [string]$entry.sheet_name
        if (-not $name) { continue }
        if ($createdSheets.ContainsKey($name)) { continue }
        $ws = $wb.Worksheets.Add()
        $ws.Name = $name
        $createdSheets[$name] = $ws
    }
    $defaultSheet.Delete()

    foreach ($entry in $orderedLayout) {
        $sheetName = [string]$entry.sheet_name
        if (-not $sheetName) { continue }
        $ws = $wb.Worksheets.Item($sheetName)

        if ($sheetName -eq "summary") {
            Write-ObjectsToSheet -Worksheet $ws -Rows $summaryRows
            continue
        }
        if ($sheetName -eq "meta") {
            $metaRows = @(
                [pscustomobject]@{ key = "artifact"; value = $pack.artifact }
                [pscustomobject]@{ key = "version"; value = $pack.version }
                [pscustomobject]@{ key = "generated_at"; value = $pack.generated_at }
                [pscustomobject]@{ key = "sources_pack_json"; value = $SourcesPackJson }
                [pscustomobject]@{ key = "summary_csv"; value = $SummaryCsv }
            )
            Write-ObjectsToSheet -Worksheet $ws -Rows $metaRows
            continue
        }
        if ($sheetName -eq "charts") {
            $chartRows = @(
                [pscustomobject]@{ note = "chart objects are created by 205f_excel_add_charts.ps1" }
                [pscustomobject]@{ note = "do not edit chart names manually (chart_id)" }
            )
            Write-ObjectsToSheet -Worksheet $ws -Rows $chartRows
            continue
        }

        $tableRows = Get-PackTableRows -Pack $pack -TableName $sheetName
        Write-ObjectsToSheet -Worksheet $ws -Rows $tableRows
    }

    $wb.SaveAs($OutWorkbook, 51)
    $wb.Close($true)
    Write-Host "[S03] Workbook created: $OutWorkbook"
}
finally {
    if ($wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
    $excel.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
