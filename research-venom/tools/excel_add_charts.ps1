[CmdletBinding()]
param(
    [string]$WorkbookPath = "",
    [string]$ChartSpecJson = "",
    [string]$LayoutSpecJson = "",
    [string]$StyleProfileJson = "",
    [string]$ControlProfileJson = ""
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
    return @{
        WorkbookPath = $WorkbookPath
        ChartSpecJson = $ChartSpecJson
        LayoutSpecJson = $LayoutSpecJson
        StyleProfileJson = $StyleProfileJson
        ControlProfileJson = $ControlProfileJson
    }
}

function Get-ColumnIndexByHeader {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][string]$Header,
        [int]$HeaderRow = 1,
        $StyleProfile
    )
    $acceptedHeaders = @($Header.Trim())
    if ($StyleProfile -and $StyleProfile.column_aliases) {
        $aliasProp = $StyleProfile.column_aliases.PSObject.Properties[$Header]
        if ($null -ne $aliasProp -and $aliasProp.Value) {
            $acceptedHeaders += ([string]$aliasProp.Value).Trim()
        }
    }
    $usedCols = $Worksheet.UsedRange.Columns.Count
    for ($c = 1; $c -le $usedCols; $c++) {
        $value = [string]$Worksheet.Cells.Item($HeaderRow, $c).Value2
        if ($acceptedHeaders -contains $value.Trim()) {
            return $c
        }
    }
    return -1
}

function Get-LastDataRow {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [int]$HeaderRow = 1
    )
    $xlUp = -4162
    $last = $Worksheet.Cells.Item($Worksheet.Rows.Count, 1).End($xlUp).Row
    if ($last -lt ($HeaderRow + 1)) {
        $last = $Worksheet.UsedRange.Rows.Count
    }
    return [int]$last
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

function Get-ScopedDataRowBounds {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        $ChartCfg,
        [int]$XColumn,
        [int]$DataStartRow,
        [int]$LastDataRow
    )
    $startRow = $DataStartRow
    $endRow = $LastDataRow
    if (-not $ChartCfg -or $XColumn -lt 1 -or $LastDataRow -lt $DataStartRow) {
        return @{ StartRow = $startRow; EndRow = $endRow }
    }
    $scopeMode = ""
    if ($ChartCfg.PSObject.Properties.Name -contains "x_axis_scope_mode" -and $ChartCfg.x_axis_scope_mode) {
        $scopeMode = [string]$ChartCfg.x_axis_scope_mode
    }
    if (-not $scopeMode -or $scopeMode -eq "full_source") {
        return @{ StartRow = $startRow; EndRow = $endRow }
    }
    $minDate = ""
    $maxDate = ""
    if ($ChartCfg.PSObject.Properties.Name -contains "x_axis_start" -and $ChartCfg.x_axis_start) {
        $minDate = [string]$ChartCfg.x_axis_start
    }
    if ($ChartCfg.PSObject.Properties.Name -contains "x_axis_end" -and $ChartCfg.x_axis_end) {
        $maxDate = [string]$ChartCfg.x_axis_end
    }
    if (-not $minDate -and -not $maxDate) {
        return @{ StartRow = $startRow; EndRow = $endRow }
    }

    $foundStart = 0
    $foundEnd = 0
    for ($row = $DataStartRow; $row -le $LastDataRow; $row++) {
        $cellDate = Convert-ExcelDateToIso -Value $Worksheet.Cells.Item($row, $XColumn).Value2
        if (-not $cellDate) { continue }
        if ($minDate -and [string]::CompareOrdinal($cellDate, $minDate) -lt 0) { continue }
        if ($maxDate -and [string]::CompareOrdinal($cellDate, $maxDate) -gt 0) { continue }
        if ($foundStart -eq 0) { $foundStart = $row }
        $foundEnd = $row
    }
    if ($foundStart -gt 0 -and $foundEnd -ge $foundStart) {
        return @{ StartRow = [int]$foundStart; EndRow = [int]$foundEnd }
    }
    return @{ StartRow = $startRow; EndRow = $endRow }
}

function Get-ChartTypeCode {
    param([string]$Type)
    switch ($Type) {
        "area" { return 1 }
        "area_stacked" { return 76 }
        "area_100" { return 77 }
        "line" { return 4 }
        "combo" { return 4 }
        "bar_horizontal" { return 57 }
        "bar_clustered" { return 57 }
        "bar_stacked" { return 58 }
        "bar_100" { return 59 }
        "column" { return 51 }
        default { return 4 }
    }
}

function Is-HorizontalBarChart {
    param([string]$Type)
    return $Type -eq "bar_horizontal" -or $Type -eq "bar_stacked" -or $Type -eq "bar_100"
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

function Get-PhaseSeriesLabels {
    param($ChartCfg)
    $labels = New-Object System.Collections.Generic.List[string]
    if (-not $ChartCfg -or -not $ChartCfg.series_plan) { return @($labels) }
    foreach ($plan in @($ChartCfg.series_plan)) {
        if (-not $plan) { continue }
        if ([string]$plan.field -notlike "phase_*") { continue }
        $label = if (($plan.PSObject.Properties.Name -contains "label") -and $plan.label) { [string]$plan.label } else { [string]$plan.field }
        if (-not $labels.Contains($label)) { [void]$labels.Add($label) }
    }
    return @($labels)
}

function Enforce-PhaseSeriesAsSecondaryColumns {
    param(
        $Chart,
        $ChartCfg
    )
    if (-not $Chart -or -not $ChartCfg) { return }
    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    if ($phaseLabels.Count -eq 0) { return }
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $series = $Chart.SeriesCollection($i)
            $seriesName = Get-CleanSeriesName -Series $series
            if ($phaseLabels -notcontains $seriesName) { continue }
            try { $series.ChartType = (Get-ChartTypeCode -Type "column") } catch {}
            try { $series.AxisGroup = 2 } catch {}
        }
    } catch {}
}

function Convert-TimeUnitToCom {
    param([string]$Value)
    switch (($Value | ForEach-Object { [string]$_ }).Trim().ToLowerInvariant()) {
        "days" { return 0 }
        "day" { return 0 }
        "months" { return 1 }
        "month" { return 1 }
        "years" { return 2 }
        "year" { return 2 }
        default { return 0 }
    }
}

function Apply-SecondaryAxisScale {
    param(
        $Chart,
        $ScaleConfig
    )
    if (-not $Chart -or -not $ScaleConfig) { return }
    try {
        $axis = $Chart.Axes(2, 2)
        if (-not $axis) { return }
        if (($ScaleConfig.PSObject.Properties.Name -contains "minimum") -and $null -ne $ScaleConfig.minimum) {
            $axis.MinimumScale = [double]$ScaleConfig.minimum
            try { $axis.MinimumScaleIsAuto = $false } catch {}
        }
        if (($ScaleConfig.PSObject.Properties.Name -contains "maximum") -and $null -ne $ScaleConfig.maximum) {
            $axis.MaximumScale = [double]$ScaleConfig.maximum
            try { $axis.MaximumScaleIsAuto = $false } catch {}
        }
        if (($ScaleConfig.PSObject.Properties.Name -contains "major_unit") -and $null -ne $ScaleConfig.major_unit) {
            $axis.MajorUnit = [double]$ScaleConfig.major_unit
            try { $axis.MajorUnitIsAuto = $false } catch {}
        }
        if (($ScaleConfig.PSObject.Properties.Name -contains "minimum_is_auto") -and $ScaleConfig.minimum_is_auto -eq $false) {
            try { $axis.MinimumScaleIsAuto = $false } catch {}
        }
        if (($ScaleConfig.PSObject.Properties.Name -contains "maximum_is_auto") -and $ScaleConfig.maximum_is_auto -eq $false) {
            try { $axis.MaximumScaleIsAuto = $false } catch {}
        }
        if (($ScaleConfig.PSObject.Properties.Name -contains "major_unit_is_auto") -and $ScaleConfig.major_unit_is_auto -eq $false) {
            try { $axis.MajorUnitIsAuto = $false } catch {}
        }
        if (($ScaleConfig.PSObject.Properties.Name -contains "crosses_at") -and $null -ne $ScaleConfig.crosses_at) {
            try { $axis.CrossesAt = [double]$ScaleConfig.crosses_at } catch {}
        }
    } catch {}
}

function Apply-DateAxisScale {
    param(
        $Chart,
        $ScaleConfig
    )
    if (-not $Chart -or -not $ScaleConfig) { return }
    try {
        $axis = $Chart.Axes(1)
        if (-not $axis) { return }
        try {
            $axis.CategoryType = 2
        } catch {}
        if (($ScaleConfig.PSObject.Properties.Name -contains "tick_label_spacing") -and $null -ne $ScaleConfig.tick_label_spacing) {
            try { $axis.TickLabelSpacing = [int]$ScaleConfig.tick_label_spacing } catch {}
            try { $axis.TickLabelSpacingIsAuto = $false } catch {}
        }
        if (($ScaleConfig.PSObject.Properties.Name -contains "tick_mark_spacing") -and $null -ne $ScaleConfig.tick_mark_spacing) {
            try { $axis.TickMarkSpacing = [int]$ScaleConfig.tick_mark_spacing } catch {}
            try { $axis.TickMarkSpacingIsAuto = $false } catch {}
        }
        if (($ScaleConfig.PSObject.Properties.Name -contains "number_format") -and $ScaleConfig.number_format) {
            try { $axis.TickLabels.NumberFormat = [string]$ScaleConfig.number_format } catch {}
        }
    } catch {}
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

function Resolve-SeriesLabel {
    param(
        [string]$Label,
        [string]$FallbackHeader
    )
    if ($Label -and $Label.Trim()) {
        return $Label.Trim()
    }
    return $FallbackHeader
}

function Get-SeriesPlanEntries {
    param(
        $ChartCfg,
        $ControlProfile
    )
    $entries = @()
    $defaultSeriesType = ""
    $defaultAxisGroup = "primary"
    if ($ControlProfile -and $ControlProfile.series_plan_defaults) {
        if (($ControlProfile.series_plan_defaults.PSObject.Properties.Name -contains "chart_type") -and $ControlProfile.series_plan_defaults.chart_type) {
            $defaultSeriesType = [string]$ControlProfile.series_plan_defaults.chart_type
        }
        if (($ControlProfile.series_plan_defaults.PSObject.Properties.Name -contains "axis_group") -and $ControlProfile.series_plan_defaults.axis_group) {
            $defaultAxisGroup = [string]$ControlProfile.series_plan_defaults.axis_group
        }
    }
    if ($ChartCfg.series_plan) {
        foreach ($item in @($ChartCfg.series_plan)) {
            if (-not $item) { continue }
            if (($item.PSObject.Properties.Name -contains "hidden") -and $item.hidden -eq $true) { continue }
            if (($item.PSObject.Properties.Name -contains "render") -and $item.render -eq $false) { continue }
            $field = [string]($item.field)
            if (-not $field) { $field = [string]($item.name) }
            if (-not $field) { $field = [string]($item.series) }
            if (-not $field) { continue }
            $label = if ($item.PSObject.Properties.Name -contains "label" -and $item.label) { [string]$item.label } else { "" }
            $chartType = if ($item.PSObject.Properties.Name -contains "chart_type" -and $item.chart_type) { [string]$item.chart_type } elseif ($defaultSeriesType) { $defaultSeriesType } else { "" }
            $axisGroup = if ($item.PSObject.Properties.Name -contains "axis_group" -and $item.axis_group) { [string]$item.axis_group } else { $defaultAxisGroup }
            $render = if ($item.PSObject.Properties.Name -contains "render") { [bool]$item.render } else { $true }
            $entries += [pscustomobject]@{
                role = if ($item.PSObject.Properties.Name -contains "role" -and $item.role) { [string]$item.role } else { "y" }
                field = $field
                label = $label
                chart_type = $chartType
                axis_group = $axisGroup
                render = $render
            }
        }
        return @($entries)
    }

    $yHeaders = @($ChartCfg.y_series)
    $seriesLabels = @($ChartCfg.series_labels)
    for ($i = 0; $i -lt $yHeaders.Count; $i++) {
        $yHeader = [string]$yHeaders[$i]
        if (-not $yHeader) { continue }
        $seriesLabel = if ($i -lt $seriesLabels.Count) { [string]$seriesLabels[$i] } else { "" }
        $entries += [pscustomobject]@{
            role = "y"
            field = $yHeader
            label = $seriesLabel
            chart_type = ""
            axis_group = "primary"
            render = $true
        }
    }
    return @($entries)
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

function Apply-TextStyle {
    param(
        $FontObject,
        $StyleNode
    )
    if (-not $FontObject -or -not $StyleNode) { return }
    if ($StyleNode.font_name) { $FontObject.Name = [string]$StyleNode.font_name }
    if ($StyleNode.font_size) { $FontObject.Size = [double]$StyleNode.font_size }
    if ($StyleNode.PSObject.Properties.Name -contains "bold") { $FontObject.Bold = [bool]$StyleNode.bold }
    if ($StyleNode.PSObject.Properties.Name -contains "italic") { $FontObject.Italic = [bool]$StyleNode.italic }
    if ($StyleNode.font_color_rgb) {
        $c = Parse-HexColorToCom -Rgb ([string]$StyleNode.font_color_rgb)
        if ($null -ne $c) { $FontObject.Color = $c }
    }
}

function Apply-ChartStyle {
    param(
        $Chart,
        $ChartCfg,
        $StyleProfile
    )

    if (-not $StyleProfile) { return }

    if ($Chart.HasTitle -and $StyleProfile.chart_title) {
        Apply-TextStyle -FontObject $Chart.ChartTitle.Font -StyleNode $StyleProfile.chart_title
    }

    if ($Chart.HasLegend -and $StyleProfile.legend) {
        Apply-TextStyle -FontObject $Chart.Legend.Font -StyleNode $StyleProfile.legend
        $legendPosition = [string]$ChartCfg.legend_position
        if (-not $legendPosition) { $legendPosition = [string]$StyleProfile.legend.position }
        switch ($legendPosition) {
            "none" { $Chart.HasLegend = $false }
            "left" { $Chart.Legend.Position = -4131 }
            "top" { $Chart.Legend.Position = -4160 }
            "bottom" { $Chart.Legend.Position = -4107 }
            default { $Chart.Legend.Position = -4152 }
        }
    }

    if ($StyleProfile.plot) {
        $chartAreaColor = Parse-HexColorToCom -Rgb ([string]$StyleProfile.plot.chart_area_fill_rgb)
        if ($null -ne $chartAreaColor) { $Chart.ChartArea.Format.Fill.ForeColor.RGB = $chartAreaColor }

        $plotAreaColor = Parse-HexColorToCom -Rgb ([string]$StyleProfile.plot.plot_area_fill_rgb)
        if ($null -ne $plotAreaColor) { $Chart.PlotArea.Format.Fill.ForeColor.RGB = $plotAreaColor }

        $lineColor = Parse-HexColorToCom -Rgb ([string]$StyleProfile.plot.border_line_rgb)
        if ($null -ne $lineColor) { $Chart.ChartArea.Format.Line.ForeColor.RGB = $lineColor }
        if ($StyleProfile.plot.border_line_weight) { $Chart.ChartArea.Format.Line.Weight = [double]$StyleProfile.plot.border_line_weight }
    }

    $seriesColors = @()
    if (($ChartCfg.PSObject.Properties.Name -contains "series_palette_override") -and $ChartCfg.series_palette_override) {
        $seriesColors = @($ChartCfg.series_palette_override)
    } elseif ($StyleProfile.series_palette_rgb) {
        $seriesColors = @($StyleProfile.series_palette_rgb)
    }

    $serCount = [int]$Chart.SeriesCollection().Count
    for ($i = 1; $i -le $serCount; $i++) {
        $ser = $Chart.SeriesCollection($i)
        if ($seriesColors.Count -gt 0) {
            $rgb = [string]$seriesColors[($i - 1) % $seriesColors.Count]
            $c = Parse-HexColorToCom -Rgb $rgb
            if ($null -ne $c) {
                $ser.Format.Fill.ForeColor.RGB = $c
                $ser.Format.Line.ForeColor.RGB = $c
            }
        }
    }

    try {
        $valueAxis = $Chart.Axes(2)
        if ($valueAxis -and $StyleProfile.axis_labels) {
            Apply-TextStyle -FontObject $valueAxis.TickLabels.Font -StyleNode $StyleProfile.axis_labels
            $valueAxis.HasMajorGridlines = $true
            $gridColor = Parse-HexColorToCom -Rgb "B7C9DE"
            if ($null -ne $gridColor) { $valueAxis.MajorGridlines.Format.Line.ForeColor.RGB = $gridColor }
        }
    } catch {}
    try {
        $secondaryValueAxis = $Chart.Axes(2, 2)
        if ($secondaryValueAxis -and $StyleProfile.axis_labels) {
            Apply-TextStyle -FontObject $secondaryValueAxis.TickLabels.Font -StyleNode $StyleProfile.axis_labels
        }
    } catch {}
    try {
        $catAxis = $Chart.Axes(1)
        if ($catAxis -and $StyleProfile.axis_labels) { Apply-TextStyle -FontObject $catAxis.TickLabels.Font -StyleNode $StyleProfile.axis_labels }
    } catch {}
}

function Apply-BarStyleLayout {
    param(
        $Chart,
        $ChartCfg,
        $StyleProfile
    )
    if (-not $Chart -or -not $StyleProfile -or -not $StyleProfile.bar_style) { return }
    $chartType = [string]$ChartCfg.chart_type
    if (-not (Is-HorizontalBarChart -Type $chartType)) { return }
    $barStyle = $StyleProfile.bar_style
    $gapWidth = $null
    $overlap = $null
    if (($barStyle.PSObject.Properties.Name -contains "gap_width") -and $null -ne $barStyle.gap_width) {
        $gapWidth = [int]$barStyle.gap_width
    }
    if (($barStyle.PSObject.Properties.Name -contains "overlap") -and $null -ne $barStyle.overlap) {
        $overlap = [int]$barStyle.overlap
    }
    if ($null -eq $gapWidth -and $null -eq $overlap) { return }
    try {
        foreach ($group in @($Chart.ChartGroups())) {
            if (-not $group) { continue }
            if ($null -ne $gapWidth) { try { $group.GapWidth = $gapWidth } catch {} }
            if ($null -ne $overlap) { try { $group.Overlap = $overlap } catch {} }
        }
    } catch {}
}

function Test-ProjectKeyMatch {
    param(
        [string]$Left,
        [string]$Right
    )
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    if ([string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $leftNorm = $Left.ToLowerInvariant().Replace("/", "_")
    $rightNorm = $Right.ToLowerInvariant().Replace("/", "_")
    if ($leftNorm -eq $rightNorm) { return $true }
    return ($Left.ToLowerInvariant().Replace("_", "/") -eq $Right.ToLowerInvariant().Replace("_", "/"))
}

function Apply-BarPointHighlight {
    param(
        $Chart,
        $ChartCfg,
        $SourceSheet,
        [int]$DataStartRow,
        [int]$LastRow,
        [int]$XColumn,
        $StyleProfile
    )
    if (-not $Chart -or -not $ChartCfg -or -not (Is-HorizontalBarChart -Type ([string]$ChartCfg.chart_type))) { return }
    $highlightKey = ""
    if (($ChartCfg.PSObject.Properties.Name -contains "highlight_project_key") -and $ChartCfg.highlight_project_key) {
        $highlightKey = [string]$ChartCfg.highlight_project_key
    } elseif (($ChartCfg.PSObject.Properties.Name -contains "focus_project_key") -and $ChartCfg.focus_project_key) {
        $highlightKey = [string]$ChartCfg.focus_project_key
    } elseif ($StyleProfile -and $StyleProfile.highlight -and ($StyleProfile.highlight.PSObject.Properties.Name -contains "project_key") -and $StyleProfile.highlight.project_key) {
        $highlightKey = [string]$StyleProfile.highlight.project_key
    }
    if (-not $highlightKey) { return }

    $highlightFill = $null
    $contextFill = $null
    if ($StyleProfile -and $StyleProfile.highlight) {
        if (($StyleProfile.highlight.PSObject.Properties.Name -contains "highlight_fill_rgb") -and $StyleProfile.highlight.highlight_fill_rgb) {
            $highlightFill = Parse-HexColorToCom -Rgb ([string]$StyleProfile.highlight.highlight_fill_rgb)
        }
        if (($StyleProfile.highlight.PSObject.Properties.Name -contains "context_fill_rgb") -and $StyleProfile.highlight.context_fill_rgb) {
            $contextFill = Parse-HexColorToCom -Rgb ([string]$StyleProfile.highlight.context_fill_rgb)
        }
    }
    if ($null -eq $highlightFill -and $null -eq $contextFill) { return }
    $series = $null
    try { $series = $Chart.SeriesCollection(1) } catch { $series = $null }
    if (-not $series) { return }

    try {
        $pointCount = [int]$series.Points().Count
    } catch {
        $pointCount = 0
    }
    if ($pointCount -le 0) { return }

    for ($row = $DataStartRow; $row -le $LastRow; $row++) {
        $pointIndex = $row - $DataStartRow + 1
        if ($pointIndex -lt 1 -or $pointIndex -gt $pointCount) { continue }
        $rawLabel = [string]$SourceSheet.Cells.Item($row, $XColumn).Value2
        if (-not $rawLabel) { continue }
        $isHighlight = Test-ProjectKeyMatch -Left $rawLabel -Right $highlightKey
        if ($isHighlight) {
            if ($null -ne $highlightFill) {
                try { $series.Points($pointIndex).Format.Fill.ForeColor.RGB = $highlightFill } catch {}
                try { $series.Points($pointIndex).Format.Line.ForeColor.RGB = $highlightFill } catch {}
            }
        } elseif ($null -ne $contextFill) {
            try { $series.Points($pointIndex).Format.Fill.ForeColor.RGB = $contextFill } catch {}
            try { $series.Points($pointIndex).Format.Line.ForeColor.RGB = $contextFill } catch {}
        }
    }
}

function Apply-PhaseBackgroundStyle {
    param(
        $Chart,
        $ChartCfg,
        $ControlProfile
    )
    if (-not $Chart -or -not $ChartCfg -or -not $ControlProfile) { return }
    if (-not (($ControlProfile.PSObject.Properties.Name -contains "phase_background") -and $ControlProfile.phase_background)) { return }
    $phaseConfig = $ControlProfile.phase_background
    $fillTransparency = 0.75
    if (($phaseConfig.PSObject.Properties.Name -contains "fill_transparency") -and $null -ne $phaseConfig.fill_transparency) {
        $fillTransparency = [double]$phaseConfig.fill_transparency
    }
    $lineVisible = $false
    if (($phaseConfig.PSObject.Properties.Name -contains "line_visible") -and $null -ne $phaseConfig.line_visible) {
        $lineVisible = [bool]$phaseConfig.line_visible
    }
    if (-not $ChartCfg.series_plan) { return }
    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    if ($phaseLabels.Count -eq 0) { return }
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $ser = $Chart.SeriesCollection($i)
            $seriesName = Get-CleanSeriesName -Series $ser
            if (-not $phaseLabels.Contains($seriesName)) { continue }
            try { $ser.Format.Fill.Transparency = $fillTransparency } catch {}
            try { $ser.Format.Line.Visible = $lineVisible } catch {}
            try { $ser.Format.Line.Transparency = 1 } catch {}
        }
    } catch {}
}

function Apply-PhaseBackgroundLayout {
    param(
        $Chart,
        $ChartCfg,
        $ControlProfile
    )
    if (-not $Chart -or -not $ChartCfg -or [string]$ChartCfg.chart_type -ne "combo") { return }
    $hasPhaseSeries = $false
    foreach ($seriesDef in @(Get-SeriesPlanEntries -ChartCfg $ChartCfg -ControlProfile $ControlProfile)) {
        if ([string]$seriesDef.field -like "phase_*") {
            $hasPhaseSeries = $true
            break
        }
    }
    if (-not $hasPhaseSeries) { return }

    $gapWidth = 0
    $overlap = 100
    if ($ControlProfile -and $ControlProfile.phase_background) {
        if (($ControlProfile.phase_background.PSObject.Properties.Name -contains "gap_width") -and $null -ne $ControlProfile.phase_background.gap_width) {
            $gapWidth = [int]$ControlProfile.phase_background.gap_width
        }
        if (($ControlProfile.phase_background.PSObject.Properties.Name -contains "overlap") -and $null -ne $ControlProfile.phase_background.overlap) {
            $overlap = [int]$ControlProfile.phase_background.overlap
        }
    }

    try {
        $groups = @($Chart.ChartGroups())
        foreach ($group in $groups) {
            if (-not $group) { continue }
            try { $group.GapWidth = $gapWidth } catch {}
            try { $group.Overlap = $overlap } catch {}
        }
    } catch {}
}

$paths = Resolve-DefaultPaths
$WorkbookPath = $paths.WorkbookPath
$ChartSpecJson = $paths.ChartSpecJson
$LayoutSpecJson = $paths.LayoutSpecJson
$StyleProfileJson = $paths.StyleProfileJson

if (-not (Test-Path -LiteralPath $WorkbookPath)) { throw "Missing workbook: $WorkbookPath" }
if (-not (Test-Path -LiteralPath $ChartSpecJson)) { throw "Missing chart spec: $ChartSpecJson" }

$chartSpec = Get-Content -LiteralPath $ChartSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json
$layoutSpec = $null
if (Test-Path -LiteralPath $LayoutSpecJson) {
    $layoutSpec = Get-Content -LiteralPath $LayoutSpecJson -Raw -Encoding UTF8 | ConvertFrom-Json
}
$styleProfile = $null
if (Test-Path -LiteralPath $StyleProfileJson) {
    $styleProfile = Get-Content -LiteralPath $StyleProfileJson -Raw -Encoding UTF8 | ConvertFrom-Json
}
$controlProfile = $null
if ($ControlProfileJson -and (Test-Path -LiteralPath $ControlProfileJson)) {
    $controlProfile = Get-Content -LiteralPath $ControlProfileJson -Raw -Encoding UTF8 | ConvertFrom-Json
}
$secondaryAxisScale = Get-SecondaryAxisScaleConfig -ControlProfile $controlProfile
$dateAxisScale = Get-DateAxisConfig -ControlProfile $controlProfile

$sheetLayoutMap = @{}
$inputTableToSheetMap = @{}
$sheetHeaderRowMap = @{}
$sheetDataStartRowMap = @{}
if ($layoutSpec -and $layoutSpec.sheets) {
    foreach ($sh in @($layoutSpec.sheets)) {
        $sn = [string]$sh.sheet_name
        $sheetLayoutMap[$sn] = $sh
        if ($sh.input_table) {
            $inputTableToSheetMap[[string]$sh.input_table] = [string]$sh.sheet_name
        }
        $headerRow = 1
        $dataStartRow = 2
        if ($sh.PSObject.Properties.Name -contains "table_layout") {
            $tl = $sh.table_layout
            if (($tl.PSObject.Properties.Name -contains "header_row") -and $tl.header_row) { $headerRow = [int]$tl.header_row }
            if (($tl.PSObject.Properties.Name -contains "data_start_row") -and $tl.data_start_row) { $dataStartRow = [int]$tl.data_start_row }
        } elseif (($sh.PSObject.Properties.Name -contains "data_start_row") -and $sh.data_start_row) {
            $headerRow = [int]$sh.data_start_row
            $dataStartRow = $headerRow + 1
        }
        $sheetHeaderRowMap[$sn] = $headerRow
        $sheetDataStartRowMap[$sn] = $dataStartRow
    }
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $null

try {
    $wb = $excel.Workbooks.Open($WorkbookPath)

    foreach ($ws in @($wb.Worksheets)) {
        while ($ws.ChartObjects().Count -gt 0) {
            $ws.ChartObjects(1).Delete()
        }
    }

    $indexPerSheet = @{}
    $created = 0
    $failed = 0

    foreach ($chartCfg in @($chartSpec.charts)) {
        $chartId = [string]$chartCfg.chart_id
        try {
            $sourceSheetName = [string]$chartCfg.source_sheet
            $targetSheetName = [string]$chartCfg.sheet
            if (-not $targetSheetName) { $targetSheetName = $sourceSheetName }

            $xHeader = [string]$chartCfg.x_series
            $seriesDefs = @(Get-SeriesPlanEntries -ChartCfg $chartCfg -ControlProfile $controlProfile)
            $ySeriesDefs = @($seriesDefs | Where-Object { [string]$_.role -ne "x" })
            $isBarHorizontal = Is-HorizontalBarChart -Type ([string]$chartCfg.chart_type)

            if (-not $chartId -or -not $sourceSheetName -or -not $targetSheetName) { continue }

            $resolvedSourceSheetName = $sourceSheetName
            $srcSheet = $null
            try { $srcSheet = $wb.Worksheets.Item($resolvedSourceSheetName) } catch { $srcSheet = $null }
            if (-not $srcSheet -and $inputTableToSheetMap.ContainsKey($sourceSheetName)) {
                $resolvedSourceSheetName = [string]$inputTableToSheetMap[$sourceSheetName]
                try { $srcSheet = $wb.Worksheets.Item($resolvedSourceSheetName) } catch { $srcSheet = $null }
            }
            if (-not $srcSheet) {
                Write-Warning "[S04] Missing source sheet for ${chartId}: $sourceSheetName"
                continue
            }

            $targetSheet = $null
            try { $targetSheet = $wb.Worksheets.Item($targetSheetName) } catch { $targetSheet = $null }
            if (-not $targetSheet) {
                Write-Warning "[S04] Missing target sheet for ${chartId}: $targetSheetName"
                continue
            }

            $srcHeaderRow = 1
            $srcDataStartRow = 2
            if ($sheetHeaderRowMap.ContainsKey($resolvedSourceSheetName)) { $srcHeaderRow = [int]$sheetHeaderRowMap[$resolvedSourceSheetName] }
            if ($sheetDataStartRowMap.ContainsKey($resolvedSourceSheetName)) { $srcDataStartRow = [int]$sheetDataStartRowMap[$resolvedSourceSheetName] }

            $lastRow = Get-LastDataRow -Worksheet $srcSheet -HeaderRow $srcHeaderRow
            if ($lastRow -lt $srcDataStartRow) {
                Write-Warning "[S04] Source sheet has no data for ${chartId}: $sourceSheetName"
                continue
            }

            $xCol = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header (Resolve-SeriesHeaderAlias -Header $xHeader) -HeaderRow $srcHeaderRow -StyleProfile $styleProfile
            if ($xCol -lt 1) {
                Write-Warning "[S04] Missing x_series '$xHeader' for $chartId"
                continue
            }
            $rowBounds = Get-ScopedDataRowBounds -Worksheet $srcSheet -ChartCfg $chartCfg -XColumn $xCol -DataStartRow $srcDataStartRow -LastDataRow $lastRow
            $chartDataStartRow = [int]$rowBounds.StartRow
            $chartLastRow = [int]$rowBounds.EndRow
            if ($chartLastRow -lt $chartDataStartRow) {
                Write-Warning "[S04] Scoped source sheet has no data for ${chartId}: $sourceSheetName"
                continue
            }

            if (-not $indexPerSheet.ContainsKey($targetSheetName)) { $indexPerSheet[$targetSheetName] = 0 }
            $sheetIdx = [int]$indexPerSheet[$targetSheetName]

            $left = 520
            $top = 20 + (330 * $sheetIdx)
            $width = 640
            $height = 300

            $sheetLayout = $null
            if ($sheetLayoutMap.ContainsKey($targetSheetName)) { $sheetLayout = $sheetLayoutMap[$targetSheetName] }
            if ($sheetLayout -and $sheetLayout.chart_region) {
                $left = [double]$sheetLayout.chart_region.left
                $top = [double]$sheetLayout.chart_region.top + (330 * $sheetIdx)
                $width = [double]$sheetLayout.chart_region.width
                $height = [double]$sheetLayout.chart_region.height
            }
            $preferSheetRegion = $false
            if ($styleProfile -and $styleProfile.layout_defaults) {
                if ($styleProfile.layout_defaults.PSObject.Properties.Name -contains "prefer_sheet_chart_region") {
                    $preferSheetRegion = [bool]$styleProfile.layout_defaults.prefer_sheet_chart_region
                }
                if (-not $preferSheetRegion) {
                    if ($styleProfile.layout_defaults.PSObject.Properties.Name -contains "chart_left" -and $styleProfile.layout_defaults.chart_left) { $left = [double]$styleProfile.layout_defaults.chart_left }
                    if ($styleProfile.layout_defaults.PSObject.Properties.Name -contains "chart_top" -and $styleProfile.layout_defaults.chart_top) { $top = [double]$styleProfile.layout_defaults.chart_top + (330 * $sheetIdx) }
                }
                if (-not $sheetLayout -or -not $sheetLayout.chart_region) {
                    if ($styleProfile.layout_defaults.chart_width) { $width = [double]$styleProfile.layout_defaults.chart_width }
                    if ($styleProfile.layout_defaults.chart_height) { $height = [double]$styleProfile.layout_defaults.chart_height }
                }
            }
            if ((-not $preferSheetRegion -or -not $sheetLayout -or -not $sheetLayout.chart_region) -and $chartCfg.chart_size) {
                if ($chartCfg.chart_size.width) { $width = [double]$chartCfg.chart_size.width }
                if ($chartCfg.chart_size.height) { $height = [double]$chartCfg.chart_size.height }
            }

            $co = $targetSheet.ChartObjects().Add($left, $top, $width, $height)
            $co.Name = $chartId
            $chart = $co.Chart
            $chartTypeForChart = [string]$chartCfg.chart_type
            if ($chartTypeForChart -eq "combo") {
                $firstExplicitType = ""
                foreach ($def in $ySeriesDefs) {
                    if ([string]$def.axis_group -eq "primary" -and $def.chart_type) {
                        $firstExplicitType = [string]$def.chart_type
                        break
                    }
                }
                foreach ($def in $ySeriesDefs) {
                    if (-not $firstExplicitType -and $def.chart_type) {
                        $firstExplicitType = [string]$def.chart_type
                        break
                    }
                }
                if ($firstExplicitType) { $chartTypeForChart = $firstExplicitType } else { $chartTypeForChart = "line" }
            }
            $chart.ChartType = (Get-ChartTypeCode -Type $chartTypeForChart)
            $chart.HasTitle = $true
            $chart.ChartTitle.Text = [string]$chartCfg.title
            $chart.HasLegend = (-not $isBarHorizontal) -or ($isBarHorizontal -and $ySeriesDefs.Count -gt 1)

            while ($chart.SeriesCollection().Count -gt 0) {
                $chart.SeriesCollection(1).Delete()
            }

            if ($isBarHorizontal) {
                if ($ySeriesDefs.Count -gt 1) {
                    $categoryCol = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header (Resolve-SeriesHeaderAlias -Header $xHeader) -HeaderRow $srcHeaderRow -StyleProfile $styleProfile
                    if ($categoryCol -lt 1) {
                        Write-Warning "[S04] Missing bar category header '$xHeader' for $chartId"
                        continue
                    }
                    for ($i = 0; $i -lt $ySeriesDefs.Count; $i++) {
                        $seriesDef = $ySeriesDefs[$i]
                        $yHeader = [string]$seriesDef.field
                        if (-not $yHeader) { continue }
                        $seriesLabel = [string]$seriesDef.label
                        $yCol = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header (Resolve-SeriesHeaderAlias -Header $yHeader) -HeaderRow $srcHeaderRow -StyleProfile $styleProfile
                        if ($yCol -lt 1) {
                            Write-Warning "[S04] Missing y_series '$yHeader' for $chartId"
                            continue
                        }
                        $series = $chart.SeriesCollection().NewSeries()
                        $series.Name = Resolve-SeriesLabel -Label $seriesLabel -FallbackHeader $yHeader
                        $series.XValues = $srcSheet.Range($srcSheet.Cells.Item($chartDataStartRow, $categoryCol), $srcSheet.Cells.Item($chartLastRow, $categoryCol))
                        $series.Values = $srcSheet.Range($srcSheet.Cells.Item($chartDataStartRow, $yCol), $srcSheet.Cells.Item($chartLastRow, $yCol))
                        if ($seriesDef.chart_type) {
                            $series.ChartType = (Get-ChartTypeCode -Type ([string]$seriesDef.chart_type))
                        }
                        if ([string]$seriesDef.axis_group -eq "secondary") {
                            try { $series.AxisGroup = 2 } catch {}
                        }
                }
            } else {
                $seriesDef = if ($ySeriesDefs.Count -gt 0) { $ySeriesDefs[0] } else { $null }
                $yHeader = if ($seriesDef) { [string]$seriesDef.field } else { "" }
                $categoryCol = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header (Resolve-SeriesHeaderAlias -Header $xHeader) -HeaderRow $srcHeaderRow -StyleProfile $styleProfile
                $valueCol = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header (Resolve-SeriesHeaderAlias -Header $yHeader) -HeaderRow $srcHeaderRow -StyleProfile $styleProfile
                if ($categoryCol -lt 1 -or $valueCol -lt 1) {
                    Write-Warning "[S04] Missing bar series headers for $chartId"
                    continue
                }
                $series = $chart.SeriesCollection().NewSeries()
                $series.Name = Resolve-SeriesLabel -Label ($(if ($seriesDef) { $seriesDef.label } else { "" })) -FallbackHeader $yHeader
                $series.XValues = $srcSheet.Range($srcSheet.Cells.Item($chartDataStartRow, $categoryCol), $srcSheet.Cells.Item($chartLastRow, $categoryCol))
                $series.Values = $srcSheet.Range($srcSheet.Cells.Item($chartDataStartRow, $valueCol), $srcSheet.Cells.Item($chartLastRow, $valueCol))
                if ($seriesDef -and $seriesDef.chart_type) {
                    $series.ChartType = (Get-ChartTypeCode -Type ([string]$seriesDef.chart_type))
                }
                if ($seriesDef -and [string]$seriesDef.axis_group -eq "secondary") {
                    try { $series.AxisGroup = 2 } catch {}
                }
            }
            }
            else {
                for ($i = 0; $i -lt $ySeriesDefs.Count; $i++) {
                    $seriesDef = $ySeriesDefs[$i]
                    $yHeader = [string]$seriesDef.field
                    if (-not $yHeader) { continue }
                    $seriesLabel = [string]$seriesDef.label
                    $lookupHeader = Resolve-SeriesHeaderAlias -Header $yHeader
                    $yCol = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header $lookupHeader -HeaderRow $srcHeaderRow -StyleProfile $styleProfile
                    if ($yCol -lt 1) {
                        Write-Warning "[S04] Missing y_series '$yHeader' for $chartId"
                        continue
                    }

                    $series = $chart.SeriesCollection().NewSeries()
                    $series.Name = Resolve-SeriesLabel -Label $seriesLabel -FallbackHeader $yHeader
                    $series.XValues = $srcSheet.Range($srcSheet.Cells.Item($chartDataStartRow, $xCol), $srcSheet.Cells.Item($chartLastRow, $xCol))
                    $series.Values = $srcSheet.Range($srcSheet.Cells.Item($chartDataStartRow, $yCol), $srcSheet.Cells.Item($chartLastRow, $yCol))
                    if ($seriesDef.chart_type) {
                        $series.ChartType = (Get-ChartTypeCode -Type ([string]$seriesDef.chart_type))
                    } elseif ([string]$chartCfg.chart_type -eq "combo" -and $controlProfile -and $controlProfile.series_plan_defaults -and $controlProfile.series_plan_defaults.chart_type) {
                        $series.ChartType = (Get-ChartTypeCode -Type ([string]$controlProfile.series_plan_defaults.chart_type))
                    }
                    if ([string]$seriesDef.axis_group -eq "secondary") {
                        try { $series.AxisGroup = 2 } catch {}
                    }
                }
            }

            $hasSecondarySeries = $false
            foreach ($seriesDefCheck in @($ySeriesDefs)) {
                if ([string]$seriesDefCheck.axis_group -eq "secondary") {
                    $hasSecondarySeries = $true
                    break
                }
            }
            Enforce-PhaseSeriesAsSecondaryColumns -Chart $chart -ChartCfg $chartCfg
            if ($hasSecondarySeries -and $chartCfg.chart_type -eq "combo") {
                Apply-SecondaryAxisScale -Chart $chart -ScaleConfig $(if ($secondaryAxisScale) { $secondaryAxisScale } else { [pscustomobject]@{ minimum = 0; maximum = 100; major_unit = 20; minimum_is_auto = $false; maximum_is_auto = $false; major_unit_is_auto = $false } })
            }
            if ($dateAxisScale -and [string]$xHeader -eq "date" -and -not $isBarHorizontal) {
                Apply-DateAxisScale -Chart $chart -ScaleConfig $dateAxisScale
            }
            Apply-ChartStyle -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile
            Apply-BarStyleLayout -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile
            if ($isBarHorizontal) {
                Apply-BarPointHighlight -Chart $chart -ChartCfg $chartCfg -SourceSheet $srcSheet -DataStartRow $chartDataStartRow -LastRow $chartLastRow -XColumn $categoryCol -StyleProfile $styleProfile
            }
            Enforce-PhaseSeriesAsSecondaryColumns -Chart $chart -ChartCfg $chartCfg
            Apply-PhaseBackgroundStyle -Chart $chart -ChartCfg $chartCfg -ControlProfile $controlProfile
            Apply-PhaseBackgroundLayout -Chart $chart -ChartCfg $chartCfg -ControlProfile $controlProfile
            $indexPerSheet[$targetSheetName] = $sheetIdx + 1
            $created++
        } catch {
            $failed++
            Write-Warning "[S04] Chart '$chartId' failed: $($_.Exception.Message)"
            continue
        }
    }

    if ($failed -gt 0) {
        throw "[S04] Chart build failures: $failed"
    }

    $wb.Save()
    $wb.Close($true)
    Write-Host "[S04] Charts added to workbook: $WorkbookPath"
    Write-Host "[S04] Charts created: $created"
}
finally {
    if ($null -ne $wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
    $excel.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
