# Process Exportify CSV: resolve original release year via iTunes (fallback: Spotify).
# Outputs CSV ready for build.ps1
param(
  [Parameter(Mandatory=$true)][string]$Csv,
  [string]$OutCsv,
  [switch]$FastSpotifyOnly,  # skip iTunes lookup, just use Spotify release year
  [switch]$UseMusicBrainz    # also try MusicBrainz when iTunes fails (slow: 1.1s/req)
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $OutCsv) {
  $stamp = Get-Date -Format 'yyyy-MM-ddTHH-mm'
  $OutCsv = Join-Path (Split-Path -Parent $PSCommandPath) "${stamp}_resolved.csv"
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

function Get-YearFromMusicBrainz([string]$artist, [string]$title) {
  try {
    $q = 'recording:"' + ($title -replace '"','\"') + '" AND artist:"' + ($artist -replace '"','\"') + '"'
    $u = 'https://musicbrainz.org/ws/2/recording?query=' + [uri]::EscapeDataString($q) + '&fmt=json&limit=5'
    $r = Invoke-RestMethod -Method Get -Uri $u -Headers @{ 'User-Agent' = 'HitsterLocalBuilder/1.0' } -TimeoutSec 15
    $years = @()
    foreach ($rec in $r.recordings) {
      if ($rec.'first-release-date' -match '^(\d{4})') { $years += [int]$Matches[1] }
    }
    if ($years.Count) { return ($years | Measure-Object -Minimum).Minimum }
  } catch { }
  return $null
}

$rows = Import-Csv -Path $Csv -Encoding UTF8
$total = $rows.Count
Write-Host "Loaded $total tracks from $Csv"

$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rows) {
  $i++
  $title  = $r.'Track Name'
  $artistFull = $r.'Artist Name(s)'
  # Take first artist for lookup (separators: ; , feat)
  $artistFirst = $artistFull -split '[;,]' | Select-Object -First 1
  $artistFirst = $artistFirst.Trim()

  $uri = $r.'Track URI'
  $link = if ($uri -match 'spotify:track:(.+)') { "https://open.spotify.com/track/$($Matches[1])" } else { '' }

  $spotifyYear = if ($r.'Release Date' -match '^(\d{4})') { [int]$Matches[1] } else { $null }

  $year = $null; $source = ''
  if (-not $FastSpotifyOnly) {
    $year = Get-YearFromItunes -artist $artistFirst -title $title
    if ($year) { $source = 'iTunes' }
    elseif ($UseMusicBrainz) {
      Start-Sleep -Milliseconds 1100
      $year = Get-YearFromMusicBrainz -artist $artistFirst -title $title
      if ($year) { $source = 'MusicBrainz' }
    }
  }
  if (-not $year -and $spotifyYear) {
    $year = $spotifyYear
    $source = 'Spotify'
  }

  $out.Add([pscustomobject]@{
    Artist = ($artistFull -replace ';', ', ')
    Song   = $title
    Year   = $year
    Source = $source
    Link   = $link
  }) | Out-Null

  if ($i % 50 -eq 0) {
    Write-Host ("  {0}/{1}  {2} -> {3} [{4}]" -f $i, $total, $title, $year, $source)
  }
}

$out | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
$withYear = ($out | Where-Object { $_.Year }).Count
Write-Host ""
Write-Host "Done. Wrote $($out.Count) rows -> $OutCsv"
Write-Host "With year:    $withYear"
Write-Host "Without year: $($out.Count - $withYear)"
Write-Host ""
Write-Host "Next: .\build.ps1 -Csv `"$OutCsv`""
