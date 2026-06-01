# Fetch Spotify playlist + resolve release years via iTunes / MusicBrainz.
# Outputs CSV compatible with build.ps1
param(
  [string]$ClientId,
  [string]$ClientSecret,
  [string]$PlaylistUrl,
  [string]$CredsFile = (Join-Path (Split-Path -Parent $PSCommandPath) 'spotify_creds.txt'),
  [string]$OutCsv
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Load creds from file if not given as params
if ((-not $ClientId -or -not $ClientSecret -or -not $PlaylistUrl) -and (Test-Path $CredsFile)) {
  Get-Content $CredsFile | ForEach-Object {
    if ($_ -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
      switch ($Matches[1].ToLower()) {
        'client_id'     { if (-not $ClientId) { $ClientId = $Matches[2] } }
        'client_secret' { if (-not $ClientSecret) { $ClientSecret = $Matches[2] } }
        'playlist'      { if (-not $PlaylistUrl) { $PlaylistUrl = $Matches[2] } }
      }
    }
  }
}

if (-not $ClientId -or -not $ClientSecret -or -not $PlaylistUrl) {
  throw "Missing client_id / client_secret / playlist. Pass as params or put in $CredsFile."
}

# Extract playlist ID
if ($PlaylistUrl -notmatch 'playlist[/:]([A-Za-z0-9]+)') { throw "Cannot parse playlist id from $PlaylistUrl" }
$playlistId = $Matches[1]

if (-not $OutCsv) {
  $stamp = Get-Date -Format 'yyyy-MM-ddTHH-mm'
  $OutCsv = Join-Path (Split-Path -Parent $PSCommandPath) "${stamp}_fetched.csv"
}

Write-Host "Playlist ID: $playlistId"
Write-Host "Output:      $OutCsv"

# ---------- 1. Spotify token ----------
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${ClientId}:${ClientSecret}"))
$tokenResp = Invoke-RestMethod -Method Post `
  -Uri 'https://accounts.spotify.com/api/token' `
  -Headers @{ Authorization = "Basic $basic" } `
  -Body @{ grant_type = 'client_credentials' }
$token = $tokenResp.access_token
$spotifyHeaders = @{ Authorization = "Bearer $token" }
Write-Host "Got Spotify token."

# ---------- 2. Fetch all tracks (paginated) ----------
$tracks = New-Object System.Collections.Generic.List[object]
$next = "https://api.spotify.com/v1/playlists/$playlistId/tracks?limit=100&fields=next,items(track(name,artists(name),external_urls(spotify),album(release_date)))"
while ($next) {
  $page = Invoke-RestMethod -Method Get -Uri $next -Headers $spotifyHeaders
  foreach ($it in $page.items) {
    if ($null -eq $it.track) { continue }
    $t = $it.track
    $tracks.Add([pscustomobject]@{
      Name           = $t.name
      Artist         = ($t.artists | ForEach-Object { $_.name }) -join ', '
      ArtistFirst    = if ($t.artists) { $t.artists[0].name } else { '' }
      SpotifyUrl     = $t.external_urls.spotify
      SpotifyYear    = if ($t.album.release_date -match '^(\d{4})') { [int]$Matches[1] } else { $null }
    }) | Out-Null
  }
  $next = $page.next
  Write-Host "  fetched $($tracks.Count) tracks..."
}
Write-Host "Total tracks: $($tracks.Count)"

# ---------- 3. Resolve year per track ----------
function Get-YearFromItunes([string]$artist, [string]$title) {
  try {
    $q = [uri]::EscapeDataString("$artist $title")
    $u = "https://itunes.apple.com/search?term=$q&entity=song&limit=5"
    $r = Invoke-RestMethod -Method Get -Uri $u -TimeoutSec 15
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
    $r = Invoke-RestMethod -Method Get -Uri $u -Headers @{ 'User-Agent' = 'HitsterLocalBuilder/1.0 (local script)' } -TimeoutSec 15
    $years = @()
    foreach ($rec in $r.recordings) {
      if ($rec.'first-release-date' -match '^(\d{4})') { $years += [int]$Matches[1] }
    }
    if ($years.Count) { return ($years | Measure-Object -Minimum).Minimum }
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -in 429,503) {
      Start-Sleep -Seconds 2
    }
  }
  return $null
}

$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($t in $tracks) {
  $i++
  $year = $null; $source = ''
  $year = Get-YearFromItunes -artist $t.ArtistFirst -title $t.Name
  if ($year) {
    $source = 'iTunes'
  } else {
    Start-Sleep -Milliseconds 1100
    $year = Get-YearFromMusicBrainz -artist $t.ArtistFirst -title $t.Name
    if ($year) { $source = 'MusicBrainz' }
  }
  if (-not $year -and $t.SpotifyYear) {
    $year = $t.SpotifyYear
    $source = 'Spotify'
  }
  $rows.Add([pscustomobject]@{
    Artist = $t.Artist
    Song   = $t.Name
    Year   = $year
    Source = $source
    Link   = $t.SpotifyUrl
  }) | Out-Null
  if ($i % 25 -eq 0) { Write-Host "  resolved $i / $($tracks.Count) (latest: $($t.Name) -> $year [$source])" }
}

$rows | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "Wrote $($rows.Count) rows to: $OutCsv"
$withYear = ($rows | Where-Object { $_.Year }).Count
Write-Host "With year:    $withYear"
Write-Host "Without year: $($rows.Count - $withYear)"
