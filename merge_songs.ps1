# Merge new songs (TSV) into songs.json, resolve years, optionally remove bad IDs.
param(
  [string]$Tsv,
  [string]$SongsJson = (Join-Path (Split-Path -Parent $PSCommandPath) 'songs.json'),
  [string[]]$RemoveIds = @()
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Normalize-Track([string]$s) {
  if (-not $s) { return '' }
  $t = $s.ToLowerInvariant()
  $t = [regex]::Replace($t, '\([^)]*\)', ' ')
  $t = [regex]::Replace($t, '\[[^\]]*\]', ' ')
  $i = $t.IndexOf(' - ')
  if ($i -ge 0) { $t = $t.Substring(0, $i) }
  $t = [regex]::Replace($t, '\b(feat\.?|ft\.?|featuring)\b.*', ' ')
  $t = $t -replace '&', ' and '
  $t = [regex]::Replace($t, "[^\p{L}\p{Nd}\s]", ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}
function Normalize-Artist([string]$s) {
  if (-not $s) { return '' }
  $t = $s.ToLowerInvariant()
  foreach ($sep in @(',', ' feat', ' ft', ' featuring', ' & ', ' x ', ' vs ')) {
    $i = $t.IndexOf($sep)
    if ($i -ge 0) { $t = $t.Substring(0, $i) }
  }
  $t = [regex]::Replace($t, "[^\p{L}\p{Nd}\s]", ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}
function Get-YearFromItunes([string]$artist, [string]$title) {
  try {
    $q = [uri]::EscapeDataString("$artist $title")
    $u = "https://itunes.apple.com/search?term=$q&entity=song&limit=5"
    $r = Invoke-RestMethod -Method Get -Uri $u -TimeoutSec 12
    $years = @()
    foreach ($x in $r.results) {
      if ($x.releaseDate -match '^(\d{4})') { $years += [int]$Matches[1] }
    }
    if ($years.Count) { return ($years | Measure-Object -Minimum).Minimum }
  } catch { }
  return $null
}

# ---------- Load existing ----------
$existing = Get-Content $SongsJson -Raw -Encoding UTF8 | ConvertFrom-Json
$keep = New-Object System.Collections.Generic.List[object]
$removedCount = 0
foreach ($s in $existing.songs) {
  if ($RemoveIds -contains $s.id) { $removedCount++; continue }
  $keep.Add([pscustomobject]@{
    id          = $s.id
    track_name  = $s.track_name
    artist      = $s.artist
    year_init   = $s.year_init
    spotify_url = $s.spotify_url
  }) | Out-Null
}
Write-Host "Existing: $($existing.songs.Count)  Removed (per RemoveIds): $removedCount  After remove: $($keep.Count)"

# Build dedupe sets (after removal)
$ids = @{}
$keys = @{}
foreach ($s in $keep) {
  $ids[$s.id] = $true
  $keys[(Normalize-Artist $s.artist) + '|' + (Normalize-Track $s.track_name)] = $true
}

# ---------- Add new from TSV (if provided) ----------
$added = 0
$skippedDup = 0
$skippedNoYear = 0
if ($Tsv -and (Test-Path $Tsv)) {
  $lines = Get-Content $Tsv -Encoding UTF8
  $header = $lines[0] -split "`t"
  $idxName    = [array]::IndexOf($header, 'Track Name')
  $idxArtist  = [array]::IndexOf($header, 'Artist Name(s)')
  $idxRelease = [array]::IndexOf($header, 'Release Date')
  $idxUri     = [array]::IndexOf($header, 'Track URI')
  $rowCount = 0
  for ($i = 1; $i -lt $lines.Count; $i++) {
    if (-not $lines[$i].Trim()) { continue }
    $f = $lines[$i] -split "`t"
    $uri = $f[$idxUri]
    if ($uri -notmatch 'spotify:track:(.+)') { continue }
    $id = $Matches[1]
    $name = $f[$idxName]
    $artist = $f[$idxArtist]
    $spotifyYear = $null
    if ($idxRelease -ge 0 -and $idxRelease -lt $f.Count) {
      $rel = $f[$idxRelease]
      if ($rel -match '(\d{4})$') { $spotifyYear = [int]$Matches[1] }
      elseif ($rel -match '^(\d{4})') { $spotifyYear = [int]$Matches[1] }
    }
    $rowCount++

    $key = (Normalize-Artist $artist) + '|' + (Normalize-Track $name)
    if ($ids.ContainsKey($id) -or $keys.ContainsKey($key)) { $skippedDup++; continue }

    $artistFirst = ($artist -split '[,;]' | Select-Object -First 1).Trim()
    $year = Get-YearFromItunes -artist $artistFirst -title $name
    if (-not $year) { $year = $spotifyYear }
    if (-not $year) { $skippedNoYear++; continue }

    $keep.Add([pscustomobject]@{
      id          = $id
      track_name  = $name
      artist      = $artist
      year_init   = [int]$year
      spotify_url = "https://open.spotify.com/track/$id"
    }) | Out-Null
    $ids[$id] = $true
    $keys[$key] = $true
    $added++
    if ($added % 20 -eq 0) { Write-Host "  added $added so far..." }
  }
  Write-Host "TSV rows:        $rowCount"
  Write-Host "Added:           $added"
  Write-Host "Skipped (dupe):  $skippedDup"
  Write-Host "Skipped (year):  $skippedNoYear"
}

# ---------- Save ----------
$newVersion = Get-Date -Format 'yyyy-MM-dd-HHmm'
$out = [pscustomobject]@{
  version = $newVersion
  count   = $keep.Count
  songs   = $keep.ToArray()
}
$json = $out | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($SongsJson, $json, (New-Object Text.UTF8Encoding $false))
Write-Host ""
Write-Host "Wrote $($keep.Count) songs (version $newVersion) -> $SongsJson"
