# Build Hitster HTML from CSV export.
# Usage: .\build.ps1 -Csv "path\to\export.csv"
param(
  [Parameter(Mandatory=$true)][string]$Csv,
  [string]$OutDir = (Split-Path -Parent $PSCommandPath)
)

$ErrorActionPreference = 'Stop'

function Normalize-Track([string]$s) {
  if (-not $s) { return '' }
  $t = $s.ToLowerInvariant()
  # Remove anything in parens/brackets
  $t = [regex]::Replace($t, '\([^)]*\)', ' ')
  $t = [regex]::Replace($t, '\[[^\]]*\]', ' ')
  # Drop suffix after " - " (remaster/live/version/mix etc.)
  $i = $t.IndexOf(' - ')
  if ($i -ge 0) { $t = $t.Substring(0, $i) }
  # feat/ft/featuring
  $t = [regex]::Replace($t, '\b(feat\.?|ft\.?|featuring)\b.*', ' ')
  # & -> and
  $t = $t -replace '&', ' and '
  # Strip punctuation/symbols, collapse whitespace
  $t = [regex]::Replace($t, "[^\p{L}\p{Nd}\s]", ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}

function Normalize-Artist([string]$s) {
  if (-not $s) { return '' }
  $t = $s.ToLowerInvariant()
  # Take only the first/main artist
  foreach ($sep in @(',', ' feat', ' ft', ' featuring', ' & ', ' x ', ' vs ')) {
    $i = $t.IndexOf($sep)
    if ($i -ge 0) { $t = $t.Substring(0, $i) }
  }
  $t = [regex]::Replace($t, "[^\p{L}\p{Nd}\s]", ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}

$rows = Import-Csv -Path $Csv -Encoding UTF8
$total = $rows.Count

# Filter missing year
$withYear = $rows | Where-Object { $_.Year -match '^\d{4}$' }
$droppedNoYear = $total - $withYear.Count

# Dedupe
$seen = @{}
$kept = New-Object System.Collections.Generic.List[object]
$droppedDup = 0
foreach ($r in $withYear) {
  $key = (Normalize-Artist $r.Artist) + '|' + (Normalize-Track $r.Song)
  if ($seen.ContainsKey($key)) { $droppedDup++; continue }
  $seen[$key] = $true
  $kept.Add($r) | Out-Null
}

Write-Host "Total in CSV:    $total"
Write-Host "Dropped (year):  $droppedNoYear"
Write-Host "Dropped (dupe):  $droppedDup"
Write-Host "Kept:            $($kept.Count)"

# Build JSON for embedding
$songs = $kept | ForEach-Object {
  [pscustomobject]@{
    a = $_.Artist
    s = $_.Song
    y = [int]$_.Year
    u = $_.Link
  }
}
$songsJson = ($songs | ConvertTo-Json -Depth 3 -Compress)

$version = Get-Date -Format 'yyyy-MM-dd-HHmm'
$count = $kept.Count
$outFile = Join-Path $OutDir "hitster_v${version}_${count}songs.html"

$template = @'
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Hitster __VERSION__</title>
<script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin: 0; height: 100%; background: #0a0a0a; color: #eee; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  body { display: flex; flex-direction: column; align-items: center; padding: env(safe-area-inset-top) 16px env(safe-area-inset-bottom); }
  header { width: 100%; max-width: 480px; display: flex; justify-content: space-between; align-items: center; padding: 12px 4px; font-size: 13px; color: #888; }
  header button { background: none; border: 1px solid #333; color: #aaa; padding: 6px 10px; border-radius: 6px; font-size: 13px; }
  .stage { flex: 1; width: 100%; max-width: 480px; display: flex; align-items: center; justify-content: center; perspective: 1200px; padding: 8px 0; }
  .card {
    position: relative; width: 100%; aspect-ratio: 1/1; max-height: 70vh;
    transform-style: preserve-3d; transition: transform 0.55s cubic-bezier(.2,.7,.2,1);
    cursor: pointer;
  }
  .card.flipped { transform: rotateY(180deg); }
  .face {
    position: absolute; inset: 0; backface-visibility: hidden; -webkit-backface-visibility: hidden;
    border-radius: 14px; overflow: hidden;
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    box-shadow: 0 10px 30px rgba(0,0,0,.5);
  }
  /* Front: QR with concentric Hitster rings */
  .front { background: #000; position: relative; }
  .rings { position: absolute; inset: 0; }
  .rings svg { width: 100%; height: 100%; display: block; }
  .qr {
    position: relative; z-index: 1;
    width: 46%; aspect-ratio: 1; background: #fff; padding: 6px; border-radius: 4px;
    display: flex; align-items: center; justify-content: center;
  }
  .qr svg, .qr img { width: 100%; height: 100%; display: block; }
  /* Back: colored Hitster card */
  .back { transform: rotateY(180deg); color: #111; padding: 8% 8% 6%; text-align: center; position: relative; }
  .back .artist { font-size: clamp(18px, 5.2vw, 26px); font-weight: 600; margin-top: 0; line-height: 1.2; }
  .back .year { font-size: clamp(72px, 22vw, 130px); font-weight: 900; line-height: 0.95; letter-spacing: -3px; margin: 0.15em 0; color: #000; }
  .back .title { font-size: clamp(16px, 4.4vw, 22px); font-style: italic; line-height: 1.25; }
  .back .idx { position: absolute; bottom: 10px; right: 14px; font-size: 11px; opacity: 0.55; font-weight: 600; }
  .back .verify, .back .editBtn { position: absolute; bottom: 8px; font-size: 11px; color: #111; text-decoration: none; opacity: 0.55; padding: 4px 8px; border: 1px solid rgba(0,0,0,0.3); border-radius: 6px; background: rgba(255,255,255,0.25); cursor: pointer; }
  .back .verify { left: 12px; }
  .back .editBtn { left: 76px; border: 1px solid rgba(0,0,0,0.3); }
  .back .verify:active, .back .editBtn:active { opacity: 1; }
  .back.edited::after { content: '✎'; position: absolute; top: 10px; right: 14px; font-size: 14px; opacity: 0.55; }
  /* Edit modal */
  .modal { position: fixed; inset: 0; background: rgba(0,0,0,0.7); display: none; align-items: center; justify-content: center; z-index: 10; padding: 16px; }
  .modal.open { display: flex; }
  .modal-box { background: #1a1a1a; color: #eee; border-radius: 14px; width: 100%; max-width: 420px; padding: 20px; }
  .modal-box h2 { margin: 0 0 12px; font-size: 18px; }
  .modal-box label { display: block; font-size: 12px; color: #888; margin: 10px 0 4px; }
  .modal-box input { width: 100%; padding: 10px 12px; font-size: 16px; border-radius: 8px; border: 1px solid #333; background: #0a0a0a; color: #fff; }
  .modal-actions { display: flex; gap: 8px; margin-top: 16px; }
  .modal-actions button { flex: 1; padding: 12px; border-radius: 10px; border: none; font-weight: 600; font-size: 14px; }
  .modal-actions .save { background: #1db954; color: #fff; }
  .modal-actions .cancel { background: #2a2a2a; color: #eee; }
  .modal-actions .reset { background: #5a2a2a; color: #fbb; }
  .controls { width: 100%; max-width: 480px; display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 10px; padding: 12px 0 8px; }
  .controls button {
    padding: 16px; font-size: 15px; font-weight: 600; border-radius: 12px; border: none;
    background: #2a2a2a; color: #eee;
  }
  .controls button.primary { background: #1db954; color: #fff; }
  .controls button:active { transform: scale(0.98); }
  .controls button:disabled { opacity: 0.35; }
  .footer { width: 100%; max-width: 480px; text-align: center; padding: 6px 0 14px; font-size: 11px; color: #555; }
</style>
</head>
<body>
<header>
  <span id="counter">–</span>
  <button id="shuffleBtn">Neu mischen</button>
</header>

<div class="stage">
  <div class="card" id="card">
    <div class="face front">
      <div class="rings" id="rings"></div>
      <div class="qr" id="qr"></div>
    </div>
    <div class="face back" id="back">
      <div class="artist" id="artist"></div>
      <div class="year" id="year"></div>
      <div class="title" id="title"></div>
      <div class="idx" id="idx"></div>
      <a class="verify" id="verify" href="#" target="_blank" rel="noopener" onclick="event.stopPropagation()">Google ↗</a>
      <button class="editBtn" id="editBtn" onclick="event.stopPropagation(); openEdit()">Bearbeiten</button>
    </div>
  </div>
</div>

<div class="controls">
  <button id="prevBtn">Zurück</button>
  <button id="flipBtn">Umdrehen</button>
  <button id="nextBtn" class="primary">Nächste</button>
</div>
<div class="footer">v__VERSION__ · __COUNT__ Songs</div>

<div class="modal" id="editModal">
  <div class="modal-box" onclick="event.stopPropagation()">
    <h2>Karte bearbeiten</h2>
    <label for="editArtist">Künstler</label>
    <input id="editArtist" type="text" autocomplete="off">
    <label for="editSong">Titel</label>
    <input id="editSong" type="text" autocomplete="off">
    <label for="editYear">Jahr</label>
    <input id="editYear" type="number" inputmode="numeric" min="1900" max="2099">
    <div class="modal-actions">
      <button class="cancel" onclick="closeEdit()">Abbrechen</button>
      <button class="reset" onclick="resetOverride()">Zurücksetzen</button>
      <button class="save" onclick="saveOverride()">Speichern</button>
    </div>
  </div>
</div>

<script>
const SONGS = __SONGS__;
const COLORS = ['#e8534a','#f08a3e','#f0c93a','#9ed24a','#4ac98a','#4ab7d2','#5a8de0','#a47ed2','#d26ea8','#e57e7e'];
const OVERRIDE_KEY = 'hitster_overrides_v1';

let deck = [], pos = 0;

function trackId(url) {
  const m = url && url.match(/track\/([A-Za-z0-9]+)/);
  return m ? m[1] : url;
}
function loadOverrides() {
  try { return JSON.parse(localStorage.getItem(OVERRIDE_KEY) || '{}'); } catch { return {}; }
}
function saveOverrides(o) {
  localStorage.setItem(OVERRIDE_KEY, JSON.stringify(o));
}
function effectiveSong(s) {
  const o = loadOverrides()[trackId(s.u)];
  return o ? { a: o.a ?? s.a, s: o.s ?? s.s, y: o.y ?? s.y, u: s.u, _edited: true } : s;
}

function shuffle(arr) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function renderRings() {
  // Concentric rings in Hitster colors
  const palette = ['#e8534a','#f0c93a','#9ed24a','#4ab7d2','#a47ed2','#d26ea8','#f08a3e','#4ac98a'];
  const cx = 50, cy = 50;
  let svg = `<svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet">`;
  for (let i = 0; i < 8; i++) {
    const r = 48 - i * 3.2;
    const color = palette[i % palette.length];
    svg += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${color}" stroke-width="1.4"/>`;
  }
  svg += `</svg>`;
  document.getElementById('rings').innerHTML = svg;
}

function renderQR(url) {
  const el = document.getElementById('qr');
  el.innerHTML = '';
  const qr = qrcode(0, 'M');
  qr.addData(url);
  qr.make();
  el.innerHTML = qr.createSvgTag({ scalable: true, margin: 0 });
  el.onclick = (e) => { e.stopPropagation(); window.open(url, '_blank', 'noopener'); };
}

function render() {
  const card = document.getElementById('card');
  card.classList.remove('flipped');
  const raw = deck[pos];
  const song = effectiveSong(raw);
  const back = document.getElementById('back');
  back.style.background = COLORS[pos % COLORS.length];
  back.classList.toggle('edited', !!song._edited);
  document.getElementById('counter').textContent = `${pos + 1} / ${deck.length}`;
  document.getElementById('artist').textContent = song.a;
  document.getElementById('year').textContent = song.y;
  document.getElementById('title').textContent = song.s;
  document.getElementById('idx').textContent = (pos + 1);
  document.getElementById('verify').href = 'https://www.google.com/search?q=' + encodeURIComponent(song.a + ' ' + song.s + ' release year');
  document.getElementById('prevBtn').disabled = pos === 0;
  document.getElementById('nextBtn').disabled = pos === deck.length - 1;
  renderQR(raw.u);
}

function openEdit() {
  const raw = deck[pos];
  const song = effectiveSong(raw);
  document.getElementById('editArtist').value = song.a;
  document.getElementById('editSong').value = song.s;
  document.getElementById('editYear').value = song.y;
  document.getElementById('editModal').classList.add('open');
}
function closeEdit() {
  document.getElementById('editModal').classList.remove('open');
}
function saveOverride() {
  const id = trackId(deck[pos].u);
  const overrides = loadOverrides();
  overrides[id] = {
    a: document.getElementById('editArtist').value.trim(),
    s: document.getElementById('editSong').value.trim(),
    y: parseInt(document.getElementById('editYear').value, 10) || deck[pos].y
  };
  saveOverrides(overrides);
  closeEdit();
  render();
}
function resetOverride() {
  const id = trackId(deck[pos].u);
  const overrides = loadOverrides();
  delete overrides[id];
  saveOverrides(overrides);
  closeEdit();
  render();
}

function reshuffle() {
  deck = shuffle(SONGS);
  pos = 0;
  render();
}

document.getElementById('flipBtn').onclick = () => {
  document.getElementById('card').classList.toggle('flipped');
};
document.getElementById('card').onclick = () => {
  document.getElementById('card').classList.toggle('flipped');
};
document.getElementById('nextBtn').onclick = () => {
  if (pos < deck.length - 1) { pos++; render(); }
};
document.getElementById('prevBtn').onclick = () => {
  if (pos > 0) { pos--; render(); }
};
document.getElementById('shuffleBtn').onclick = () => {
  if (confirm('Stapel wirklich neu mischen? Der aktuelle Spielverlauf geht verloren.')) reshuffle();
};

document.getElementById('editModal').onclick = closeEdit;

renderRings();
reshuffle();
</script>
</body>
</html>
'@

$html = $template `
  -replace '__VERSION__', $version `
  -replace '__COUNT__', $count `
  -replace '__SONGS__', [System.Text.RegularExpressions.Regex]::Escape($songsJson)
# Regex.Escape was wrong — restore by writing raw
$html = $template.Replace('__VERSION__', $version).Replace('__COUNT__', "$count").Replace('__SONGS__', $songsJson)

Set-Content -Path $outFile -Value $html -Encoding UTF8
Write-Host ""
Write-Host "Written: $outFile"
