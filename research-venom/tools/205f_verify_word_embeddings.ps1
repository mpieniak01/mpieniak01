[CmdletBinding()]
param(
    [string]$WordDocx = "",
    [string]$WordMapCsv = "",
    [string]$S07RunJson = "",
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
    if (-not $WordDocx) {
        $WordDocx = Join-Path $base "produkty\word\final\205F_embed_canvas_v02.docx"
    }
    if (-not $WordMapCsv) { $WordMapCsv = Join-Path $base "205F\inputs\205F_word_embed_map_v01.csv" }
    if (-not $S07RunJson) { $S07RunJson = Join-Path $base "205F\analysis\205F_word_embed_run_v01.json" }
    if (-not $OutJson) { $OutJson = Join-Path $base "205F\analysis\205F_word_embed_verify_v01.json" }
    if (-not $OutMd) { $OutMd = Join-Path $base "205F\analysis\205F_word_embed_verify_v01.md" }
    return @{
        WordDocx = $WordDocx
        WordMapCsv = $WordMapCsv
        S07RunJson = $S07RunJson
        OutJson = $OutJson
        OutMd = $OutMd
    }
}

$paths = Resolve-DefaultPaths
$WordDocx = $paths.WordDocx
$WordMapCsv = $paths.WordMapCsv
$S07RunJson = $paths.S07RunJson
$OutJson = $paths.OutJson
$OutMd = $paths.OutMd

if (-not (Test-Path -LiteralPath $WordDocx)) { throw "Missing Word docx: $WordDocx" }
if (-not (Test-Path -LiteralPath $WordMapCsv)) { throw "Missing map csv: $WordMapCsv" }

$mapRows = @(
    Import-Csv -LiteralPath $WordMapCsv | Where-Object {
        $status = ([string]$_.status).Trim().ToLowerInvariant()
        $status -ne "disabled" -and $status -ne "skip" -and $status -ne "inactive"
    }
)

$s07 = $null
$s07PerChart = @{}
$s07FailedCount = $null
$s07Exists = Test-Path -LiteralPath $S07RunJson
if ($s07Exists) {
    $s07 = Get-Content -LiteralPath $S07RunJson -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($item in @($s07.per_chart)) {
        $key = [string]$item.chart_id
        if ($key) { $s07PerChart[$key] = $item }
    }
    $s07FailedCount = [int]$s07.run.failed_count
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($WordDocx, $false, $true)

    $checks = @()
    foreach ($row in $mapRows) {
        $bm = [string]$row.word_bookmark
        $chartId = [string]$row.chart_id
        if (-not $bm -or -not $chartId) { continue }

        $exists = $doc.Bookmarks.Exists($bm)
        $inlineShapesInRange = 0
        $wordStatus = "missing_bookmark"
        if ($exists) {
            $range = $doc.Bookmarks.Item($bm).Range
            $inlineShapesInRange = [int]$range.InlineShapes.Count
            if ($inlineShapesInRange -gt 0) {
                $wordStatus = "embedded_in_bookmark_range"
            } else {
                $wordStatus = "bookmark_without_inline_shape"
            }
        }

        $s07Status = "missing_s07_result"
        if ($s07PerChart.ContainsKey($chartId)) {
            $s07Status = [string]$s07PerChart[$chartId].status
        } elseif (-not $s07Exists) {
            $s07Status = "missing_s07_report"
        }

        $checks += [pscustomobject]@{
            chart_id = $chartId
            word_bookmark = $bm
            bookmark_exists = $exists
            inline_shapes_in_bookmark_range = $inlineShapesInRange
            word_status = $wordStatus
            s07_status = $s07Status
        }
    }

    $mapped = @($checks).Count
    $embeddedInRange = @($checks | Where-Object { $_.word_status -eq "embedded_in_bookmark_range" }).Count
    $s07FailedEff = if ($null -eq $s07FailedCount) { 999999 } else { [int]$s07FailedCount }
    $finalStatus = if ($embeddedInRange -eq $mapped -and $s07FailedEff -eq 0) { "ok" } else { "failed" }

    $payload = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        word_docx = $WordDocx
        s07_run_json = $S07RunJson
        s07_report_exists = $s07Exists
        total_inline_shapes_doc = [int]$doc.InlineShapes.Count
        checks = $checks
        totals = @{
            mapped_active = $mapped
            bookmark_exists = @($checks | Where-Object { $_.bookmark_exists }).Count
            embedded_in_bookmark_range = $embeddedInRange
            s07_failed_count = $s07FailedEff
            final_status = $finalStatus
        }
    }

    $outDir = Split-Path -Parent $OutJson
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }

    $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutJson -Encoding UTF8

    $md = @()
    $md += "# 205F Word Embed Verify v01"
    $md += ""
    $md += "- generated_at: $($payload.generated_at)"
    $md += "- word_docx: $WordDocx"
    $md += "- s07_run_json: $S07RunJson"
    $md += "- s07_report_exists: $s07Exists"
    $md += "- embedded_in_bookmark_range: $($payload.totals.embedded_in_bookmark_range) / $($payload.totals.mapped_active)"
    $md += "- s07_failed_count: $($payload.totals.s07_failed_count)"
    $md += "- final_status: $($payload.totals.final_status)"
    $md += ""
    $md += "| chart_id | bookmark | word_status | s07_status | inline_shapes |"
    $md += "|---|---|---|---|---:|"
    foreach ($row in $checks) {
        $md += "| $($row.chart_id) | $($row.word_bookmark) | $($row.word_status) | $($row.s07_status) | $($row.inline_shapes_in_bookmark_range) |"
    }
    $md -join "`n" | Set-Content -LiteralPath $OutMd -Encoding UTF8

    $doc.Close($false)
    Write-Host "[S09] Verify JSON: $OutJson"
    Write-Host "[S09] Verify MD:   $OutMd"
    Write-Host "[S09] final_status=$finalStatus"

    if ($finalStatus -ne "ok") { exit 1 }
}
finally {
    if ($doc) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) }
    $word.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
