[CmdletBinding()]
param(
    [string]$WorkbookPath = "",
    [string]$ChartSpecJson = "",
    [string]$LayoutSpecJson = "",
    [string]$StyleProfileJson = "",
    [string]$ControlProfileJson = "",
    [string]$OutJson = "",
    [string]$OutMd = ""
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
    if (-not $WorkbookPath) { $WorkbookPath = Join-Path $repoRoot "_external\not_tracked\visualization\workbook_v04.xlsx" }
    if (-not $ChartSpecJson) { $ChartSpecJson = Join-Path $base "inputs\visualization\chart_spec_v04.json" }
    if (-not $LayoutSpecJson) { $LayoutSpecJson = Join-Path $base "inputs\visualization\workbook_layout_v04.json" }
    if (-not $StyleProfileJson) { $StyleProfileJson = Join-Path $base "inputs\visualization\chart_style_profile_v04.json" }
    if (-not $ControlProfileJson) { $ControlProfileJson = Join-Path $base "inputs\visualization\chart_control_profile_v04.json" }
    if (-not $OutJson) { $OutJson = Join-Path $base "products_light\visualization\excel_verify_v04.json" }
    if (-not $OutMd) { $OutMd = Join-Path $base "products_light\visualization\excel_verify_v04.md" }
    return @{
        WorkbookPath = $WorkbookPath
        ChartSpecJson = $ChartSpecJson
        LayoutSpecJson = $LayoutSpecJson
        StyleProfileJson = $StyleProfileJson
        ControlProfileJson = $ControlProfileJson
        OutJson = $OutJson
        OutMd = $OutMd
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

function Get-StyleValidationThresholds {
    param($StyleProfile)
    $warnRatio = 0.9
    $sparseRatio = 0.5
    if ($StyleProfile -and $StyleProfile.validation) {
        if ($StyleProfile.validation.PSObject.Properties.Name -contains "series_nonnull_ratio_warn" -and $StyleProfile.validation.series_nonnull_ratio_warn) {
            $warnRatio = [double]$StyleProfile.validation.series_nonnull_ratio_warn
        }
        if ($StyleProfile.validation.PSObject.Properties.Name -contains "series_nonnull_ratio_sparse" -and $StyleProfile.validation.series_nonnull_ratio_sparse) {
            $sparseRatio = [double]$StyleProfile.validation.series_nonnull_ratio_sparse
        }
    }
    if ($sparseRatio -gt $warnRatio) { $sparseRatio = $warnRatio }
    return @{
        warn_ratio = $warnRatio
        sparse_ratio = $sparseRatio
    }
}

function Get-HeaderCandidates {
    param(
        [string]$HeaderName,
        $StyleProfile
    )
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($HeaderName) {
        $trimmed = [string]$HeaderName
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) { [void]$candidates.Add($trimmed) }
    }
    if ($StyleProfile -and $StyleProfile.column_aliases) {
        $aliases = $StyleProfile.column_aliases
        if ($aliases.PSObject.Properties.Name -contains $HeaderName) {
            $alias = [string]$aliases.$HeaderName
            if (-not [string]::IsNullOrWhiteSpace($alias) -and (-not $candidates.Contains($alias))) {
                [void]$candidates.Add($alias)
            }
        }
        foreach ($prop in @($aliases.PSObject.Properties)) {
            if ([string]$prop.Value -eq $HeaderName) {
                $raw = [string]$prop.Name
                if (-not [string]::IsNullOrWhiteSpace($raw) -and (-not $candidates.Contains($raw))) {
                    [void]$candidates.Add($raw)
                }
            }
        }
    }
    return @($candidates)
}

function Find-HeaderColumnIndex {
    param(
        $Worksheet,
        [int]$HeaderRow,
        [string[]]$Candidates
    )
    if (-not $Worksheet -or -not $Candidates -or @($Candidates).Count -eq 0) { return $null }
    $used = $Worksheet.UsedRange
    $firstCol = [int]$used.Column
    $lastCol = $firstCol + [int]$used.Columns.Count - 1
    for ($col = $firstCol; $col -le $lastCol; $col++) {
        $cellValue = $Worksheet.Cells.Item($HeaderRow, $col).Value2
        if ($null -eq $cellValue) { continue }
        $headerText = [string]$cellValue
        if ([string]::IsNullOrWhiteSpace($headerText)) { continue }
        foreach ($candidate in $Candidates) {
            if ([string]::Equals($headerText.Trim(), ([string]$candidate).Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
                return $col
            }
        }
    }
    return $null
}

function Count-NonEmptyCells {
    param(
        $Worksheet,
        [int]$ColumnIndex,
        [int]$DataStartRow,
        [int]$LastDataRow
    )
    if (-not $Worksheet -or -not $ColumnIndex -or $LastDataRow -lt $DataStartRow) { return 0 }
    $count = 0
    for ($row = $DataStartRow; $row -le $LastDataRow; $row++) {
        $value = $Worksheet.Cells.Item($row, $ColumnIndex).Value2
        if ($null -eq $value) { continue }
        if ($value -is [string] -and [string]::IsNullOrWhiteSpace([string]$value)) { continue }
        $count++
    }
    return $count
}

function Convert-ExcelDateToIso {
    param($Value)
    if ($null -eq $Value) { return "" }
    try {
        if ($Value -is [double] -or $Value -is [int] -or $Value -is [decimal]) {
            return ([DateTime]::FromOADate([double]$Value)).ToString("yyyy-MM-dd")
        }
    } catch {}
    $text = ([string]$Value).Trim()
    if (-not $text) { return "" }
    $parsed = [DateTime]::MinValue
    if ([DateTime]::TryParse($text, [ref]$parsed)) {
        return $parsed.ToString("yyyy-MM-dd")
    }
    if ($text.Length -ge 10) {
        return $text.Substring(0, 10)
    }
    return $text
}

function Convert-ComArrayToList {
    param($Value)
    $items = @()
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            $items += $item
        }
    } else {
        $items = @($Value)
    }
    return @($items)
}

function Get-SeriesHealthStatus {
    param(
        $Worksheet,
        [int]$HeaderRow,
        [int]$DataStartRow,
        [string]$SeriesName,
        [string]$SeriesRole,
        $StyleProfile,
        [double]$WarnRatio,
        [double]$SparseRatio
    )
    $result = [ordered]@{
        series_role = $SeriesRole
        series_name = $SeriesName
        header_candidates = @()
        column_index = $null
        nonnull = 0
        total = 0
        ratio = $null
        status = "source_metric_missing"
        severity = "fail"
    }
    $candidates = Get-HeaderCandidates -HeaderName $SeriesName -StyleProfile $StyleProfile
    $result.header_candidates = $candidates
    $colIndex = Find-HeaderColumnIndex -Worksheet $Worksheet -HeaderRow $HeaderRow -Candidates $candidates
    if ($null -eq $colIndex) {
        return [pscustomobject]$result
    }

    $used = $Worksheet.UsedRange
    $lastDataRow = [int]$used.Row + [int]$used.Rows.Count - 1
    $nonnull = Count-NonEmptyCells -Worksheet $Worksheet -ColumnIndex ([int]$colIndex) -DataStartRow $DataStartRow -LastDataRow $lastDataRow
    $total = 0
    if ($lastDataRow -ge $DataStartRow) { $total = $lastDataRow - $DataStartRow + 1 }

    $result.column_index = [int]$colIndex
    $result.nonnull = $nonnull
    $result.total = $total
    if ($total -le 0) {
        $result.status = "source_no_rows"
        $result.severity = "fail"
        return [pscustomobject]$result
    }
    if ($nonnull -le 0) {
        if ($SeriesName -like "phase_*") {
            $result.status = "series_all_null_background"
            $result.severity = "warn"
        } elseif ($SeriesRole -like "optional*") {
            $result.status = "series_all_null_optional"
            $result.severity = "warn"
        } else {
            $result.status = "series_all_null"
            $result.severity = "fail"
        }
        $result.ratio = 0.0
        return [pscustomobject]$result
    }

    if ($SeriesName -like "phase_*") {
        $result.status = "ok"
        $result.severity = "ok"
        $result.ratio = [math]::Round(([double]$nonnull / [double]$total), 4)
        return [pscustomobject]$result
    }

    $ratio = [double]$nonnull / [double]$total
    $result.ratio = [math]::Round($ratio, 4)
    if ($ratio -lt $SparseRatio) {
        $result.status = "series_too_sparse"
        $result.severity = "warn"
    } elseif ($ratio -lt 1.0) {
        if ($ratio -ge $WarnRatio) {
            $result.status = "series_partial_missing"
            $result.severity = "warn"
        } else {
            $result.status = "series_too_sparse"
            $result.severity = "warn"
        }
    } else {
        $result.status = "ok"
        $result.severity = "ok"
    }
    return [pscustomobject]$result
}

function Get-SecondaryAxisScaleConfig {
    param($ControlProfile)
    if (-not $ControlProfile) { return $null }
    if (($ControlProfile.PSObject.Properties.Name -contains "phase_background") -and $ControlProfile.phase_background) {
        $phaseBackground = $ControlProfile.phase_background
        if (($phaseBackground.PSObject.Properties.Name -contains "secondary_axis_scale") -and $phaseBackground.secondary_axis_scale) {
            return $phaseBackground.secondary_axis_scale
        }
    }
    return $null
}

function Get-DateAxisConfig {
    param($ControlProfile)
    if (-not $ControlProfile) { return $null }
    if (($ControlProfile.PSObject.Properties.Name -contains "date_axis") -and $ControlProfile.date_axis) {
        return $ControlProfile.date_axis
    }
    return $null
}

function Get-CleanSeriesName {
    param($Series)
    if (-not $Series) { return "" }
    $name = ""
    try { $name = [string]$Series.Name } catch { return "" }
    return $name.Trim("=""""")
}

function Get-ChartSeriesDefinitions {
    param($Cfg)
    $defs = @()
    $xField = [string]($Cfg.x_series)
    if ($xField) {
        $defs += [pscustomobject]@{ role = "x"; name = $xField; label = "" }
    }
    if ($Cfg.series_plan) {
        foreach ($item in @($Cfg.series_plan)) {
            if (-not $item) { continue }
            if (($item.PSObject.Properties.Name -contains "hidden") -and $item.hidden -eq $true) { continue }
            if (($item.PSObject.Properties.Name -contains "render") -and $item.render -eq $false) { continue }
            $field = [string]($item.field)
            if (-not $field) { $field = [string]($item.name) }
            if (-not $field) { $field = [string]($item.series) }
            if (-not $field) { continue }
            $role = if ($item.PSObject.Properties.Name -contains "role" -and $item.role) { [string]$item.role } else { "y" }
            $label = if ($item.PSObject.Properties.Name -contains "label" -and $item.label) { [string]$item.label } else { "" }
            $defs += [pscustomobject]@{ role = $role; name = $field; label = $label }
        }
        return @($defs)
    }
    foreach ($yHeader in @($Cfg.y_series)) {
        if (-not $yHeader) { continue }
        $idx = @($Cfg.y_series).IndexOf($yHeader)
        $label = ""
        if ($Cfg.series_labels -and $idx -ge 0 -and $idx -lt @($Cfg.series_labels).Count) {
            $label = [string]@($Cfg.series_labels)[$idx]
        }
        $defs += [pscustomobject]@{ role = "y"; name = [string]$yHeader; label = $label }
    }
    return @($defs)
}

$paths = Resolve-DefaultPaths
$WorkbookPath = $paths.WorkbookPath
$ChartSpecJson = $paths.ChartSpecJson
$LayoutSpecJson = $paths.LayoutSpecJson
$StyleProfileJson = $paths.StyleProfileJson
$OutJson = $paths.OutJson
$OutMd = $paths.OutMd

if (-not (Test-Path -LiteralPath $WorkbookPath)) { throw "Missing workbook: $WorkbookPath" }
if (-not (Test-Path -LiteralPath $ChartSpecJson)) { throw "Missing chart spec: $ChartSpecJson" }

$chartSpec = Get-Content -LiteralPath $ChartSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json
$layoutSpec = $null
if (Test-Path -LiteralPath $LayoutSpecJson) { $layoutSpec = Get-Content -LiteralPath $LayoutSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json }
$styleProfile = $null
if (Test-Path -LiteralPath $StyleProfileJson) { $styleProfile = Get-Content -LiteralPath $StyleProfileJson -Raw -Encoding UTF8 | ConvertFrom-Json }
$controlProfile = $null
if ($ControlProfileJson -and (Test-Path -LiteralPath $ControlProfileJson)) {
    $controlProfile = Get-Content -LiteralPath $ControlProfileJson -Raw -Encoding UTF8 | ConvertFrom-Json
}
$validationThresholds = Get-StyleValidationThresholds -StyleProfile ($(if ($controlProfile) { $controlProfile } else { $styleProfile }))
$warnRatio = [double]$validationThresholds.warn_ratio
$sparseRatio = [double]$validationThresholds.sparse_ratio
$secondaryAxisScale = Get-SecondaryAxisScaleConfig -ControlProfile $controlProfile
$dateAxisScale = Get-DateAxisConfig -ControlProfile $controlProfile

$expectedTitleSize = $null
$expectedLegendSize = $null
$expectedFirstSeriesColor = $null
if ($styleProfile) {
    if ($styleProfile.chart_title -and $styleProfile.chart_title.font_size) { $expectedTitleSize = [double]$styleProfile.chart_title.font_size }
    if ($styleProfile.legend -and $styleProfile.legend.font_size) { $expectedLegendSize = [double]$styleProfile.legend.font_size }
    if ($styleProfile.series_palette_rgb -and @($styleProfile.series_palette_rgb).Count -gt 0) {
        $expectedFirstSeriesColor = Parse-HexColorToCom -Rgb ([string]$styleProfile.series_palette_rgb[0])
    }
}

$inputTableToSheetMap = @{}
$layoutBySheetName = @{}
if ($layoutSpec -and $layoutSpec.sheets) {
    foreach ($s in @($layoutSpec.sheets)) {
        if ($s.sheet_name) { $layoutBySheetName[[string]$s.sheet_name] = $s }
        if ($s.input_table -and $s.sheet_name) {
            $inputTableToSheetMap[[string]$s.input_table] = [string]$s.sheet_name
        }
    }
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $null

try {
    $wb = $excel.Workbooks.Open($WorkbookPath, $false, $true)
    $sheetNames = @()
    foreach ($ws in @($wb.Worksheets)) { $sheetNames += [string]$ws.Name }

    $expectedSheetNames = @()
    if ($layoutSpec -and $layoutSpec.sheets) {
        foreach ($s in @($layoutSpec.sheets)) { $expectedSheetNames += [string]$s.sheet_name }
    }

    $missingSheets = @($expectedSheetNames | Where-Object { $_ -and ($sheetNames -notcontains $_) })

    $chartChecks = @()
    foreach ($cfg in @($chartSpec.charts)) {
        $chartId = [string]$cfg.chart_id
        $targetSheetName = [string]$cfg.sheet
        $sourceSheetName = [string]$cfg.source_sheet
        $seriesDefs = @(Get-ChartSeriesDefinitions -Cfg $cfg)
        $hasSecondarySeries = $false
        if ($cfg.series_plan) {
            foreach ($item in @($cfg.series_plan)) {
                if ($item -and [string]$item.axis_group -eq "secondary") {
                    $hasSecondarySeries = $true
                    break
                }
            }
        }

        $check = [ordered]@{
            chart_id = $chartId
            target_sheet = $targetSheetName
            source_sheet = $sourceSheetName
            source_domain = $null
            source_sheet_exists = $false
            source_sheet_has_rows = $false
            target_sheet_exists = $false
            chart_exists = $false
            series_count = 0
            series_health_status = "not_checked"
            series_health_summary = ""
            series_health = @()
            style_title_font_size_ok = $true
            style_legend_font_size_ok = $true
            style_first_series_color_ok = $true
            secondary_axis_scale_ok = $true
            secondary_axis_min = $null
            secondary_axis_max = $null
            phase_series_axis_group_ok = $true
            phase_series_axis_groups = @()
            chart_type_semantics_ok = $true
            phase_scope_ok = $true
            date_axis_scope_ok = $true
            date_axis_first = $null
            date_axis_last = $null
            date_axis_ok = $true
            date_axis_category_type = $null
            date_axis_number_format = $null
            date_axis_tick_label_spacing = $null
            date_axis_tick_mark_spacing = $null
            source_domain_ok = $false
            input_project_count = $null
            rendered_project_count_expected = $null
            rendered_project_count_ok = $true
            rendered_project_keys_ok = $true
            project_key_label_mode_ok = $true
            project_key_contract_ok = $true
            project_key_values = @()
            style_ok = $true
            quality_severity = "fail"
            status = "missing"
        }

        $resolvedSourceSheet = $sourceSheetName
        $sourceSheet = $null
        try { $sourceSheet = $wb.Worksheets.Item($resolvedSourceSheet) } catch { $sourceSheet = $null }
        if (-not $sourceSheet -and $inputTableToSheetMap.ContainsKey($sourceSheetName)) {
            $resolvedSourceSheet = [string]$inputTableToSheetMap[$sourceSheetName]
            try { $sourceSheet = $wb.Worksheets.Item($resolvedSourceSheet) } catch { $sourceSheet = $null }
        }
        if ($sourceSheet) {
            $check.source_sheet_exists = $true
            $used = $sourceSheet.UsedRange
            $layoutEntry = $null
            if ($layoutBySheetName.ContainsKey($resolvedSourceSheet)) {
                $layoutEntry = $layoutBySheetName[$resolvedSourceSheet]
            } elseif ($layoutBySheetName.ContainsKey($sourceSheetName)) {
                $layoutEntry = $layoutBySheetName[$sourceSheetName]
            }
            $headerRow = 1
            $dataStartRow = 2
            if ($layoutEntry -and $layoutEntry.table_layout) {
                if (($layoutEntry.table_layout.PSObject.Properties.Name -contains "header_row") -and $layoutEntry.table_layout.header_row) {
                    $headerRow = [int]$layoutEntry.table_layout.header_row
                }
                if (($layoutEntry.table_layout.PSObject.Properties.Name -contains "data_start_row") -and $layoutEntry.table_layout.data_start_row) {
                    $dataStartRow = [int]$layoutEntry.table_layout.data_start_row
                }
            }
            $lastDataRow = [int]$used.Row + [int]$used.Rows.Count - 1
            if ($lastDataRow -ge $dataStartRow) { $check.source_sheet_has_rows = $true }

            $seriesHealth = @()
            foreach ($def in $seriesDefs) {
                $health = Get-SeriesHealthStatus -Worksheet $sourceSheet -HeaderRow $headerRow -DataStartRow $dataStartRow -SeriesName ([string]$def.name) -SeriesRole ([string]$def.role) -StyleProfile $styleProfile -WarnRatio $warnRatio -SparseRatio $sparseRatio
                $seriesHealth += $health
            }
            if ($seriesHealth.Count -gt 0) {
                $check.series_health = @($seriesHealth)
                $summaryParts = @()
                foreach ($h in $seriesHealth) {
                    $ratioText = if ($null -ne $h.ratio) { ";ratio=$([string]$h.ratio)" } else { "" }
                    $summaryParts += "$($h.series_role):$($h.series_name)=$($h.status)[nonnull=$($h.nonnull);total=$($h.total)$ratioText]"
                }
                $check.series_health_summary = ($summaryParts -join "; ")
                $statuses = @($seriesHealth | ForEach-Object { [string]$_.status })
                if ($statuses -contains "source_metric_missing") {
                    $check.series_health_status = "source_metric_missing"
                } elseif ($statuses -contains "series_all_null") {
                    $check.series_health_status = "series_all_null"
                } elseif ($statuses -contains "series_too_sparse") {
                    $check.series_health_status = "series_too_sparse"
                } elseif ($statuses -contains "series_all_null_background") {
                    $check.series_health_status = "series_all_null_background"
                } elseif ($statuses -contains "series_all_null_optional") {
                    $check.series_health_status = "series_all_null_optional"
                } elseif ($statuses -contains "series_partial_missing") {
                    $check.series_health_status = "series_partial_missing"
                } else {
                    $check.series_health_status = "ok"
                }
            }

            if (($cfg.PSObject.Properties.Name -contains "source_domain") -and $cfg.source_domain) {
                $check.source_domain = [string]$cfg.source_domain
                if ($cfg.table_description -and ([string]$cfg.table_description).StartsWith("Zrodlo:")) {
                    $check.source_domain_ok = ([string]$cfg.table_description -like ("Zrodlo: " + [string]$cfg.source_domain + "*"))
                } else {
                    $check.source_domain_ok = $false
                }
            } else {
                $check.source_domain_ok = $false
            }
            if (($cfg.PSObject.Properties.Name -contains "input_project_count") -and $null -ne $cfg.input_project_count) {
                $check.input_project_count = [int]$cfg.input_project_count
            }
            if (($cfg.PSObject.Properties.Name -contains "rendered_project_count") -and $null -ne $cfg.rendered_project_count) {
                $check.rendered_project_count_expected = [int]$cfg.rendered_project_count
            }

            $projectKeyColumn = $null
            try {
                $projectKeyColumn = Find-HeaderColumnIndex -Worksheet $sourceSheet -HeaderRow $headerRow -Candidates (Get-HeaderCandidates -HeaderName "project_key" -StyleProfile $styleProfile)
            } catch {
                $projectKeyColumn = $null
            }
            if ($projectKeyColumn) {
                $used = $sourceSheet.UsedRange
                $lastDataRow = [int]$used.Row + [int]$used.Rows.Count - 1
                $projectKeys = New-Object System.Collections.Generic.List[string]
                for ($row = $dataStartRow; $row -le $lastDataRow; $row++) {
                    $value = $sourceSheet.Cells.Item($row, [int]$projectKeyColumn).Value2
                    if ($null -eq $value) { continue }
                    $text = [string]$value
                    if ([string]::IsNullOrWhiteSpace($text)) { continue }
                    if (-not $projectKeys.Contains($text)) {
                        [void]$projectKeys.Add($text.Trim())
                    }
                }
                $check.project_key_values = @($projectKeys)
                if (($cfg.PSObject.Properties.Name -contains "rendered_project_keys") -and $cfg.rendered_project_keys) {
                    $expectedKeys = @($cfg.rendered_project_keys)
                    $check.rendered_project_count_ok = ($projectKeys.Count -eq $expectedKeys.Count)
                    $projectKeyListOk = ($projectKeys.Count -eq $expectedKeys.Count)
                    if ($projectKeyListOk) {
                        for ($i = 0; $i -lt $expectedKeys.Count; $i++) {
                            if (-not [string]::Equals([string]$projectKeys[$i], [string]$expectedKeys[$i], [System.StringComparison]::OrdinalIgnoreCase)) {
                                $projectKeyListOk = $false
                                break
                            }
                        }
                    }
                    $check.rendered_project_keys_ok = $projectKeyListOk
                }
                if (($cfg.PSObject.Properties.Name -contains "project_key_label_mode") -and $cfg.project_key_label_mode) {
                    $check.project_key_label_mode_ok = ([string]$cfg.project_key_label_mode -eq "full")
                }
            } elseif (($cfg.PSObject.Properties.Name -contains "rendered_project_keys") -and $cfg.rendered_project_keys) {
                $check.rendered_project_keys_ok = $false
                $check.rendered_project_count_ok = $false
            }
            $check.project_key_contract_ok = ($check.rendered_project_count_ok -and $check.rendered_project_keys_ok -and $check.project_key_label_mode_ok)
        }

        $targetSheet = $null
        try { $targetSheet = $wb.Worksheets.Item($targetSheetName) } catch { $targetSheet = $null }
        if ($targetSheet) { $check.target_sheet_exists = $true }

        if ($targetSheet) {
            $chartObj = $null
            try { $chartObj = $targetSheet.ChartObjects($chartId) } catch { $chartObj = $null }
            if ($chartObj) {
                $check.chart_exists = $true
                $check.series_count = [int]$chartObj.Chart.SeriesCollection().Count

                if ($null -ne $expectedTitleSize -and $chartObj.Chart.HasTitle) {
                    $check.style_title_font_size_ok = ([math]::Abs([double]$chartObj.Chart.ChartTitle.Font.Size - $expectedTitleSize) -lt 0.01)
                }
                if ($null -ne $expectedLegendSize -and $chartObj.Chart.HasLegend) {
                    $check.style_legend_font_size_ok = ([math]::Abs([double]$chartObj.Chart.Legend.Font.Size - $expectedLegendSize) -lt 0.01)
                }
                if ($null -ne $expectedFirstSeriesColor -and $check.series_count -gt 0) {
                    $seriesObj = $chartObj.Chart.SeriesCollection(1)
                    $actualFillColor = $null
                    $actualLineColor = $null
                    try { $actualFillColor = [int]$seriesObj.Format.Fill.ForeColor.RGB } catch {}
                    try { $actualLineColor = [int]$seriesObj.Format.Line.ForeColor.RGB } catch {}
                    $check.style_first_series_color_ok = (($actualFillColor -eq $expectedFirstSeriesColor) -or ($actualLineColor -eq $expectedFirstSeriesColor))
                }
                if ($hasSecondarySeries -and $chartObj.Chart.ChartType) {
                    $expectedMin = 0.0
                    $expectedMax = 100.0
                    if ($secondaryAxisScale) {
                        if (($secondaryAxisScale.PSObject.Properties.Name -contains "minimum") -and $null -ne $secondaryAxisScale.minimum) {
                            $expectedMin = [double]$secondaryAxisScale.minimum
                        }
                        if (($secondaryAxisScale.PSObject.Properties.Name -contains "maximum") -and $null -ne $secondaryAxisScale.maximum) {
                            $expectedMax = [double]$secondaryAxisScale.maximum
                        }
                    }
                    try {
                        $secondaryAxis = $chartObj.Chart.Axes(2, 2)
                        if ($secondaryAxis) {
                            $check.secondary_axis_min = [double]$secondaryAxis.MinimumScale
                            $check.secondary_axis_max = [double]$secondaryAxis.MaximumScale
                            $minOk = ([math]::Abs([double]$secondaryAxis.MinimumScale - $expectedMin) -lt 0.01)
                            $maxOk = ([math]::Abs([double]$secondaryAxis.MaximumScale - $expectedMax) -lt 0.01)
                            $check.secondary_axis_scale_ok = ($minOk -and $maxOk)
                        } else {
                            $check.secondary_axis_scale_ok = $false
                        }
                    } catch {
                        $check.secondary_axis_scale_ok = $false
                    }
                }
                $phaseLabels = New-Object System.Collections.Generic.List[string]
                if ($cfg.series_plan) {
                    foreach ($item in @($cfg.series_plan)) {
                        if ($item -and [string]$item.field -like "phase_*") {
                            $label = if (($item.PSObject.Properties.Name -contains "label") -and $item.label) { [string]$item.label } else { [string]$item.field }
                            if (-not $phaseLabels.Contains($label)) { [void]$phaseLabels.Add($label) }
                        }
                    }
                }
                if ($phaseLabels.Count -gt 0) {
                    $phaseAxisEntries = @()
                    try {
                        for ($seriesIdx = 1; $seriesIdx -le [int]$chartObj.Chart.SeriesCollection().Count; $seriesIdx++) {
                            $seriesObj = $chartObj.Chart.SeriesCollection($seriesIdx)
                            $cleanName = Get-CleanSeriesName -Series $seriesObj
                            if ($phaseLabels.Contains($cleanName)) {
                                $axisGroup = $null
                                try { $axisGroup = [int]$seriesObj.AxisGroup } catch {}
                                $phaseAxisEntries += [pscustomobject]@{
                                    series_name = $cleanName
                                    axis_group = $axisGroup
                                }
                                if ($axisGroup -ne 2) {
                                    $check.phase_series_axis_group_ok = $false
                                }
                            }
                        }
                    } catch {
                        $check.phase_series_axis_group_ok = $false
                    }
                    $check.phase_series_axis_groups = @($phaseAxisEntries)
                    if ($phaseAxisEntries.Count -ne $phaseLabels.Count) {
                        $check.phase_series_axis_group_ok = $false
                    }
                }
                if ($cfg.series_plan) {
                    $declaredActivePhases = @()
                    if (($cfg.PSObject.Properties.Name -contains "active_phase_fields") -and $cfg.active_phase_fields) {
                        $declaredActivePhases = @($cfg.active_phase_fields | ForEach-Object { [string]$_ })
                    }
                    $renderedPhaseFields = @()
                    foreach ($item in @($cfg.series_plan)) {
                        if (-not $item) { continue }
                        $fieldName = [string]$item.field
                        if ($fieldName -like "phase_*") {
                            $renderedPhaseFields += $fieldName
                            continue
                        }
                        if (($item.PSObject.Properties.Name -contains "metric_semantics") -and $item.metric_semantics) {
                            $semantics = [string]$item.metric_semantics
                            $seriesChartType = if (($item.PSObject.Properties.Name -contains "chart_type") -and $item.chart_type) { [string]$item.chart_type } else { "" }
                            if (($semantics -eq "daily_event" -or $semantics -eq "sparse_event") -and $seriesChartType -eq "line") {
                                $check.chart_type_semantics_ok = $false
                            }
                        }
                    }
                    if ($declaredActivePhases.Count -gt 0) {
                        if ($renderedPhaseFields.Count -ne $declaredActivePhases.Count) {
                            $check.phase_scope_ok = $false
                        } else {
                            for ($phaseIdx = 0; $phaseIdx -lt $declaredActivePhases.Count; $phaseIdx++) {
                                if ([string]$renderedPhaseFields[$phaseIdx] -ne [string]$declaredActivePhases[$phaseIdx]) {
                                    $check.phase_scope_ok = $false
                                    break
                                }
                            }
                        }
                    }
                    if (($cfg.PSObject.Properties.Name -contains "phase_scope_mode") -and $cfg.phase_scope_mode) {
                        $phaseScopeMode = [string]$cfg.phase_scope_mode
                        if ($phaseScopeMode -eq "declared_phase_only" -and ($renderedPhaseFields.Count -ne 1)) {
                            $check.phase_scope_ok = $false
                        }
                    }
                }
                if (
                    ($cfg.PSObject.Properties.Name -contains "x_axis_scope_mode") -and
                    $cfg.x_axis_scope_mode -and
                    [string]$cfg.x_axis_scope_mode -ne "full_source"
                ) {
                    $expectedAxisStart = if (($cfg.PSObject.Properties.Name -contains "x_axis_start") -and $cfg.x_axis_start) { [string]$cfg.x_axis_start } else { "" }
                    $expectedAxisEnd = if (($cfg.PSObject.Properties.Name -contains "x_axis_end") -and $cfg.x_axis_end) { [string]$cfg.x_axis_end } else { "" }
                    try {
                        $firstSeries = $null
                        for ($seriesIdx = 1; $seriesIdx -le [int]$chartObj.Chart.SeriesCollection().Count; $seriesIdx++) {
                            $candidate = $chartObj.Chart.SeriesCollection($seriesIdx)
                            $xValues = Convert-ComArrayToList -Value $candidate.XValues
                            if ($xValues.Count -gt 0) {
                                $firstSeries = $candidate
                                break
                            }
                        }
                        if ($firstSeries) {
                            $xValues = Convert-ComArrayToList -Value $firstSeries.XValues
                            if ($xValues.Count -gt 0) {
                                $firstDate = Convert-ExcelDateToIso -Value $xValues[0]
                                $lastDate = Convert-ExcelDateToIso -Value $xValues[$xValues.Count - 1]
                                $check.date_axis_first = $firstDate
                                $check.date_axis_last = $lastDate
                                if ($expectedAxisStart -and $firstDate -ne $expectedAxisStart) {
                                    $check.date_axis_scope_ok = $false
                                }
                                if ($expectedAxisEnd -and $lastDate -ne $expectedAxisEnd) {
                                    $check.date_axis_scope_ok = $false
                                }
                            } else {
                                $check.date_axis_scope_ok = $false
                            }
                        } else {
                            $check.date_axis_scope_ok = $false
                        }
                    } catch {
                        $check.date_axis_scope_ok = $false
                    }
                }
                if ([string]$cfg.x_series -like "date*" -and $dateAxisScale) {
                    try {
                        $categoryAxis = $chartObj.Chart.Axes(1)
                        if ($categoryAxis) {
                            try { $check.date_axis_category_type = [int]$categoryAxis.CategoryType } catch {}
                            $check.date_axis_tick_label_spacing = [int]$categoryAxis.TickLabelSpacing
                            try { $check.date_axis_tick_mark_spacing = [int]$categoryAxis.TickMarkSpacing } catch {}
                            try { $check.date_axis_number_format = [string]$categoryAxis.TickLabels.NumberFormat } catch {}
                            $check.date_axis_ok = (
                                ([int]$check.date_axis_category_type -eq 2) -and
                                ([int]$check.date_axis_tick_label_spacing -eq 7) -and
                                ([int]$check.date_axis_tick_mark_spacing -eq 7) -and
                                ([string]::Equals([string]$check.date_axis_number_format, "mm-dd", [System.StringComparison]::OrdinalIgnoreCase))
                            )
                        } else {
                            $check.date_axis_ok = $false
                        }
                    } catch {
                        $check.date_axis_ok = $false
                    }
                }
            }
        }

        $styleOk = ($check.style_title_font_size_ok -and $check.style_legend_font_size_ok -and $check.style_first_series_color_ok -and $check.secondary_axis_scale_ok -and $check.phase_series_axis_group_ok -and $check.chart_type_semantics_ok -and $check.phase_scope_ok -and $check.date_axis_scope_ok -and $check.date_axis_ok)
        $metadataOk = ($check.source_domain_ok -and $check.project_key_contract_ok)
        $check.style_ok = $styleOk
        if ($check.source_sheet_exists -and $check.source_sheet_has_rows -and $check.target_sheet_exists -and $check.chart_exists -and $check.series_count -gt 0 -and $check.series_health_status -eq "ok" -and $styleOk -and $metadataOk) {
            $check.status = "ok"
            $check.quality_severity = "ok"
        } elseif (-not $check.chart_exists) {
            $check.status = "missing_chart"
            $check.quality_severity = "fail"
        } elseif (-not $check.source_sheet_exists) {
            $check.status = "missing_source_sheet"
            $check.quality_severity = "fail"
        } elseif (-not $check.target_sheet_exists) {
            $check.status = "missing_target_sheet"
            $check.quality_severity = "fail"
        } elseif (-not $check.source_sheet_has_rows) {
            $check.status = "source_no_rows"
            $check.quality_severity = "fail"
        } elseif ($check.series_health_status -ne "ok") {
            $check.status = $check.series_health_status
            if (($check.series_health_status -eq "series_partial_missing" -or $check.series_health_status -eq "series_too_sparse" -or $check.series_health_status -eq "series_all_null_background" -or $check.series_health_status -eq "series_all_null_optional") -and $styleOk) {
                $check.quality_severity = "warn"
            } else {
                $check.quality_severity = "fail"
            }
        } elseif ($check.series_count -eq 0) {
            $check.status = "chart_empty_series"
            $check.quality_severity = "fail"
        } elseif (-not $styleOk) {
            $check.status = "style_mismatch"
            $check.quality_severity = "fail"
        } elseif (-not $metadataOk) {
            $check.status = "metadata_mismatch"
            $check.quality_severity = "fail"
        } else {
            $check.status = "style_mismatch"
            $check.quality_severity = "fail"
        }

        $chartChecks += [pscustomobject]$check
    }

    $warned = @($chartChecks | Where-Object { $_.quality_severity -eq "warn" })
    $failed = @($chartChecks | Where-Object { $_.quality_severity -eq "fail" -and $_.status -ne "ok" })
    $payload = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        workbook_path = $WorkbookPath
        chart_spec_path = $ChartSpecJson
        layout_spec_path = $LayoutSpecJson
        style_profile_path = $StyleProfileJson
        sheets = $sheetNames
        expected_sheet_count = $(if ($layoutSpec -and $layoutSpec.sheet_count_target) { [int]$layoutSpec.sheet_count_target } else { $null })
        actual_sheet_count = $sheetNames.Count
        expected_sheets_present = ($missingSheets.Count -eq 0)
        missing_sheets = $missingSheets
        chart_checks = $chartChecks
        totals = @{
            charts_spec = @($chartChecks).Count
            charts_ok = @($chartChecks | Where-Object { $_.status -eq "ok" }).Count
            charts_warn = $warned.Count
            charts_failed = $failed.Count
            missing_sheets = $missingSheets.Count
        }
    }

    $outDir = Split-Path -Parent $OutJson
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }

    $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutJson -Encoding UTF8

    $md = @()
    $reportLabel = [System.IO.Path]::GetFileNameWithoutExtension($OutMd)
    if (-not $reportLabel) { $reportLabel = "excel_verify" }
    $md += "# Excel Verify $reportLabel"
    $md += ""
    $md += "- generated_at: $($payload.generated_at)"
    $md += "- workbook: $WorkbookPath"
    $md += "- sheets: $($payload.actual_sheet_count)"
    $md += "- charts_ok: $($payload.totals.charts_ok) / $($payload.totals.charts_spec)"
    $md += "- charts_warn: $($payload.totals.charts_warn)"
    $md += "- charts_failed: $($payload.totals.charts_failed)"
    $md += ""
    if ($missingSheets.Count -gt 0) {
        $md += "## Missing sheets"
        foreach ($s in $missingSheets) { $md += "- $s" }
        $md += ""
    }
    $md += "| chart_id | status | severity | series_count | target_sheet | source_sheet | series_health_status |"
    $md += "|---|---|---|---:|---|---|---|"
    foreach ($row in $chartChecks) {
    $md += "| $($row.chart_id) | $($row.status) | $($row.quality_severity) | $($row.series_count) | $($row.target_sheet) | $($row.source_sheet) | $($row.series_health_status) |"
    }
    $md -join "`n" | Set-Content -LiteralPath $OutMd -Encoding UTF8

    $wb.Close($false)
    Write-Host "[S08] Verify JSON: $OutJson"
    Write-Host "[S08] Verify MD:   $OutMd"
    Write-Host "[S08] Charts OK:   $($payload.totals.charts_ok)/$($payload.totals.charts_spec)"
    Write-Host "[S08] Sheets:      $($payload.actual_sheet_count)"
    if ($payload.totals.charts_failed -gt 0 -or -not $payload.expected_sheets_present) {
        exit 1
    }
}
finally {
    if ($null -ne $wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
    $excel.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
