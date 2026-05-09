[CmdletBinding()]
param(
    [string]$SourcesPackJson = "",
    [string]$SummaryCsv = "",
    [string]$LayoutCsv = "",
    [string]$LayoutSpecJson = "",
    [string]$StyleProfileJson = "",
    [string]$ChartSpecJson = "",
    [string]$OutWorkbook = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { "" }
    if (-not $scriptPath) { throw "Cannot resolve script path for Get-RepoRoot" }
    $toolsDir = Split-Path -Parent $scriptPath
    $repoCandidate = Join-Path $toolsDir ".."
    $resolved = Resolve-Path -LiteralPath $repoCandidate -ErrorAction Stop
    if ($resolved -is [array]) { $resolved = $resolved[0] }
    if ($resolved.PSObject.Properties.Name -contains "ProviderPath") { return [string]$resolved.ProviderPath }
    if ($resolved.PSObject.Properties.Name -contains "Path") { return [string]$resolved.Path }
    return [string]$resolved
}

function Resolve-DefaultPaths {
    $repoRoot = Get-RepoRoot
    $base = Join-Path $repoRoot "artifacts"
    if (-not $SourcesPackJson) { $SourcesPackJson = Join-Path $base "processing\visualization\sources_pack_v01.json" }
    if (-not $SummaryCsv) { $SummaryCsv = Join-Path $base "processing\visualization\summary_tables_v01.csv" }
    if (-not $LayoutCsv) { $LayoutCsv = Join-Path $base "inputs\visualization\excel_sheet_layout_v04.csv" }
    if (-not $LayoutSpecJson) { $LayoutSpecJson = Join-Path $base "inputs\visualization\workbook_layout_v04.json" }
    if (-not $StyleProfileJson) { $StyleProfileJson = Join-Path $base "inputs\visualization\chart_style_profile_v04.json" }
    if (-not $ChartSpecJson) { $ChartSpecJson = Join-Path $base "inputs\visualization\chart_spec_v04.json" }
    if (-not $OutWorkbook) { $OutWorkbook = Join-Path $repoRoot "_external\not_tracked\visualization\workbook_v04.xlsx" }
    return @{
        SourcesPackJson = $SourcesPackJson
        SummaryCsv = $SummaryCsv
        LayoutCsv = $LayoutCsv
        LayoutSpecJson = $LayoutSpecJson
        StyleProfileJson = $StyleProfileJson
        ChartSpecJson = $ChartSpecJson
        OutWorkbook = $OutWorkbook
    }
}

function Apply-HeaderStyle {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][int]$HeaderRow,
        [Parameter(Mandatory = $true)][int]$LastCol,
        $StyleProfile,
        $SourceTypeStyle = $null
    )

    $headerRange = $Worksheet.Range($Worksheet.Cells.Item($HeaderRow, 1), $Worksheet.Cells.Item($HeaderRow, $LastCol))
    $headerRange.Font.Bold = $true

    if ($StyleProfile -and $StyleProfile.table_header) {
        $th = $StyleProfile.table_header
        if (($th.PSObject.Properties.Name -contains "font_name") -and $th.font_name) { $headerRange.Font.Name = [string]$th.font_name }
        if (($th.PSObject.Properties.Name -contains "font_size") -and $null -ne $th.font_size) { $headerRange.Font.Size = [double]$th.font_size }
        if ($th.PSObject.Properties.Name -contains "bold") { $headerRange.Font.Bold = [bool]$th.bold }
        if ($th.PSObject.Properties.Name -contains "italic") { $headerRange.Font.Italic = [bool]$th.italic }
        if (($th.PSObject.Properties.Name -contains "font_color_rgb") -and $th.font_color_rgb) {
            $fontColor = Parse-HexColorToCom -Rgb ([string]$th.font_color_rgb)
            if ($null -ne $fontColor) { $headerRange.Font.Color = $fontColor }
        }
        # Domain-specific header fill overrides generic table_header fill
        $headerFillRgb = if ($SourceTypeStyle -and ($SourceTypeStyle.PSObject.Properties.Name -contains "header_fill_rgb") -and $SourceTypeStyle.header_fill_rgb) `
                         { [string]$SourceTypeStyle.header_fill_rgb } `
                         elseif (($th.PSObject.Properties.Name -contains "fill_color_rgb") -and $th.fill_color_rgb) { [string]$th.fill_color_rgb } else { "" }
        if ($headerFillRgb) {
            $fillColor = Parse-HexColorToCom -Rgb $headerFillRgb
            if ($null -ne $fillColor) { $headerRange.Interior.Color = $fillColor }
        }
    }
}

function Parse-HexColorToCom {
    param([string]$Rgb)
    if (-not $Rgb) { return $null }
    $clean = $Rgb.Trim().ToUpper()
    if ($clean.Length -eq 8 -and $clean.StartsWith("FF")) { $clean = $clean.Substring(2) }
    if ($clean.Length -ne 6) { return $null }
    $r = [Convert]::ToInt32($clean.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($clean.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($clean.Substring(4, 2), 16)
    return ($b * 65536) + ($g * 256) + $r
}

function Get-IsAcademicModeEnabled {
    param($StyleProfile)
    if (-not $StyleProfile) { return $false }
    if ($StyleProfile.PSObject.Properties.Name -contains "academic_style") {
        $ac = $StyleProfile.academic_style
        if ($ac -and ($ac.PSObject.Properties.Name -contains "enabled") -and $ac.enabled -eq $true) { return $true }
    }
    return $false
}

function Resolve-ColumnLabel {
    param(
        [Parameter(Mandatory = $true)][string]$ColumnName,
        $StyleProfile
    )
    if ($StyleProfile -and $StyleProfile.column_aliases) {
        $prop = $StyleProfile.column_aliases.PSObject.Properties[$ColumnName]
        if ($null -ne $prop -and $prop.Value) { return [string]$prop.Value }
    }
    return $ColumnName
}

function Convert-ToWorkbookValue {
    param(
        [string]$HeaderName,
        $Value
    )
    if ($null -eq $Value) { return "" }
    if ($Value -is [bool]) { return $(if ($Value) { "true" } else { "false" }) }
    if ([string]::Equals([string]$HeaderName, "date", [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($Value -is [datetime]) { return [datetime]$Value }
        $text = [string]$Value
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            try {
                return [datetime]::ParseExact($text, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
            } catch {
                try { return [datetime]$text } catch { return $text }
            }
        }
    }
    return [string]$Value
}

function Try-ParseDateValue {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return [datetime]$Value }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $text = $text.Trim()

    $formats = @(
        "yyyy-MM-dd",
        "yyyy-M-d",
        "yyyy.MM.dd",
        "yyyy/M/d",
        "dd.MM.yyyy",
        "d.M.yyyy",
        "dd-MM-yyyy",
        "d-M-yyyy",
        "MM/dd/yyyy",
        "M/d/yyyy"
    )

    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($text, $formats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return $parsed
    }
    if ([datetime]::TryParse($text, [System.Globalization.CultureInfo]::CurrentCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return $parsed
    }
    if ([datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function Apply-TableBodyStyle {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][int]$HeaderRow,
        [Parameter(Mandatory = $true)][int]$DataStartRow,
        [Parameter(Mandatory = $true)][int]$LastRow,
        [Parameter(Mandatory = $true)][int]$LastCol,
        $StyleProfile
    )

    if (-not $StyleProfile -or -not $StyleProfile.table_body) { return }
    $tb = $StyleProfile.table_body
    $allRange = $Worksheet.Range($Worksheet.Cells.Item($HeaderRow, 1), $Worksheet.Cells.Item($LastRow, $LastCol))
    if (($tb.PSObject.Properties.Name -contains "font_name") -and $tb.font_name) { $allRange.Font.Name = [string]$tb.font_name }
    if (($tb.PSObject.Properties.Name -contains "font_size") -and $null -ne $tb.font_size) { $allRange.Font.Size = [double]$tb.font_size }
    if (($tb.PSObject.Properties.Name -contains "font_color_rgb") -and $tb.font_color_rgb) {
        $fontColor = Parse-HexColorToCom -Rgb ([string]$tb.font_color_rgb)
        if ($null -ne $fontColor) { $allRange.Font.Color = $fontColor }
    }

    if (($tb.PSObject.Properties.Name -contains "border_color_rgb") -and $tb.border_color_rgb) {
        $borderColor = Parse-HexColorToCom -Rgb ([string]$tb.border_color_rgb)
        if ($null -ne $borderColor) {
            foreach ($idx in @(7, 8, 9, 10, 11, 12)) {
                $allRange.Borders.Item($idx).LineStyle = 1
                $allRange.Borders.Item($idx).Color = $borderColor
                $allRange.Borders.Item($idx).Weight = 2
            }
        }
    }

    if (($tb.PSObject.Properties.Name -contains "alternate_fill_rgb") -and $tb.alternate_fill_rgb) {
        $altColor = Parse-HexColorToCom -Rgb ([string]$tb.alternate_fill_rgb)
        if ($null -ne $altColor) {
            for ($r = $DataStartRow; $r -le $LastRow; $r++) {
                if ((($r - $DataStartRow) % 2) -eq 1) {
                    $Worksheet.Range($Worksheet.Cells.Item($r, 1), $Worksheet.Cells.Item($r, $LastCol)).Interior.Color = $altColor
                }
            }
        }
    }

    if ($tb.enable_filter -eq $true) {
        $Worksheet.Range($Worksheet.Cells.Item($HeaderRow, 1), $Worksheet.Cells.Item($LastRow, $LastCol)).AutoFilter() | Out-Null
    }
    if ($tb.freeze_panes -eq $true) {
        $Worksheet.Application.ActiveWindow.SplitRow = $HeaderRow
        $Worksheet.Application.ActiveWindow.FreezePanes = $true
    }
}

function Convert-LongRowsToWideRows {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$RowField,
        [Parameter(Mandatory = $true)][string]$ColumnField,
        [Parameter(Mandatory = $true)][string]$ValueField,
        [string[]]$ColumnOrder = @()
    )

    $rowsArray = @($Rows)
    if ($rowsArray.Count -eq 0) { return @() }

    $rowMap = @{}
    $rowOrder = New-Object System.Collections.Generic.List[string]
    $columnSeen = New-Object System.Collections.Generic.List[string]

    foreach ($row in $rowsArray) {
        $rowKey = [string]$row.$RowField
        $columnKey = [string]$row.$ColumnField
        $value = $row.$ValueField

        if (-not $rowMap.ContainsKey($rowKey)) {
            $rowMap[$rowKey] = @{}
            [void]$rowOrder.Add($rowKey)
        }
        if (-not $columnSeen.Contains($columnKey)) {
            [void]$columnSeen.Add($columnKey)
        }
        $rowMap[$rowKey][$ColumnField] = $columnKey
        $rowMap[$rowKey][$RowField] = $row.$RowField
        $rowMap[$rowKey][$columnKey] = $value
    }

    $orderedColumns = @()
    if ($ColumnOrder -and @($ColumnOrder).Count -gt 0) {
        $orderedColumns = @($ColumnOrder)
    } else {
        $orderedColumns = @($columnSeen)
    }

    $outputRows = @()
    foreach ($rowKey in $rowOrder) {
        $current = $rowMap[$rowKey]
        $obj = [ordered]@{}
        $obj[$RowField] = $current[$RowField]
        foreach ($col in $orderedColumns) {
            if ([string]::IsNullOrWhiteSpace([string]$col)) { continue }
            if ($current.ContainsKey([string]$col)) {
                $obj[[string]$col] = $current[[string]$col]
            } else {
                $obj[[string]$col] = ""
            }
        }
        $outputRows += [pscustomobject]$obj
    }

    return @($outputRows)
}

function Write-ObjectsToSheet {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)]$Rows,
        [int]$HeaderRow = 1,
        [int]$DataStartRow = 2,
        [string]$TableTitle = "",
        [string]$TableDescription = "",
        [string]$AnalysisCaption = "",
        [string]$SourceType = "",
        $TableTransform = $null,
        $StyleProfile
    )

    $Worksheet.Cells.Clear() | Out-Null
    $sourceTypeStyle = $null
    if ($StyleProfile -and $StyleProfile.source_type_palette -and $SourceType) {
        $paletteEntry = $StyleProfile.source_type_palette.PSObject.Properties[$SourceType]
        if ($null -ne $paletteEntry -and $paletteEntry.Value) {
            $sourceTypeStyle = $paletteEntry.Value
        }
    }
    $worksheetStyle = $null
    if ($StyleProfile -and $StyleProfile.worksheet_style) {
        $worksheetStyle = $StyleProfile.worksheet_style
    }

    $rowsArray = @($Rows)
    if ($TableTransform -and $TableTransform.type) {
        $transformType = [string]$TableTransform.type
        if ($transformType -eq "pivot_long") {
            $rowField = if ($TableTransform.row_field) { [string]$TableTransform.row_field } else { "project_key" }
            $columnField = if ($TableTransform.column_field) { [string]$TableTransform.column_field } else { "metric_name" }
            $valueField = if ($TableTransform.value_field) { [string]$TableTransform.value_field } else { "metric_value" }
            $columnOrder = @()
            if ($TableTransform.column_order) { $columnOrder = @($TableTransform.column_order) }
            $rowsArray = Convert-LongRowsToWideRows -Rows $rowsArray -RowField $rowField -ColumnField $columnField -ValueField $valueField -ColumnOrder $columnOrder
        }
    }
    if ($rowsArray.Count -eq 0) {
        $Worksheet.Cells.Item($HeaderRow, 1).Value2 = "no_data"
        return
    }

    $headers = @($rowsArray[0].PSObject.Properties.Name)
    if ($headers.Count -eq 0) {
        $Worksheet.Cells.Item($HeaderRow, 1).Value2 = "no_columns"
        return
    }

    for ($c = 0; $c -lt $headers.Count; $c++) {
        $Worksheet.Cells.Item($HeaderRow, $c + 1).Value2 = Resolve-ColumnLabel -ColumnName $headers[$c] -StyleProfile $StyleProfile
    }

    for ($r = 0; $r -lt $rowsArray.Count; $r++) {
        $row = $rowsArray[$r]
        for ($c = 0; $c -lt $headers.Count; $c++) {
            $name = $headers[$c]
            $value = $row.$name
            if ([string]::Equals([string]$name, "date", [System.StringComparison]::OrdinalIgnoreCase)) {
                $dateValue = Try-ParseDateValue -Value $value
                if ($null -ne $dateValue) {
                    # Persist date as Excel serial value to avoid DATE()/DATA() formulas in cells.
                    $Worksheet.Cells.Item($DataStartRow + $r, $c + 1).Value2 = [double]$dateValue.ToOADate()
                    continue
                }
            }
            $cellValue = [object](Convert-ToWorkbookValue -HeaderName $name -Value $value)
            $Worksheet.Cells.Item($DataStartRow + $r, $c + 1).Value = $cellValue
        }
    }

    if ($TableTitle) {
        $titleCell = $Worksheet.Cells.Item(1, 1)
        $titleCell.Value2 = $TableTitle
        $titleCell.Font.Bold = $true
        if ($StyleProfile) {
            $titleStyleNode = if ($StyleProfile.PSObject.Properties.Name -contains "sheet_title") { $StyleProfile.sheet_title } elseif ($StyleProfile.PSObject.Properties.Name -contains "chart_title") { $StyleProfile.chart_title } else { $null }
            $headerFillRgb = ""
            if (($StyleProfile.PSObject.Properties.Name -contains "table_header") -and $StyleProfile.table_header.PSObject.Properties.Name -contains "fill_color_rgb") {
                $headerFillRgb = [string]$StyleProfile.table_header.fill_color_rgb
            }
            if ($sourceTypeStyle -and ($sourceTypeStyle.PSObject.Properties.Name -contains "header_fill_rgb") -and $sourceTypeStyle.header_fill_rgb) {
                $headerFillRgb = [string]$sourceTypeStyle.header_fill_rgb
            }
            if ($titleStyleNode) {
                if (($titleStyleNode.PSObject.Properties.Name -contains "font_name") -and $titleStyleNode.font_name) { $titleCell.Font.Name = [string]$titleStyleNode.font_name }
                if (($titleStyleNode.PSObject.Properties.Name -contains "font_size") -and $null -ne $titleStyleNode.font_size) { $titleCell.Font.Size = [double]$titleStyleNode.font_size }
                if ($titleStyleNode.PSObject.Properties.Name -contains "bold") { $titleCell.Font.Bold = [bool]$titleStyleNode.bold }
                if ($titleStyleNode.PSObject.Properties.Name -contains "italic") { $titleCell.Font.Italic = [bool]$titleStyleNode.italic }

                $titleBand = $Worksheet.Range($Worksheet.Cells.Item(1, 1), $Worksheet.Cells.Item(1, $headers.Count))
                $titleFillRgb = if (($titleStyleNode.PSObject.Properties.Name -contains "fill_color_rgb") -and $titleStyleNode.fill_color_rgb) { [string]$titleStyleNode.fill_color_rgb } else { "FFFFFF" }
                $titleFill = Parse-HexColorToCom -Rgb $titleFillRgb
                if ($null -ne $titleFill) { try { $titleBand.Interior.Color = $titleFill } catch {} }

                $titleFontRgb = ""
                if (($titleStyleNode.PSObject.Properties.Name -contains "font_color_source") -and [string]$titleStyleNode.font_color_source -eq "table_header_fill") {
                    $titleFontRgb = $headerFillRgb
                }
                if (-not $titleFontRgb -and ($titleStyleNode.PSObject.Properties.Name -contains "font_color_rgb") -and $titleStyleNode.font_color_rgb) {
                    $titleFontRgb = [string]$titleStyleNode.font_color_rgb
                }
                $titleColor = Parse-HexColorToCom -Rgb $titleFontRgb
                if ($null -ne $titleColor) {
                    try { $titleBand.Font.Color = $titleColor } catch {}
                    try { $titleCell.Font.Color = $titleColor } catch {}
                }
            }
        }
    }
    if ($TableDescription) {
        $descText = [string]$TableDescription
        if ($AnalysisCaption) {
            $captionText = [string]$AnalysisCaption
            if ($descText) {
                $descText = $descText + "`n`nAnaliza: " + $captionText
            } else {
                $descText = "Analiza: $captionText"
            }
        }
        $descCell = $Worksheet.Cells.Item(2, 1)
        $descCell.Value2 = $descText
        if ($StyleProfile) {
            $academicMode = Get-IsAcademicModeEnabled -StyleProfile $StyleProfile
            $captionStyleNode = if ($academicMode -and $StyleProfile.PSObject.Properties.Name -contains "academic_typography" -and $StyleProfile.academic_typography.PSObject.Properties.Name -contains "caption") `
                                  { $StyleProfile.academic_typography.caption } `
                                elseif ($StyleProfile.PSObject.Properties.Name -contains "axis_labels") { $StyleProfile.axis_labels } else { $null }
            if ($captionStyleNode) {
                if (($captionStyleNode.PSObject.Properties.Name -contains "font_name") -and $captionStyleNode.font_name) { $descCell.Font.Name = [string]$captionStyleNode.font_name }
                if (($captionStyleNode.PSObject.Properties.Name -contains "font_size") -and $null -ne $captionStyleNode.font_size) { $descCell.Font.Size = [double]$captionStyleNode.font_size }
                $descCell.Font.Italic = $true
                if (($captionStyleNode.PSObject.Properties.Name -contains "font_color_rgb") -and $captionStyleNode.font_color_rgb) {
                    $descColor = Parse-HexColorToCom -Rgb ([string]$captionStyleNode.font_color_rgb)
                    if ($null -ne $descColor) { $descCell.Font.Color = $descColor }
                }
            }
        }
    } elseif ($AnalysisCaption) {
        $Worksheet.Cells.Item(2, 1).Value2 = "Analiza: $AnalysisCaption"
    }

    $lastRow = $DataStartRow + $rowsArray.Count - 1
    Apply-TableBodyStyle -Worksheet $Worksheet -HeaderRow $HeaderRow -DataStartRow $DataStartRow -LastRow $lastRow -LastCol $headers.Count -StyleProfile $StyleProfile
    Apply-HeaderStyle -Worksheet $Worksheet -HeaderRow $HeaderRow -LastCol $headers.Count -StyleProfile $StyleProfile -SourceTypeStyle $sourceTypeStyle
    try { $Worksheet.Rows.Item(1).RowHeight = 17.25 } catch {}
    try { $Worksheet.Rows.Item(2).RowHeight = 15.75 } catch {}
    try { $Worksheet.Rows.Item(3).RowHeight = 8.25 } catch {}
    for ($c = 0; $c -lt $headers.Count; $c++) {
        if ([string]::Equals([string]$headers[$c], "date", [System.StringComparison]::OrdinalIgnoreCase)) {
            $dateColumn = $c + 1
            for ($r = $DataStartRow; $r -le $lastRow; $r++) {
                try {
                    $cell = $Worksheet.Cells.Item($r, $dateColumn)
                    $normalized = Try-ParseDateValue -Value $cell.Value2
                    if ($null -ne $normalized) {
                        $cell.Value2 = [double]$normalized.ToOADate()
                    }
                } catch {}
            }
            try { $Worksheet.Columns.Item($dateColumn).NumberFormat = 'dd"."mm"."yyyy' } catch {}
            try { $Worksheet.Columns.Item($dateColumn).NumberFormatLocal = "dd.mm.rrrr" } catch {}
        }
    }
    try {
        if ($lastRow -ge $DataStartRow) {
            $dataRange = $Worksheet.Range($Worksheet.Cells.Item($HeaderRow, 1), $Worksheet.Cells.Item($lastRow, $headers.Count))
            $dataRange.Columns.AutoFit() | Out-Null
        }
    } catch {
        $Worksheet.Columns.AutoFit() | Out-Null
    }
}

function Get-PackTableRows {
    param(
        [Parameter(Mandatory = $true)]$Pack,
        [Parameter(Mandatory = $true)][string]$TableName,
        [Parameter(Mandatory = $true)]$SummaryRows
    )
    if ($TableName -eq "summary") { return @($SummaryRows) }
    $table = $Pack.tables.PSObject.Properties[$TableName]
    if ($null -eq $table) { return @() }
    return @($table.Value)
}

function Get-LayoutEntries {
    param(
        [Parameter(Mandatory = $true)][string]$LayoutSpecJson,
        [Parameter(Mandatory = $true)][string]$LayoutCsv
    )

    if (Test-Path -LiteralPath $LayoutSpecJson) {
        $spec = Get-Content -LiteralPath $LayoutSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($spec.sheets) {
            return @($spec.sheets | Sort-Object { [int]$_.order })
        }
    }

    if (Test-Path -LiteralPath $LayoutCsv) {
        return @(Import-Csv -LiteralPath $LayoutCsv | Sort-Object { [int]$_.order })
    }

    throw "Missing both layout artifacts: $LayoutSpecJson and $LayoutCsv"
}

$paths = Resolve-DefaultPaths
$SourcesPackJson = $paths.SourcesPackJson
$SummaryCsv = $paths.SummaryCsv
$LayoutCsv = $paths.LayoutCsv
$LayoutSpecJson = $paths.LayoutSpecJson
$StyleProfileJson = $paths.StyleProfileJson
$ChartSpecJson = $paths.ChartSpecJson
$OutWorkbook = $paths.OutWorkbook

if (-not (Test-Path -LiteralPath $SourcesPackJson)) { throw "Missing SourcesPackJson: $SourcesPackJson" }
if (-not (Test-Path -LiteralPath $SummaryCsv)) { throw "Missing SummaryCsv: $SummaryCsv" }

$pack = Get-Content -LiteralPath $SourcesPackJson -Raw -Encoding UTF8 | ConvertFrom-Json
$summaryRows = Import-Csv -LiteralPath $SummaryCsv
$layoutEntries = Get-LayoutEntries -LayoutSpecJson $LayoutSpecJson -LayoutCsv $LayoutCsv
$styleProfile = $null
if (Test-Path -LiteralPath $StyleProfileJson) {
    $styleProfile = Get-Content -LiteralPath $StyleProfileJson -Raw -Encoding UTF8 | ConvertFrom-Json
}
$chartSpec = $null
if (Test-Path -LiteralPath $ChartSpecJson) {
    $chartSpec = Get-Content -LiteralPath $ChartSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json
}
$sheetTextByName = @{}
if ($chartSpec -and $chartSpec.charts) {
    foreach ($ch in @($chartSpec.charts)) {
        $sn = [string]$ch.sheet
        if (-not $sn) { continue }
        if (-not $sheetTextByName.ContainsKey($sn)) {
            $sheetTextByName[$sn] = @{
                title = [string]$ch.table_title
                description = [string]$ch.table_description
            }
            if ($ch.PSObject.Properties.Name -contains "analysis_caption" -and $ch.analysis_caption) {
                $sheetTextByName[$sn]["analysis_caption"] = [string]$ch.analysis_caption
            }
        }
    }
}

$outDir = Split-Path -Parent $OutWorkbook
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

$excel = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $excel = New-Object -ComObject Excel.Application
        break
    } catch {
        if ($attempt -eq 3) { throw }
        Start-Sleep -Seconds 2
    }
}
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Add()

    while ($wb.Worksheets.Count -gt 1) {
        $wb.Worksheets.Item(2).Delete()
    }
    $defaultSheet = $wb.Worksheets.Item(1)

    $createdSheets = @{}
    foreach ($entry in $layoutEntries) {
        $name = [string]$entry.sheet_name
        if (-not $name) { continue }
        if ($createdSheets.ContainsKey($name)) { continue }
        $ws = $wb.Worksheets.Add()
        $ws.Name = $name
        $createdSheets[$name] = $ws
    }
    $defaultSheet.Delete()

    foreach ($entry in $layoutEntries) {
        $sheetName = [string]$entry.sheet_name
        if (-not $sheetName) { continue }
        $ws = $wb.Worksheets.Item($sheetName)
        $inputTable = [string]$entry.input_table
        if (-not $inputTable) { $inputTable = $sheetName }

        $headerRow = 1
        $dataStartRow = 2
        $tableTitle = ""
        $tableDescription = ""
        $tableLayout = $null
        if ($entry.PSObject.Properties.Name -contains "table_layout") { $tableLayout = $entry.table_layout }
        if ($tableLayout) {
            if (($tableLayout.PSObject.Properties.Name -contains "header_row") -and $tableLayout.header_row) { $headerRow = [int]$tableLayout.header_row }
            if (($tableLayout.PSObject.Properties.Name -contains "data_start_row") -and $tableLayout.data_start_row) { $dataStartRow = [int]$tableLayout.data_start_row }
            if (($tableLayout.PSObject.Properties.Name -contains "title_row") -and $tableLayout.title_row -and $entry.sheet_title) { $tableTitle = [string]$entry.sheet_title }
            if (($tableLayout.PSObject.Properties.Name -contains "description_row") -and $tableLayout.description_row -and $entry.sheet_description) { $tableDescription = [string]$entry.sheet_description }
        } elseif ($entry.PSObject.Properties.Name -contains "data_start_row") {
            $tmp = [string]$entry.data_start_row
            if ($tmp) {
                $headerRow = [int]$tmp
                $dataStartRow = $headerRow + 1
            }
        }
        $sheetText = $null
        if ($sheetTextByName.ContainsKey($sheetName)) { $sheetText = $sheetTextByName[$sheetName] }
        if (-not $tableTitle -and $sheetText) { $tableTitle = [string]$sheetText["title"] }
        if (-not $tableDescription -and $sheetText) { $tableDescription = [string]$sheetText["description"] }
        $analysisCaption = ""
        if ($sheetText -and ($sheetText.PSObject.Properties.Name -contains "analysis_caption")) {
            $analysisCaption = [string]$sheetText.analysis_caption
        }

        $tableRows = Get-PackTableRows -Pack $pack -TableName $inputTable -SummaryRows $summaryRows
        $tableTransform = $null
        if ($entry.PSObject.Properties.Name -contains "table_transform") { $tableTransform = $entry.table_transform }
        $sourceType = ""
        if ($entry.PSObject.Properties.Name -contains "source_type" -and $null -ne $entry.source_type) {
            $sourceType = $entry.source_type.ToString()
        }
        Write-ObjectsToSheet -Worksheet $ws -Rows $tableRows -HeaderRow $headerRow -DataStartRow $dataStartRow -TableTitle $tableTitle -TableDescription $tableDescription -AnalysisCaption $analysisCaption -SourceType $sourceType -TableTransform $tableTransform -StyleProfile $styleProfile
    }

    $wb.SaveAs($OutWorkbook, 51)
    $wb.Close($true)
    Write-Host "[S03] Workbook created: $OutWorkbook"
    Write-Host "[S03] Sheets created: $($createdSheets.Keys.Count)"
}
finally {
    if ($wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
    $excel.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
