[CmdletBinding()]
param(
    [string]$WordOutputDocx = "",
    [string]$WordMapCsv = ""
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
    if (-not $WordOutputDocx) {
        $WordOutputDocx = Join-Path $repoRoot "_external\not_tracked\visualization\embed_canvas_v02.docx"
    }
    if (-not $WordMapCsv) {
        $WordMapCsv = Join-Path $base "inputs\visualization\word_embed_map_v02.csv"
    }
    return @{
        WordOutputDocx = $WordOutputDocx
        WordMapCsv = $WordMapCsv
    }
}

$paths = Resolve-DefaultPaths
$WordOutputDocx = $paths.WordOutputDocx
$WordMapCsv = $paths.WordMapCsv

if (-not (Test-Path -LiteralPath $WordMapCsv)) { throw "Missing map csv: $WordMapCsv" }
$outDir = Split-Path -Parent $WordOutputDocx
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

$mapRows = @(
    Import-Csv -LiteralPath $WordMapCsv | Where-Object {
        $status = ([string]$_.status).Trim().ToLowerInvariant()
        $status -ne "disabled" -and $status -ne "skip" -and $status -ne "inactive"
    }
)

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$doc = $null

try {
    $doc = $word.Documents.Add()
    $title = $doc.Content
    $title.Collapse(0)
    $title.Text = "VENOM RESEARCH MODEL EMBED CANVAS"
    $title.InsertParagraphAfter()
    $title.InsertParagraphAfter()

    $added = 0
    foreach ($row in $mapRows) {
        $bmName = [string]$row.word_bookmark
        if (-not $bmName) { continue }
        if ($doc.Bookmarks.Exists($bmName)) { continue }

        $range = $doc.Content
        $range.Collapse(0)
        $range.Text = $bmName
        [void]$doc.Bookmarks.Add($bmName, $range)
        $range.InsertParagraphAfter()
        $range.InsertParagraphAfter()
        $added++
    }

    $doc.SaveAs2($WordOutputDocx)
    $doc.Close($false)
    Write-Host "[CANVAS] Output: $WordOutputDocx"
    Write-Host "[CANVAS] Bookmarks added: $added"
}
finally {
    if ($doc) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) }
    $word.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
