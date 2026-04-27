[CmdletBinding()]
param(
    [string]$WordInputDocx = "",
    [string]$WordOutputDocx = "",
    [string]$WordMapCsv = "",
    [string]$StagingRoot = "C:\temp\205F_word_bookmarks_staging",
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
    if (-not $WordInputDocx) {
        $WordInputDocx = Join-Path $base "produkty\word\final\Projekt_Koncowy_Pieniak_FINAL8_bibliografia_pl_miesiace_gotowe.docx"
    }
    if (-not $WordOutputDocx) {
        $WordOutputDocx = Join-Path $base "produkty\word\final\Projekt_Koncowy_Pieniak_FINAL8_bibliografia_pl_miesiace_gotowe_v01.docx"
    }
    if (-not $WordMapCsv) {
        $WordMapCsv = Join-Path $base "205F\inputs\205F_word_embed_map_v01.csv"
    }
    return @{
        WordInputDocx = $WordInputDocx
        WordOutputDocx = $WordOutputDocx
        WordMapCsv = $WordMapCsv
    }
}

$paths = Resolve-DefaultPaths
$WordInputDocx = $paths.WordInputDocx
$WordOutputDocx = $paths.WordOutputDocx
$WordMapCsv = $paths.WordMapCsv

if (-not (Test-Path -LiteralPath $WordInputDocx)) { throw "Missing Word input docx: $WordInputDocx" }
if (-not (Test-Path -LiteralPath $WordMapCsv)) { throw "Missing map csv: $WordMapCsv" }

$mapRows = Import-Csv -LiteralPath $WordMapCsv

if (-not (Test-Path -LiteralPath $StagingRoot)) {
    New-Item -Path $StagingRoot -ItemType Directory -Force | Out-Null
}

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$runDir = Join-Path $StagingRoot ("run_" + $stamp + "_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -Path $runDir -ItemType Directory -Force | Out-Null
$localInputDoc = Join-Path $runDir "input.docx"
$localOutputDoc = Join-Path $runDir "output.docx"

$outDir = Split-Path -Parent $WordOutputDocx
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

Copy-Item -LiteralPath $WordInputDocx -Destination $localInputDoc -Force

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($localInputDoc)

    $insertedSectionTitle = $false
    $inserted = 0
    $existing = 0

    foreach ($row in $mapRows) {
        $bmName = [string]$row.word_bookmark
        if (-not $bmName) { continue }

        if ($doc.Bookmarks.Exists($bmName)) {
            $existing++
            continue
        }

        if (-not $insertedSectionTitle) {
            $endRange = $doc.Content
            $endRange.Collapse(0)
            $endRange.InsertParagraphAfter()
            $endRange.Collapse(0)
            $endRange.Text = "AUTO_BOOKMARKS_205F"
            $endRange.InsertParagraphAfter()
            $insertedSectionTitle = $true
        }

        $range = $doc.Content
        $range.Collapse(0)
        $range.InsertParagraphAfter()
        $range.Collapse(0)
        $range.Text = $bmName
        [void]$doc.Bookmarks.Add($bmName, $range)
        $range.InsertParagraphAfter()
        $inserted++
    }

    $doc.SaveAs2($localOutputDoc)
    $doc.Close()
    Copy-Item -LiteralPath $localOutputDoc -Destination $WordOutputDocx -Force
    Write-Host "[S06] Bookmarks inserted: $inserted, existing: $existing"
    Write-Host "[S06] Output docx: $WordOutputDocx"
    Write-Host "[S06] Staging run dir: $runDir"
}
finally {
    if ($doc) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) }
    $word.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    if (-not $KeepStaging) {
        Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
