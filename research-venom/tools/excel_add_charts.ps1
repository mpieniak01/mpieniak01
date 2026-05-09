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

function Test-IsPhaseSeriesName {
    param(
        [string]$SeriesName,
        $PhaseLabels
    )
    if (-not $SeriesName) { return $false }
    if ($PhaseLabels -and @($PhaseLabels) -contains $SeriesName) { return $true }
    if ($SeriesName -like "phase_*") { return $true }
    if ($SeriesName -like "Faza *") { return $true }
    return $false
}

function Test-IsPhaseSeriesObject {
    param(
        $Series,
        [int]$SeriesIndex,
        $PhaseLabels,
        $PhaseIndexes
    )
    $seriesName = Get-CleanSeriesName -Series $Series
    if (($PhaseIndexes -contains $SeriesIndex) -or (Test-IsPhaseSeriesName -SeriesName $seriesName -PhaseLabels $PhaseLabels)) {
        return $true
    }
    try {
        $axisGroup = [int]$Series.AxisGroup
        $chartType = [int]$Series.ChartType
        if ($axisGroup -eq 2 -and $chartType -eq (Get-ChartTypeCode -Type "column") -and $seriesName -like "Faza*") {
            return $true
        }
    } catch {}
    return $false
}

function Get-PhaseSeriesIndexes {
    param($ChartCfg)
    $indexes = New-Object System.Collections.Generic.List[int]
    if (-not $ChartCfg -or -not $ChartCfg.series_plan) { return @($indexes) }
    $idx = 0
    foreach ($plan in @($ChartCfg.series_plan)) {
        if (-not $plan) { continue }
        $render = $true
        if ($plan.PSObject.Properties.Name -contains "render") { $render = [bool]$plan.render }
        if (-not $render) { continue }
        $idx++
        if ([string]$plan.field -like "phase_*") {
            [void]$indexes.Add($idx)
        }
    }
    return @($indexes)
}

function Get-LeadingPhaseSeriesCount {
    param($ChartCfg)
    if (-not $ChartCfg -or -not $ChartCfg.series_plan) { return 0 }
    $count = 0
    foreach ($plan in @($ChartCfg.series_plan)) {
        if (-not $plan) { continue }
        $render = $true
        if ($plan.PSObject.Properties.Name -contains "render") { $render = [bool]$plan.render }
        if (-not $render) { continue }
        if ([string]$plan.field -like "phase_*") {
            $count++
            continue
        }
        break
    }
    return [int]$count
}

function Enforce-PhaseSeriesAsSecondaryColumns {
    param(
        $Chart,
        $ChartCfg
    )
    if (-not $Chart -or -not $ChartCfg) { return }
    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    $phaseIndexes = @(Get-PhaseSeriesIndexes -ChartCfg $ChartCfg)
    $leadingPhaseCount = Get-LeadingPhaseSeriesCount -ChartCfg $ChartCfg
    if ($phaseLabels.Count -eq 0) { return }
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $series = $Chart.SeriesCollection($i)
            if (($i -gt $leadingPhaseCount) -and -not (Test-IsPhaseSeriesObject -Series $series -SeriesIndex $i -PhaseLabels $phaseLabels -PhaseIndexes $phaseIndexes)) { continue }
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

function Apply-ValueAxisScale {
    param(
        $Chart,
        $ScaleConfig,
        [int]$AxisGroup = 2
    )
    if (-not $Chart -or -not $ScaleConfig) { return }
    try {
        $axis = $Chart.Axes(2, $AxisGroup)
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

function Apply-PrimaryAxisScale {
    param(
        $Chart,
        $ScaleConfig
    )
    Apply-ValueAxisScale -Chart $Chart -ScaleConfig $ScaleConfig -AxisGroup 1
}

function Apply-SecondaryAxisScale {
    param(
        $Chart,
        $ScaleConfig
    )
    Apply-ValueAxisScale -Chart $Chart -ScaleConfig $ScaleConfig -AxisGroup 2
}

function Get-ChartDataSeriesMax {
    param(
        $Worksheet,
        $SeriesDefs,
        [int]$HeaderRow,
        [int]$DataStartRow,
        [int]$LastDataRow,
        $StyleProfile,
        [string]$AxisGroup = ""
    )
    $bounds = Get-ChartDataSeriesBounds -Worksheet $Worksheet -SeriesDefs $SeriesDefs -HeaderRow $HeaderRow -DataStartRow $DataStartRow -LastDataRow $LastDataRow -StyleProfile $StyleProfile -AxisGroup $AxisGroup
    if ($null -eq $bounds -or $null -eq $bounds.max) { return $null }
    return [double]$bounds.max
}

function Convert-ComRangeValuesToFlatArray {
    param($Values)
    if ($null -eq $Values) { return @() }
    if (-not ($Values -is [System.Array])) { return @($Values) }
    $flat = @()
    foreach ($value in $Values) { $flat += $value }
    return $flat
}

function Get-ChartDataSeriesBounds {
    param(
        $Worksheet,
        $SeriesDefs,
        [int]$HeaderRow,
        [int]$DataStartRow,
        [int]$LastDataRow,
        $StyleProfile,
        [string]$AxisGroup = ""
    )
    if (-not $Worksheet -or -not $SeriesDefs) { return $null }
    $minValue = $null
    $maxValue = $null
    foreach ($seriesDef in @($SeriesDefs)) {
        if (-not $seriesDef) { continue }
        $field = [string]$seriesDef.field
        if (-not $field -or $field -like "phase_*") { continue }
        if ($AxisGroup) {
            $seriesAxisGroup = "primary"
            if (($seriesDef.PSObject.Properties.Name -contains "axis_group") -and $seriesDef.axis_group) {
                $seriesAxisGroup = [string]$seriesDef.axis_group
            }
            if ($seriesAxisGroup -ne $AxisGroup) { continue }
        }
        $col = Get-ColumnIndexByHeader -Worksheet $Worksheet -Header (Resolve-SeriesHeaderAlias -Header $field) -HeaderRow $HeaderRow -StyleProfile $StyleProfile
        if ($col -lt 1) { continue }
        $rangeValues = @()
        try {
            $range = $Worksheet.Range($Worksheet.Cells.Item($DataStartRow, $col), $Worksheet.Cells.Item($LastDataRow, $col))
            $rangeValues = @(Convert-ComRangeValuesToFlatArray -Values $range.Value2)
        } catch {
            $rangeValues = @()
        }
        foreach ($raw in $rangeValues) {
            if ($null -eq $raw -or $raw -eq "") { continue }
            $value = 0.0
            if (-not (Try-ConvertToDouble -Value $raw -Result ([ref]$value))) { continue }
            if ($null -eq $minValue -or $value -lt $minValue) { $minValue = $value }
            if ($null -eq $maxValue -or $value -gt $maxValue) { $maxValue = $value }
        }
    }
    if ($null -eq $minValue -or $null -eq $maxValue) { return $null }
    return [pscustomobject]@{
        min = [double]$minValue
        max = [double]$maxValue
    }
}

function Convert-ComSeriesValuesToArray {
    param($Values)
    if ($null -eq $Values) { return @() }
    if ($Values -is [System.Array]) { return @($Values) }
    return @($Values)
}

function Try-ConvertToDouble {
    param(
        $Value,
        [ref]$Result
    )
    if ($null -eq $Value -or [string]$Value -eq "") { return $false }
    try {
        if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal] -or $Value -is [int] -or $Value -is [long]) {
            $Result.Value = [double]$Value
            return $true
        }
    } catch {}
    $text = ([string]$Value).Trim()
    if (-not $text) { return $false }
    $num = 0.0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::CurrentCulture, [ref]$num)) {
        $Result.Value = $num
        return $true
    }
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
        $Result.Value = $num
        return $true
    }
    $normalized = $text.Replace(",", ".")
    if ([double]::TryParse($normalized, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
        $Result.Value = $num
        return $true
    }
    return $false
}

function Get-RenderedChartSeriesBounds {
    param(
        $Chart,
        $ChartCfg,
        [int]$AxisGroup
    )
    if (-not $Chart -or -not $ChartCfg) { return $null }
    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    $phaseIndexes = @(Get-PhaseSeriesIndexes -ChartCfg $ChartCfg)
    $leadingPhaseCount = Get-LeadingPhaseSeriesCount -ChartCfg $ChartCfg
    $minValue = $null
    $maxValue = $null
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $ser = $Chart.SeriesCollection($i)
            if (($i -le $leadingPhaseCount) -or (Test-IsPhaseSeriesObject -Series $ser -SeriesIndex $i -PhaseLabels $phaseLabels -PhaseIndexes $phaseIndexes)) { continue }
            $seriesAxisGroup = 1
            try { $seriesAxisGroup = [int]$ser.AxisGroup } catch { $seriesAxisGroup = 1 }
            if ($seriesAxisGroup -ne $AxisGroup) { continue }
            $values = @()
            try { $values = @(Convert-ComSeriesValuesToArray -Values $ser.Values) } catch { $values = @() }
            foreach ($raw in $values) {
                if ($null -eq $raw -or [string]$raw -eq "") { continue }
                $value = 0.0
                if (-not (Try-ConvertToDouble -Value $raw -Result ([ref]$value))) { continue }
                if ($null -eq $minValue -or $value -lt $minValue) { $minValue = $value }
                if ($null -eq $maxValue -or $value -gt $maxValue) { $maxValue = $value }
            }
        }
    } catch {}
    if ($null -eq $minValue -or $null -eq $maxValue) { return $null }
    return [pscustomobject]@{
        min = [double]$minValue
        max = [double]$maxValue
    }
}

function Apply-DynamicPhaseScale {
    param(
        $Chart,
        $ChartCfg,
        $ControlProfile,
        $PrimaryDataBounds,
        $SecondaryDataBounds
    )
    if (-not $Chart -or -not $ChartCfg -or -not $ControlProfile) { return }
    if (-not (($ControlProfile.PSObject.Properties.Name -contains "phase_background") -and $ControlProfile.phase_background)) { return }
    $phaseCfg = $ControlProfile.phase_background
    $enabled = $false
    if (($phaseCfg.PSObject.Properties.Name -contains "dynamic_scale_enabled") -and $phaseCfg.dynamic_scale_enabled -eq $true) {
        $enabled = $true
    }
    if (-not $enabled) { return }

    $paddingPct = 0.10
    if (($phaseCfg.PSObject.Properties.Name -contains "dynamic_scale_padding_pct") -and $null -ne $phaseCfg.dynamic_scale_padding_pct) {
        $paddingPct = [double]$phaseCfg.dynamic_scale_padding_pct
    }
    if ($paddingPct -lt 0) { $paddingPct = 0 }
    $buildScale = {
        param($Bounds)
        if ($null -eq $Bounds) { return $null }
        $rawMin = 0.0
        $rawMax = 0.0
        if (-not [double]::TryParse([string]$Bounds.min, [ref]$rawMin)) { return $null }
        if (-not [double]::TryParse([string]$Bounds.max, [ref]$rawMax)) { return $null }
        if ($rawMin -eq 0 -and $rawMax -eq 0) { return $null }

        if ($rawMin -lt 0) {
            $scaledMin = [Math]::Floor($rawMin * (1.0 + $paddingPct))
        } else {
            $scaledMin = 0
        }
        if ($rawMax -gt 0) {
            $scaledMax = [Math]::Ceiling($rawMax * (1.0 + $paddingPct))
        } else {
            $scaledMax = 0
        }
        if ($scaledMax -le $scaledMin) {
            $scaledMax = $scaledMin + 1
        }
        $span = [Math]::Abs($scaledMax - $scaledMin)
        $majorUnit = [Math]::Ceiling($span / 5.0)
        if ($majorUnit -le 0) { $majorUnit = 1 }
        return [pscustomobject]@{
            minimum = $scaledMin
            maximum = $scaledMax
            major_unit = $majorUnit
            minimum_is_auto = $false
            maximum_is_auto = $false
            major_unit_is_auto = $false
        }
    }

    $primaryScale = & $buildScale $PrimaryDataBounds
    if ($primaryScale) {
        Apply-PrimaryAxisScale -Chart $Chart -ScaleConfig $primaryScale
    }

    $secondaryScale = & $buildScale $SecondaryDataBounds
    if (-not $secondaryScale) {
        $secondaryScale = & $buildScale $PrimaryDataBounds
    }
    if ($secondaryScale) {
        Apply-SecondaryAxisScale -Chart $Chart -ScaleConfig $secondaryScale
    }

    $phaseMax = $null
    if ($secondaryScale -and ($secondaryScale.PSObject.Properties.Name -contains "maximum")) {
        $phaseMax = [double]$secondaryScale.maximum
    } elseif ($primaryScale -and ($primaryScale.PSObject.Properties.Name -contains "maximum")) {
        $phaseMax = [double]$primaryScale.maximum
    }
    if ($null -eq $phaseMax -or $phaseMax -le 0) { return }

    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    $phaseIndexes = @(Get-PhaseSeriesIndexes -ChartCfg $ChartCfg)
    $leadingPhaseCount = Get-LeadingPhaseSeriesCount -ChartCfg $ChartCfg
    if ($phaseLabels.Count -eq 0) { return }
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $ser = $Chart.SeriesCollection($i)
            if (($i -gt $leadingPhaseCount) -and -not (Test-IsPhaseSeriesObject -Series $ser -SeriesIndex $i -PhaseLabels $phaseLabels -PhaseIndexes $phaseIndexes)) { continue }
            $count = 0
            try { $count = [int]$ser.Points().Count } catch { $count = 0 }
            if ($count -le 0) { continue }
            $sourceValues = @()
            try { $sourceValues = @(Convert-ComSeriesValuesToArray -Values $ser.Values) } catch { $sourceValues = @() }
            $vals = New-Object object[] $count
            for ($pi = 0; $pi -lt $count; $pi++) {
                $raw = $null
                if ($pi -lt $sourceValues.Count) { $raw = $sourceValues[$pi] }
                $num = 0.0
                $active = $false
                if ($null -ne $raw -and [string]$raw -ne "") {
                    $active = (Try-ConvertToDouble -Value $raw -Result ([ref]$num)) -and $num -gt 0
                }
                if ($active) {
                    $vals[$pi] = [double]$phaseMax
                } else {
                    $vals[$pi] = $null
                }
            }
            try { $ser.Values = $vals } catch {}
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
            $label = if (($item.PSObject.Properties.Name -contains "label") -and $item.label) { [string]$item.label } else { "" }
            $chartType = if (($item.PSObject.Properties.Name -contains "chart_type") -and $item.chart_type) { [string]$item.chart_type } elseif ($defaultSeriesType) { $defaultSeriesType } else { "" }
            $axisGroup = if (($item.PSObject.Properties.Name -contains "axis_group") -and $item.axis_group) { [string]$item.axis_group } else { $defaultAxisGroup }
            $render = if ($item.PSObject.Properties.Name -contains "render") { [bool]$item.render } else { $true }
            $entries += [pscustomobject]@{
                role = if (($item.PSObject.Properties.Name -contains "role") -and $item.role) { [string]$item.role } else { "y" }
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
    if (($StyleNode.PSObject.Properties.Name -contains "font_name") -and $StyleNode.font_name) { $FontObject.Name = [string]$StyleNode.font_name }
    if (($StyleNode.PSObject.Properties.Name -contains "font_size") -and $null -ne $StyleNode.font_size) { $FontObject.Size = [double]$StyleNode.font_size }
    if ($StyleNode.PSObject.Properties.Name -contains "bold") { $FontObject.Bold = [bool]$StyleNode.bold }
    if ($StyleNode.PSObject.Properties.Name -contains "italic") { $FontObject.Italic = [bool]$StyleNode.italic }
    if (($StyleNode.PSObject.Properties.Name -contains "font_color_rgb") -and $StyleNode.font_color_rgb) {
        $c = Parse-HexColorToCom -Rgb ([string]$StyleNode.font_color_rgb)
        if ($null -ne $c) { $FontObject.Color = $c }
    }
}

function Get-IsAcademicModeEnabled {
    param($StyleProfile)
    if (-not $StyleProfile) { return $false }
    if ($StyleProfile.PSObject.Properties.Name -contains "academic_style") {
        $ac = $StyleProfile.academic_style
        if ($ac -and ($ac.PSObject.Properties.Name -contains "enabled") -and $ac.enabled -eq $true) {
            return $true
        }
    }
    return $false
}

function Get-DomainSeriesPalette {
    param($StyleProfile, [string]$SourceType)
    $academicMode = Get-IsAcademicModeEnabled -StyleProfile $StyleProfile
    if ($SourceType) {
        $paletteKey = if ($academicMode) { "series_palette_academic" } else { "series_palette_by_source_type" }
        if ($StyleProfile.PSObject.Properties.Name -contains $paletteKey) {
            $palettes = $StyleProfile.$paletteKey
            if ($palettes -and $palettes.PSObject.Properties.Name -contains $SourceType) {
                return @($palettes.$SourceType)
            }
        }
    }
    if ($StyleProfile.series_palette_rgb) { return @($StyleProfile.series_palette_rgb) }
    return @()
}

function Apply-ChartStyle {
    param(
        $Chart,
        $ChartCfg,
        $StyleProfile,
        [string]$SourceType = "",
        $ControlProfile = $null
    )

    if (-not $StyleProfile) { return }

    $academicMode = Get-IsAcademicModeEnabled -StyleProfile $StyleProfile
    $acTypo = if ($academicMode -and $StyleProfile.PSObject.Properties.Name -contains "academic_typography") { $StyleProfile.academic_typography } else { $null }
    $acStyle = if ($academicMode -and $StyleProfile.PSObject.Properties.Name -contains "academic_style") { $StyleProfile.academic_style } else { $null }

    # Title
    $titleStyleNode = if ($acTypo -and $acTypo.PSObject.Properties.Name -contains "chart_title") { $acTypo.chart_title } else { $StyleProfile.chart_title }
    if ($Chart.HasTitle -and $titleStyleNode) {
        Apply-TextStyle -FontObject $Chart.ChartTitle.Font -StyleNode $titleStyleNode
    }

    # Legend position: chart config > legend_position_by_mode > style profile
    if ($Chart.HasLegend) {
        $legendStyleNode = if ($acTypo -and $acTypo.PSObject.Properties.Name -contains "legend") { $acTypo.legend } else { $StyleProfile.legend }
        if ($legendStyleNode) {
            # Apply to container font
            try { Apply-TextStyle -FontObject $Chart.Legend.Font -StyleNode $legendStyleNode } catch {}
            # Apply per-entry — LegendEntry.Font overrides container in Excel COM
            try {
                $entryCount = [int]$Chart.Legend.LegendEntries().Count
                for ($lei = 1; $lei -le $entryCount; $lei++) {
                    try { Apply-TextStyle -FontObject $Chart.Legend.LegendEntries($lei).Font -StyleNode $legendStyleNode } catch {}
                }
            } catch {}
        }
        $legendPosition = [string]$ChartCfg.legend_position
        if (-not $legendPosition -and $ControlProfile -and $ControlProfile.PSObject.Properties.Name -contains "legend_position_by_mode") {
            $chartMode = [string]$ChartCfg.chart_mode
            if ($chartMode -and $ControlProfile.legend_position_by_mode.PSObject.Properties.Name -contains $chartMode) {
                $legendPosition = [string]$ControlProfile.legend_position_by_mode.$chartMode
            }
        }
        if (-not $legendPosition -and $StyleProfile.legend) { $legendPosition = [string]$StyleProfile.legend.position }
        switch ($legendPosition) {
            "none"   { $Chart.HasLegend = $false }
            "left"   { $Chart.Legend.Position = -4131 }
            "top"    { $Chart.Legend.Position = -4160 }
            "bottom" { $Chart.Legend.Position = -4107 }
            default  { $Chart.Legend.Position = -4152 }
        }
    }

    # Plot area and chart area colors — academic overrides profile
    $chartAreaRgb  = if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "chart_area_fill_rgb") { [string]$acStyle.chart_area_fill_rgb } `
                     elseif ($StyleProfile.plot) { [string]$StyleProfile.plot.chart_area_fill_rgb } else { "" }
    $plotAreaRgb   = if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "plot_area_fill_rgb")  { [string]$acStyle.plot_area_fill_rgb  } `
                     elseif ($StyleProfile.plot) { [string]$StyleProfile.plot.plot_area_fill_rgb  } else { "" }
    $borderRgb     = if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "chart_border") { [string]$acStyle.chart_border.color_rgb } `
                     elseif ($StyleProfile.plot) { [string]$StyleProfile.plot.border_line_rgb } else { "" }
    $borderWeight  = if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "chart_border" -and $acStyle.chart_border.PSObject.Properties.Name -contains "weight_pt") { [double]$acStyle.chart_border.weight_pt } `
                     elseif ($StyleProfile.plot -and $StyleProfile.plot.border_line_weight) { [double]$StyleProfile.plot.border_line_weight } else { 1.0 }

    $c = Parse-HexColorToCom -Rgb $chartAreaRgb; if ($null -ne $c) { $Chart.ChartArea.Format.Fill.ForeColor.RGB = $c }
    $c = Parse-HexColorToCom -Rgb $plotAreaRgb;  if ($null -ne $c) { $Chart.PlotArea.Format.Fill.ForeColor.RGB  = $c }
    $c = Parse-HexColorToCom -Rgb $borderRgb;    if ($null -ne $c) { $Chart.ChartArea.Format.Line.ForeColor.RGB = $c }
    $Chart.ChartArea.Format.Line.Weight = $borderWeight
    if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "plot_area_border") {
        if ($acStyle.plot_area_border.PSObject.Properties.Name -contains "visible" -and $acStyle.plot_area_border.visible -eq $false) {
            try { $Chart.PlotArea.Format.Line.Visible = $false } catch {}
        }
    }

    # Series colors — domain palette > academic palette > global palette
    $seriesColors = @()
    if (($ChartCfg.PSObject.Properties.Name -contains "series_palette_override") -and $ChartCfg.series_palette_override) {
        $seriesColors = @($ChartCfg.series_palette_override)
    } else {
        $seriesColors = Get-DomainSeriesPalette -StyleProfile $StyleProfile -SourceType $SourceType
    }
    $serCount = [int]$Chart.SeriesCollection().Count
    for ($i = 1; $i -le $serCount; $i++) {
        $ser = $Chart.SeriesCollection($i)
        $seriesType = ""
        if ($ChartCfg -and $ChartCfg.series_plan) {
            $seriesName = Get-CleanSeriesName -Series $ser
            foreach ($plan in @($ChartCfg.series_plan)) {
                if (-not $plan) { continue }
                $planField = [string]$plan.field
                $planLabel = if (($plan.PSObject.Properties.Name -contains "label") -and $plan.label) { [string]$plan.label } else { "" }
                if (($planField -and $planField -eq $seriesName) -or ($planLabel -and $planLabel -eq $seriesName)) {
                    $seriesType = if (($plan.PSObject.Properties.Name -contains "chart_type") -and $plan.chart_type) { [string]$plan.chart_type } else { "" }
                    break
                }
            }
        }
        if ($seriesColors.Count -gt 0) {
            $rgb = [string]$seriesColors[($i - 1) % $seriesColors.Count]
            $c = Parse-HexColorToCom -Rgb $rgb
            if ($null -ne $c) {
                $ser.Format.Fill.ForeColor.RGB = $c
                if (-not ($seriesType -eq "column")) {
                    $ser.Format.Line.ForeColor.RGB = $c
                }
            }
        }
    }

    # Semantic overrides for code-flow charts: additions (+) green, deletions (-) red.
    if ($StyleProfile.PSObject.Properties.Name -contains "semantic_series_colors") {
        $sem = $StyleProfile.semantic_series_colors
        $addColor = $null
        $delColor = $null
        if ($sem -and ($sem.PSObject.Properties.Name -contains "additions_positive_rgb") -and $sem.additions_positive_rgb) {
            $addColor = Parse-HexColorToCom -Rgb ([string]$sem.additions_positive_rgb)
        }
        if ($sem -and ($sem.PSObject.Properties.Name -contains "deletions_negative_rgb") -and $sem.deletions_negative_rgb) {
            $delColor = Parse-HexColorToCom -Rgb ([string]$sem.deletions_negative_rgb)
        }
        if ($null -ne $addColor -or $null -ne $delColor) {
            for ($i = 1; $i -le $serCount; $i++) {
                try {
                    $ser = $Chart.SeriesCollection($i)
                    $seriesName = Get-CleanSeriesName -Series $ser
                    if ($null -ne $addColor -and ($seriesName -eq "Dodane linie (+)" -or $seriesName -eq "Additions")) {
                        $ser.Format.Fill.ForeColor.RGB = $addColor
                        $ser.Format.Line.ForeColor.RGB = $addColor
                    }
                    if ($null -ne $delColor -and ($seriesName -eq "Usunięte linie (−)" -or $seriesName -eq "Usuniete linie (−)" -or $seriesName -eq "Usuniete linie (-)" -or $seriesName -eq "Deletions")) {
                        $ser.Format.Fill.ForeColor.RGB = $delColor
                        $ser.Format.Line.ForeColor.RGB = $delColor
                    }
                } catch {}
            }
        }
    }

    # Axis labels
    $axisStyleNode = if ($acTypo -and $acTypo.PSObject.Properties.Name -contains "axis_labels") { $acTypo.axis_labels } else { $StyleProfile.axis_labels }
    $gridRgb = if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "gridlines" -and $acStyle.gridlines.PSObject.Properties.Name -contains "major_color_rgb") `
               { [string]$acStyle.gridlines.major_color_rgb } else { "B7C9DE" }
    $gridWeight = if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "gridlines" -and $acStyle.gridlines.PSObject.Properties.Name -contains "major_weight_pt") `
                  { [double]$acStyle.gridlines.major_weight_pt } else { 1.0 }
    $axisLineRgb = if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "axis" -and $acStyle.axis.PSObject.Properties.Name -contains "line_color_rgb") `
                   { [string]$acStyle.axis.line_color_rgb } else { "" }
    $axisLineWeight = if ($acStyle -and $acStyle.PSObject.Properties.Name -contains "axis" -and $acStyle.axis.PSObject.Properties.Name -contains "line_weight_pt") `
                      { [double]$acStyle.axis.line_weight_pt } else { 0.0 }

    try {
        $valueAxis = $Chart.Axes(2)
        if ($valueAxis -and $axisStyleNode) {
            Apply-TextStyle -FontObject $valueAxis.TickLabels.Font -StyleNode $axisStyleNode
            $valueAxis.HasMajorGridlines = $true
            $gc = Parse-HexColorToCom -Rgb $gridRgb
            if ($null -ne $gc) { $valueAxis.MajorGridlines.Format.Line.ForeColor.RGB = $gc }
            if ($gridWeight -gt 0) { try { $valueAxis.MajorGridlines.Format.Line.Weight = $gridWeight } catch {} }
            if ($axisLineRgb) { $ac2 = Parse-HexColorToCom -Rgb $axisLineRgb; if ($null -ne $ac2) { try { $valueAxis.Format.Line.ForeColor.RGB = $ac2 } catch {} } }
            if ($axisLineWeight -gt 0) { try { $valueAxis.Format.Line.Weight = $axisLineWeight } catch {} }
            if ($acStyle) { try { $valueAxis.HasMinorGridlines = $false } catch {} }
        }
    } catch {}
    try {
        $secondaryValueAxis = $Chart.Axes(2, 2)
        if ($secondaryValueAxis -and $axisStyleNode) {
            Apply-TextStyle -FontObject $secondaryValueAxis.TickLabels.Font -StyleNode $axisStyleNode
            try { $secondaryValueAxis.HasMajorGridlines = $false } catch {}
        }
    } catch {}
    try {
        $catAxis = $Chart.Axes(1)
        if ($catAxis -and $axisStyleNode) {
            Apply-TextStyle -FontObject $catAxis.TickLabels.Font -StyleNode $axisStyleNode
            if ($axisLineRgb) { $ac2 = Parse-HexColorToCom -Rgb $axisLineRgb; if ($null -ne $ac2) { try { $catAxis.Format.Line.ForeColor.RGB = $ac2 } catch {} } }
            if ($axisLineWeight -gt 0) { try { $catAxis.Format.Line.Weight = $axisLineWeight } catch {} }
        }
    } catch {}
}

function Apply-BarStyleLayout {
    param(
        $Chart,
        $ChartCfg,
        $StyleProfile
    )
    if (-not $Chart -or -not $StyleProfile) { return }
    $chartType = [string]$ChartCfg.chart_type
    $academicMode = Get-IsAcademicModeEnabled -StyleProfile $StyleProfile
    $styleKey = ""
    if (Is-HorizontalBarChart -Type $chartType) {
        if ($chartType -eq "bar_stacked" -and $StyleProfile.PSObject.Properties.Name -contains "stacked_status_bar_style") {
            $styleKey = "stacked_status_bar_style"
        } else {
            $styleKey = if ($academicMode -and $StyleProfile.PSObject.Properties.Name -contains "bar_style_academic") { "bar_style_academic" } else { "bar_style" }
        }
    } elseif ($chartType -eq "column" -or $chartType -eq "combo") {
        $styleKey = "column_style"
        if (-not ($StyleProfile.PSObject.Properties.Name -contains $styleKey)) {
            $styleKey = if ($academicMode -and $StyleProfile.PSObject.Properties.Name -contains "bar_style_academic") { "bar_style_academic" } else { "bar_style" }
        }
    } else {
        return
    }
    if (-not ($StyleProfile.PSObject.Properties.Name -contains $styleKey)) { return }
    $barStyle = $StyleProfile.$styleKey
    $gapWidth = $null
    $overlap = $null
    if (($barStyle.PSObject.Properties.Name -contains "gap_width") -and $null -ne $barStyle.gap_width) {
        $gapWidth = [int]$barStyle.gap_width
    }
    if (($barStyle.PSObject.Properties.Name -contains "overlap") -and $null -ne $barStyle.overlap) {
        $overlap = [int]$barStyle.overlap
    }
    if (($ChartCfg.PSObject.Properties.Name -contains "column_gap_width") -and $null -ne $ChartCfg.column_gap_width) {
        $gapWidth = [int]$ChartCfg.column_gap_width
    }
    if (($ChartCfg.PSObject.Properties.Name -contains "column_overlap") -and $null -ne $ChartCfg.column_overlap) {
        $overlap = [int]$ChartCfg.column_overlap
    }
    if ($chartType -eq "bar_stacked") {
        # For stacked bars we enforce shared plane geometry.
        if ($null -eq $overlap) { $overlap = 100 }
    }
    if ($null -eq $gapWidth -and $null -eq $overlap) { return }
    try {
        foreach ($group in @($Chart.ChartGroups())) {
            if (-not $group) { continue }
            if ($null -ne $gapWidth) { try { $group.GapWidth = $gapWidth } catch {} }
            if ($null -ne $overlap) { try { $group.Overlap = $overlap } catch {} }
        }
    } catch {}
    $seriesBorderVisible = $true
    if ($barStyle.PSObject.Properties.Name -contains "series_border_visible") { $seriesBorderVisible = [bool]$barStyle.series_border_visible }
    $seriesBorderWeight = 0.5
    if ($barStyle.PSObject.Properties.Name -contains "series_border_weight_pt") { $seriesBorderWeight = [double]$barStyle.series_border_weight_pt }
    $seriesBorderRgb = $null
    if ($barStyle.PSObject.Properties.Name -contains "series_border_rgb" -and $barStyle.series_border_rgb) {
        $seriesBorderRgb = Parse-HexColorToCom -Rgb ([string]$barStyle.series_border_rgb)
    }
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $ser = $Chart.SeriesCollection($i)
            $seriesChartType = $null
            try { $seriesChartType = [int]$ser.ChartType } catch {}
            if (Is-HorizontalBarChart -Type $chartType) {
                # Horizontal bars are the wide bars visible in comparison charts.
            } elseif ($seriesChartType -ne 51) {
                # For column/combo charts only the visible column series gets the border contract.
                continue
            }
            if ($seriesBorderVisible) {
                try { $ser.Format.Line.Visible = $true } catch {}
                try { $ser.Format.Line.Weight = $seriesBorderWeight } catch {}
                if ($null -ne $seriesBorderRgb) { try { $ser.Format.Line.ForeColor.RGB = $seriesBorderRgb } catch {} }
            } else {
                try { $ser.Format.Line.Visible = $false } catch {}
            }
        }
    } catch {}
}

function Get-OrderedChartConfigs {
    param(
        [object[]]$Charts
    )
    if (-not $Charts -or $Charts.Count -eq 0) { return @() }
    $sheetOrder = New-Object System.Collections.ArrayList
    foreach ($chart in @($Charts)) {
        if (-not $chart) { continue }
        $sheetName = [string]$chart.sheet
        if ([string]::IsNullOrWhiteSpace($sheetName)) { continue }
        if (-not $sheetOrder.Contains($sheetName)) { [void]$sheetOrder.Add($sheetName) }
    }
    $ordered = New-Object System.Collections.ArrayList
    foreach ($sheetName in @($sheetOrder)) {
        $sheetCharts = @($Charts | Where-Object { [string]$_.sheet -eq $sheetName })
        $synthesisCharts = @($sheetCharts | Where-Object { [string]$_.chart_mode -eq "sheet_synthesis" })
        $otherCharts = @($sheetCharts | Where-Object { [string]$_.chart_mode -ne "sheet_synthesis" })
        foreach ($c in @($synthesisCharts + $otherCharts)) { [void]$ordered.Add($c) }
    }
    return @($ordered)
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
        $StyleProfile,
        [string]$SourceType = ""
    )
    if (-not $Chart -or -not $ChartCfg -or -not (Is-HorizontalBarChart -Type ([string]$ChartCfg.chart_type))) { return }
    if (($ChartCfg.PSObject.Properties.Name -contains "disable_point_highlight") -and $ChartCfg.disable_point_highlight -eq $true) { return }
    if ([string]$ChartCfg.chart_type -eq "bar_stacked") { return }
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
        $academicMode = Get-IsAcademicModeEnabled -StyleProfile $StyleProfile
        $domainHighlightKey = if ($academicMode) { "domain_highlight_academic" } else { "domain_highlight" }
        $domainColors = $null
        if ($SourceType -and $StyleProfile.highlight.PSObject.Properties.Name -contains $domainHighlightKey) {
            $domainMap = $StyleProfile.highlight.$domainHighlightKey
            if ($domainMap -and $domainMap.PSObject.Properties.Name -contains $SourceType) {
                $domainColors = $domainMap.$SourceType
            }
        }
        if ($domainColors) {
            if ($domainColors.PSObject.Properties.Name -contains "venom_fill_rgb" -and $domainColors.venom_fill_rgb) {
                $highlightFill = Parse-HexColorToCom -Rgb ([string]$domainColors.venom_fill_rgb)
            }
            if ($domainColors.PSObject.Properties.Name -contains "peer_fill_rgb" -and $domainColors.peer_fill_rgb) {
                $contextFill = Parse-HexColorToCom -Rgb ([string]$domainColors.peer_fill_rgb)
            }
        } else {
            if (($StyleProfile.highlight.PSObject.Properties.Name -contains "highlight_fill_rgb") -and $StyleProfile.highlight.highlight_fill_rgb) {
                $highlightFill = Parse-HexColorToCom -Rgb ([string]$StyleProfile.highlight.highlight_fill_rgb)
            }
            if (($StyleProfile.highlight.PSObject.Properties.Name -contains "context_fill_rgb") -and $StyleProfile.highlight.context_fill_rgb) {
                $contextFill = Parse-HexColorToCom -Rgb ([string]$StyleProfile.highlight.context_fill_rgb)
            }
        }
    }
    if ($null -eq $highlightFill -and $null -eq $contextFill) { return }
    $series = $null
    try { $series = $Chart.SeriesCollection(1) } catch { $series = $null }
    if (-not $series) { return }
    $borderColor = $null
    if ($StyleProfile -and $StyleProfile.PSObject.Properties.Name -contains "bar_style" -and $StyleProfile.bar_style) {
        $barStyle = $StyleProfile.bar_style
        if ($barStyle.PSObject.Properties.Name -contains "series_border_rgb" -and $barStyle.series_border_rgb) {
            $borderColor = Parse-HexColorToCom -Rgb ([string]$barStyle.series_border_rgb)
        }
    }

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
                if ($null -ne $borderColor) {
                    try { $series.Points($pointIndex).Format.Line.ForeColor.RGB = $borderColor } catch {}
                }
            }
        } elseif ($null -ne $contextFill) {
            try { $series.Points($pointIndex).Format.Fill.ForeColor.RGB = $contextFill } catch {}
            if ($null -ne $borderColor) {
                try { $series.Points($pointIndex).Format.Line.ForeColor.RGB = $borderColor } catch {}
            }
        }
    }
}

function Apply-PhaseFillColors {
    param(
        $Chart,
        $ChartCfg,
        $ControlProfile,
        $StyleProfile
    )
    if (-not $Chart -or -not $ChartCfg -or -not $ControlProfile) { return }
    if (-not ($ControlProfile.PSObject.Properties.Name -contains "phase_background") -or -not $ControlProfile.phase_background) { return }
    $phaseBackground = $ControlProfile.phase_background
    $academicMode = Get-IsAcademicModeEnabled -StyleProfile $StyleProfile
    $colorKey = if ($academicMode) { "phase_fill_colors_academic" } else { "phase_fill_colors" }
    if (-not ($phaseBackground.PSObject.Properties.Name -contains $colorKey) -or -not $phaseBackground.$colorKey) { return }
    $phaseColors = $phaseBackground.$colorKey
    if (-not $ChartCfg.series_plan) { return }
    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    if ($phaseLabels.Count -eq 0) { return }
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $ser = $Chart.SeriesCollection($i)
            $seriesName = Get-CleanSeriesName -Series $ser
            if (-not $phaseLabels.Contains($seriesName)) { continue }
            $phaseKey = ""
            foreach ($plan in @($ChartCfg.series_plan)) {
                if (-not $plan) { continue }
                $planLabel = if (($plan.PSObject.Properties.Name -contains "label") -and $plan.label) { [string]$plan.label } else { [string]$plan.field }
                if ($planLabel -eq $seriesName) { $phaseKey = [string]$plan.field; break }
            }
            if (-not $phaseKey) { continue }
            if (-not ($phaseColors.PSObject.Properties.Name -contains $phaseKey)) { continue }
            $rgb = [string]$phaseColors.$phaseKey
            $c = Parse-HexColorToCom -Rgb $rgb
            if ($null -ne $c) { try { $ser.Format.Fill.ForeColor.RGB = $c } catch {} }
        }
    } catch {}
}

function Apply-LineSeriesStyle {
    param(
        $Chart,
        $ChartCfg,
        $StyleProfile
    )
    if (-not $Chart -or -not $StyleProfile) { return }
    $lineStyleCfg = $null
    if ($StyleProfile.PSObject.Properties.Name -contains "line_style") { $lineStyleCfg = $StyleProfile.line_style }
    if (-not $lineStyleCfg) { return }
    $chartType = [string]$ChartCfg.chart_type
    if ($chartType -ne "line" -and $chartType -ne "combo") { return }
    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    $primaryWeight   = if ($lineStyleCfg.PSObject.Properties.Name -contains "primary_line_width_pt")    { [double]$lineStyleCfg.primary_line_width_pt }    else { 2.0 }
    $secondaryWeight = if ($lineStyleCfg.PSObject.Properties.Name -contains "secondary_line_width_pt")  { [double]$lineStyleCfg.secondary_line_width_pt }  else { 1.0 }
    $markerVisible   = if ($lineStyleCfg.PSObject.Properties.Name -contains "marker_visible")           { [bool]$lineStyleCfg.marker_visible }             else { $false }
    $markerStyle     = if ($lineStyleCfg.PSObject.Properties.Name -contains "marker_style")             { [string]$lineStyleCfg.marker_style }             else { "none" }
    $markerSize      = if ($lineStyleCfg.PSObject.Properties.Name -contains "marker_size_pt")           { [int]$lineStyleCfg.marker_size_pt }              else { 4 }
    $phaseLineVis    = if ($lineStyleCfg.PSObject.Properties.Name -contains "phase_series_line_visible") { [bool]$lineStyleCfg.phase_series_line_visible } else { $false }
    $referenceLineDashStyle = if ($lineStyleCfg.PSObject.Properties.Name -contains "reference_line_dash_style") { [int]$lineStyleCfg.reference_line_dash_style } else { 4 }
    $xlMarkerStyleNone = -4142
    $xlMarkerStyleCircle = 8
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $ser = $Chart.SeriesCollection($i)
            $seriesName = Get-CleanSeriesName -Series $ser
            $seriesSemantics = ""
            if ($phaseLabels -contains $seriesName) {
                if (-not $phaseLineVis) { try { $ser.Format.Line.Visible = $false } catch {} }
                continue
            }
            $seriesType = ""
            if ($ChartCfg -and $ChartCfg.series_plan) {
                foreach ($plan in @($ChartCfg.series_plan)) {
                    if (-not $plan) { continue }
                    $planField = [string]$plan.field
                    $planLabel = if (($plan.PSObject.Properties.Name -contains "label") -and $plan.label) { [string]$plan.label } else { "" }
                    if (($planField -and $planField -eq $seriesName) -or ($planLabel -and $planLabel -eq $seriesName)) {
                        $seriesType = if (($plan.PSObject.Properties.Name -contains "chart_type") -and $plan.chart_type) { [string]$plan.chart_type } else { "" }
                        $seriesSemantics = if (($plan.PSObject.Properties.Name -contains "metric_semantics") -and $plan.metric_semantics) { [string]$plan.metric_semantics } else { "" }
                        break
                    }
                }
            }
            if ($seriesType -and ($seriesType -ne "line" -and $seriesType -ne "combo" -and $seriesType -ne "area" -and $seriesType -ne "area_stacked" -and $seriesType -ne "area_100")) {
                continue
            }
            $weight = $primaryWeight
            try { if ($ser.AxisGroup -eq 2) { $weight = $secondaryWeight } } catch {}
            try { $ser.Format.Line.Visible = $true } catch {}
            try { $ser.Format.Line.Weight = $weight } catch {}
            if ($seriesSemantics -eq "period_reference_line") {
                try { $ser.Format.Line.DashStyle = $referenceLineDashStyle } catch {}
            }
            if (-not $markerVisible -or $markerStyle -eq "none") {
                try { $ser.MarkerStyle = $xlMarkerStyleNone } catch {}
                try { $ser.MarkerSize = 2 } catch {}
            } elseif ($markerStyle -eq "circle") {
                try { $ser.MarkerStyle = $xlMarkerStyleCircle } catch {}
                try { $ser.MarkerSize = $markerSize } catch {}
            }
        }
    } catch {}
}

function Apply-DataLabels {
    param(
        $Chart,
        $ChartCfg,
        $StyleProfile
    )
    if (-not $Chart -or -not $StyleProfile) { return }
    $chartType = [string]$ChartCfg.chart_type
    if (-not (Is-HorizontalBarChart -Type $chartType)) { return }
    if (($ChartCfg.PSObject.Properties.Name -contains "data_labels_mode") -and [string]$ChartCfg.data_labels_mode -eq "none") { return }
    if (($ChartCfg.PSObject.Properties.Name -contains "disable_data_labels") -and $ChartCfg.disable_data_labels -eq $true) { return }
    $dataLabelsCfg = $null
    if ($StyleProfile.PSObject.Properties.Name -contains "data_labels") {
        $dl = $StyleProfile.data_labels
        if ($dl -and $dl.PSObject.Properties.Name -contains "comparison_bar") { $dataLabelsCfg = $dl.comparison_bar }
    }
    if (-not $dataLabelsCfg) { return }
    $fontSize    = if ($dataLabelsCfg.PSObject.Properties.Name -contains "font_size")      { [int]$dataLabelsCfg.font_size }         else { 8 }
    $fontColorRgb = if ($dataLabelsCfg.PSObject.Properties.Name -contains "font_color_rgb") { [string]$dataLabelsCfg.font_color_rgb } else { "374151" }
    $numFormat   = if ($dataLabelsCfg.PSObject.Properties.Name -contains "number_format")  { [string]$dataLabelsCfg.number_format }  else { "#,##0" }
    $fontColor   = Parse-HexColorToCom -Rgb $fontColorRgb
    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    try {
        for ($i = 1; $i -le [int]$Chart.SeriesCollection().Count; $i++) {
            $ser = $Chart.SeriesCollection($i)
            $seriesName = Get-CleanSeriesName -Series $ser
            if ($phaseLabels -contains $seriesName) { continue }
            try { $ser.HasDataLabels = $true } catch { continue }
            try {
                $labels = $ser.DataLabels()
                try { $labels.Position = 2 } catch {}  # xlLabelPositionOutsideEnd
                $labels.Font.Size = $fontSize
                if ($null -ne $fontColor) { $labels.Font.Color = $fontColor }
                $labels.NumberFormat = $numFormat
            } catch {}
        }
    } catch {}
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
    if ([string]$ChartCfg.chart_mode -eq "sheet_synthesis") {
        if (($phaseConfig.PSObject.Properties.Name -contains "sheet_synthesis_fill_transparency") -and $null -ne $phaseConfig.sheet_synthesis_fill_transparency) {
            $fillTransparency = [double]$phaseConfig.sheet_synthesis_fill_transparency
        }
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

    $phaseLabels = @(Get-PhaseSeriesLabels -ChartCfg $ChartCfg)
    try {
        $groups = @($Chart.ChartGroups())
        $phaseGroupsStyled = 0
        foreach ($group in $groups) {
            if (-not $group) { continue }
            $groupHasPhase = $false
            $groupAxisGroup = $null
            try { $groupAxisGroup = [int]$group.AxisGroup } catch { $groupAxisGroup = $null }
            try {
                $groupSeries = $group.SeriesCollection()
                for ($si = 1; $si -le [int]$groupSeries.Count; $si++) {
                    $sName = Get-CleanSeriesName -Series $groupSeries($si)
                    if ($phaseLabels.Contains($sName)) { $groupHasPhase = $true; break }
                }
            } catch {}
            if ($groupHasPhase -and ($null -eq $groupAxisGroup -or $groupAxisGroup -eq 2)) {
                try { $group.GapWidth = $gapWidth } catch {}
                try { $group.Overlap = $overlap } catch {}
                $phaseGroupsStyled += 1
            }
        }
        if ($phaseGroupsStyled -eq 0 -and $phaseLabels.Count -gt 0) {
            if (($ChartCfg.PSObject.Properties.Name -contains "column_gap_width") -and $groups.Count -gt 1) {
                # Excel COM can expose every series for every ChartGroup in combo charts.
                # For mixed business columns + phase columns, Excel writes business groups first
                # and phase-background groups last; keep the business gap and style only the phase group.
                $phaseGroup = $groups[$groups.Count - 1]
                if ($phaseGroup) {
                    try { $phaseGroup.GapWidth = $gapWidth } catch {}
                    try { $phaseGroup.Overlap = $overlap } catch {}
                }
            } else {
                foreach ($group in $groups) {
                    if (-not $group) { continue }
                    # Fallback for Excel COM variants that do not expose enough group metadata.
                    try { $group.GapWidth = $gapWidth } catch {}
                    try { $group.Overlap = $overlap } catch {}
                }
            }
        }
    } catch {}
}

function Apply-AxisTitles {
    param(
        $Chart,
        $ChartCfg
    )
    if (-not $Chart -or -not $ChartCfg) { return }
    $xTitle = ""
    $yTitle = ""
    if (($ChartCfg.PSObject.Properties.Name -contains "x_axis_title") -and $ChartCfg.x_axis_title) {
        $xTitle = [string]$ChartCfg.x_axis_title
    }
    if (($ChartCfg.PSObject.Properties.Name -contains "y_axis_title") -and $ChartCfg.y_axis_title) {
        $yTitle = [string]$ChartCfg.y_axis_title
    }
    if (-not $xTitle -and -not $yTitle) { return }
    try {
        if ($xTitle) {
            $catAxis = $Chart.Axes(1)
            if ($catAxis) {
                try { $catAxis.HasTitle = $true } catch {}
                try { $catAxis.AxisTitle.Text = $xTitle } catch {}
            }
        }
    } catch {}
    try {
        if ($yTitle) {
            $valAxis = $Chart.Axes(2)
            if ($valAxis) {
                try { $valAxis.HasTitle = $true } catch {}
                try { $valAxis.AxisTitle.Text = $yTitle } catch {}
            }
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

    foreach ($chartCfg in @(Get-OrderedChartConfigs -Charts @($chartSpec.charts))) {
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
                    if ([string]$chartCfg.chart_type -eq "bar_stacked") {
                        $resolvedYCols = @()
                        $allResolved = $true
                        foreach ($seriesDefCheck in $ySeriesDefs) {
                            $headerCheck = [string]$seriesDefCheck.field
                            if (-not $headerCheck) { $allResolved = $false; break }
                            $colCheck = Get-ColumnIndexByHeader -Worksheet $srcSheet -Header (Resolve-SeriesHeaderAlias -Header $headerCheck) -HeaderRow $srcHeaderRow -StyleProfile $styleProfile
                            if ($colCheck -lt 1) { $allResolved = $false; break }
                            $resolvedYCols += [int]$colCheck
                        }
                        if ($allResolved -and $resolvedYCols.Count -eq $ySeriesDefs.Count) {
                            $minCol = [Math]::Min($categoryCol, ($resolvedYCols | Measure-Object -Minimum).Minimum)
                            $maxCol = [Math]::Max($categoryCol, ($resolvedYCols | Measure-Object -Maximum).Maximum)
                            $rangeWidth = ($maxCol - $minCol + 1)
                            $expectedWidth = (1 + $resolvedYCols.Count)
                            if ($categoryCol -eq $minCol -and $rangeWidth -eq $expectedWidth) {
                                try {
                                    $sourceRange = $srcSheet.Range($srcSheet.Cells.Item($chartDataStartRow, $minCol), $srcSheet.Cells.Item($chartLastRow, $maxCol))
                                    $chart.SetSourceData($sourceRange, 2)  # xlColumns
                                    $chart.ChartType = (Get-ChartTypeCode -Type "bar_stacked")
                                    for ($si = 1; $si -le [int]$chart.SeriesCollection().Count; $si++) {
                                        try { $chart.SeriesCollection($si).ChartType = (Get-ChartTypeCode -Type "bar_stacked") } catch {}
                                        try { $chart.SeriesCollection($si).AxisGroup = 1 } catch {}
                                        if ($si -le $ySeriesDefs.Count) {
                                            $labelOverride = [string]$ySeriesDefs[$si - 1].label
                                            $fieldFallback = [string]$ySeriesDefs[$si - 1].field
                                            if ($labelOverride -or $fieldFallback) {
                                                try { $chart.SeriesCollection($si).Name = (Resolve-SeriesLabel -Label $labelOverride -FallbackHeader $fieldFallback) } catch {}
                                            }
                                        }
                                    }
                                    $sourceType = ""
                                    if ($sheetLayout -and $sheetLayout.PSObject.Properties.Name -contains "source_type" -and $sheetLayout.source_type) {
                                        $sourceType = [string]$sheetLayout.source_type
                                    }
                                    Apply-ChartStyle -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile -SourceType $sourceType -ControlProfile $controlProfile
                                    Apply-BarStyleLayout -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile
                                    Apply-LineSeriesStyle -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile
                                    Apply-DataLabels -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile
                                    Apply-AxisTitles -Chart $chart -ChartCfg $chartCfg
                                    Apply-BarPointHighlight -Chart $chart -ChartCfg $chartCfg -SourceSheet $srcSheet -DataStartRow $chartDataStartRow -LastRow $chartLastRow -XColumn $categoryCol -StyleProfile $styleProfile -SourceType $sourceType
                                    $indexPerSheet[$targetSheetName] = $sheetIdx + 1
                                    $created++
                                    continue
                                } catch {}
                            }
                        }
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

            if ([string]$chartCfg.chart_type -eq "bar_stacked") {
                try {
                    for ($si = 1; $si -le [int]$chart.SeriesCollection().Count; $si++) {
                        try { $chart.SeriesCollection($si).AxisGroup = 1 } catch {}
                    }
                } catch {}
            }

            $hasSecondarySeries = $false
            $hasPhaseSeriesConfigured = $false
            foreach ($seriesDefCheck in @($ySeriesDefs)) {
                if ([string]$seriesDefCheck.axis_group -eq "secondary") {
                    $hasSecondarySeries = $true
                }
                if ([string]$seriesDefCheck.field -like "phase_*") {
                    $hasPhaseSeriesConfigured = $true
                }
            }
            Enforce-PhaseSeriesAsSecondaryColumns -Chart $chart -ChartCfg $chartCfg
            if ($hasSecondarySeries -and $chartCfg.chart_type -eq "combo" -and -not $hasPhaseSeriesConfigured) {
                Apply-SecondaryAxisScale -Chart $chart -ScaleConfig $(if ($secondaryAxisScale) { $secondaryAxisScale } else { [pscustomobject]@{ minimum = 0; maximum = 100; major_unit = 20; minimum_is_auto = $false; maximum_is_auto = $false; major_unit_is_auto = $false } })
            }
            if ($dateAxisScale -and [string]$xHeader -eq "date" -and -not $isBarHorizontal) {
                Apply-DateAxisScale -Chart $chart -ScaleConfig $dateAxisScale
            }
            $sourceType = ""
            if ($sheetLayout -and $sheetLayout.PSObject.Properties.Name -contains "source_type" -and $sheetLayout.source_type) {
                $sourceType = [string]$sheetLayout.source_type
            }
            Apply-ChartStyle -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile -SourceType $sourceType -ControlProfile $controlProfile
            Apply-BarStyleLayout -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile
            Apply-LineSeriesStyle -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile
            Apply-DataLabels -Chart $chart -ChartCfg $chartCfg -StyleProfile $styleProfile
            Apply-AxisTitles -Chart $chart -ChartCfg $chartCfg
            if ($isBarHorizontal) {
                Apply-BarPointHighlight -Chart $chart -ChartCfg $chartCfg -SourceSheet $srcSheet -DataStartRow $chartDataStartRow -LastRow $chartLastRow -XColumn $categoryCol -StyleProfile $styleProfile -SourceType $sourceType
            }
            Enforce-PhaseSeriesAsSecondaryColumns -Chart $chart -ChartCfg $chartCfg
            Apply-PhaseBackgroundStyle -Chart $chart -ChartCfg $chartCfg -ControlProfile $controlProfile
            Apply-PhaseFillColors -Chart $chart -ChartCfg $chartCfg -ControlProfile $controlProfile -StyleProfile $styleProfile
            Apply-PhaseBackgroundLayout -Chart $chart -ChartCfg $chartCfg -ControlProfile $controlProfile
            if (@(Get-PhaseSeriesIndexes -ChartCfg $chartCfg).Count -gt 0) {
                $primaryDataBounds = Get-RenderedChartSeriesBounds -Chart $chart -ChartCfg $chartCfg -AxisGroup 1
                $secondaryDataBounds = Get-RenderedChartSeriesBounds -Chart $chart -ChartCfg $chartCfg -AxisGroup 2
                Apply-DynamicPhaseScale -Chart $chart -ChartCfg $chartCfg -ControlProfile $controlProfile -PrimaryDataBounds $primaryDataBounds -SecondaryDataBounds $secondaryDataBounds
            }
            if (($chartCfg.PSObject.Properties.Name -contains "primary_axis_scale") -and $chartCfg.primary_axis_scale) {
                Apply-PrimaryAxisScale -Chart $chart -ScaleConfig $chartCfg.primary_axis_scale
            }
            if (($chartCfg.PSObject.Properties.Name -contains "secondary_axis_scale") -and $chartCfg.secondary_axis_scale) {
                Apply-SecondaryAxisScale -Chart $chart -ScaleConfig $chartCfg.secondary_axis_scale
            }
            if (($chartCfg.PSObject.Properties.Name -contains "phase_background_value") -and $null -ne $chartCfg.phase_background_value) {
                $phaseValue = 0.0
                if (Try-ConvertToDouble -Value $chartCfg.phase_background_value -Result ([ref]$phaseValue)) {
                    foreach ($phaseIndex in @(Get-PhaseSeriesIndexes -ChartCfg $chartCfg)) {
                        try {
                            $phaseSeries = $chart.SeriesCollection([int]$phaseIndex)
                            $pointCount = [int]$phaseSeries.Points().Count
                            $phaseVals = New-Object object[] $pointCount
                            for ($pv = 0; $pv -lt $pointCount; $pv++) { $phaseVals[$pv] = [double]$phaseValue }
                            $phaseSeries.Values = $phaseVals
                        } catch {}
                    }
                }
            }
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
