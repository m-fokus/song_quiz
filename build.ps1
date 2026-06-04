# Build Music Quiz app: songs.json + index.html from a resolved CSV.
# Usage: .\build.ps1 -Csv "path\to\resolved.csv"
param(
  [Parameter(Mandatory=$true)][string]$Csv,
  [string]$OutDir = (Split-Path -Parent $PSCommandPath),
  [string]$BinId = '6a1dc80c06141515d3388249',
  [string]$AccessKey = '$2a$10$SOKMRMzDUJmD.NonXmhRGO8TssnS1gSzOtExSmOJpSBTXR6EYQYg2'
)

$ErrorActionPreference = 'Stop'

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

function Get-TrackId([string]$url) {
  if ($url -match 'track/([A-Za-z0-9]+)') { return $Matches[1] }
  return ''
}

$rows = Import-Csv -Path $Csv -Encoding UTF8
$total = $rows.Count
$withYear = $rows | Where-Object { $_.Year -match '^\d{4}$' }
$droppedNoYear = $total - $withYear.Count

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

$version = Get-Date -Format 'yyyy-MM-dd-HHmm'

$songs = $kept | ForEach-Object {
  [pscustomobject]@{
    id          = (Get-TrackId $_.Link)
    track_name  = $_.Song
    artist      = $_.Artist
    year_init   = [int]$_.Year
    spotify_url = $_.Link
  }
}
$songsObj = [pscustomobject]@{
  version = $version
  count   = $kept.Count
  songs   = $songs
}
$songsJson = $songsObj | ConvertTo-Json -Depth 4
$songsPath = Join-Path $OutDir 'songs.json'
[IO.File]::WriteAllText($songsPath, $songsJson, (New-Object Text.UTF8Encoding $false))
Write-Host "Wrote: $songsPath"

$template = @'
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Music Quiz</title>
<link rel="icon" type="image/svg+xml" href="./icon.svg">
<link rel="apple-touch-icon" href="./icon.svg">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Music Quiz">
<meta name="theme-color" content="#0a0a0a">
<script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
<style>
  :root {
    color-scheme: dark;
    /* Card size: small enough to fit width AND keep room for buttons + header */
    --card-size: min(calc(100vw - 32px), calc(100dvh - 280px), 460px);
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body {
    margin: 0;
    background: #0a0a0a;
    color: #eee;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  body {
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: env(safe-area-inset-top) 16px env(safe-area-inset-bottom);
  }

  /* Header */
  header {
    flex-shrink: 0;
    width: 100%;
    max-width: 480px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 8px;
    padding: 10px 0;
    font-size: 13px;
    color: #888;
  }
  header .counter { white-space: nowrap; }
  header .group { display: flex; gap: 6px; flex-wrap: wrap; justify-content: flex-end; }
  header button {
    background: none;
    border: 1px solid #333;
    color: #aaa;
    padding: 6px 10px;
    border-radius: 6px;
    font-size: 12px;
    cursor: pointer;
    white-space: nowrap;
  }

  /* Main: card-block centered */
  main {
    flex: 1;
    width: 100%;
    max-width: 480px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 8px 0;
    min-height: 0;
  }
  .loading { color: #888; font-size: 14px; text-align: center; }

  /* Card block: card + flip button + nav buttons (all same width) */
  .card-block {
    width: var(--card-size);
    display: flex;
    flex-direction: column;
    gap: 10px;
    perspective: 1200px;
  }

  /* Card – 3D flip container. NO overflow:hidden here (flattens 3D in browsers). */
  .card {
    position: relative;
    width: 100%;
    height: var(--card-size);
    aspect-ratio: 1 / 1;
    flex: 0 0 auto;
    min-height: 0;
    min-width: 0;
    transform-style: preserve-3d;
    transition: transform 0.55s cubic-bezier(.2,.7,.2,1);
  }
  .card.flipped { transform: rotateY(180deg); }
  .face {
    position: absolute;
    inset: 0;
    backface-visibility: hidden;
    -webkit-backface-visibility: hidden;
    border-radius: 14px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    box-shadow: 0 10px 30px rgba(0,0,0,.5);
  }

  /* Front: QR on color */
  .front { padding: 12%; }
  .qr {
    width: 100%;
    aspect-ratio: 1;
    background: #fff;
    padding: 8px;
    border-radius: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
  }
  .qr svg, .qr img { width: 100%; height: 100%; display: block; }

  /* Back: artist + year + title */
  .back {
    transform: rotateY(180deg);
    color: #111;
    text-align: center;
    padding: 16px 16px 44px;
    justify-content: space-around;
    position: relative;
  }
  .back .artist {
    font-size: clamp(18px, 5vw, 26px);
    font-weight: 700;
    line-height: 1.15;
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    word-break: break-word;
    max-width: 100%;
  }
  .back .year {
    font-size: clamp(70px, 22vw, 130px);
    font-weight: 900;
    line-height: 0.95;
    letter-spacing: -3px;
    color: #000;
  }
  .back .title {
    font-size: clamp(15px, 4.2vw, 22px);
    font-style: italic;
    font-weight: 500;
    line-height: 1.2;
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 3;
    -webkit-box-orient: vertical;
    word-break: break-word;
    max-width: 100%;
  }
  .back .idx {
    position: absolute;
    bottom: 8px;
    right: 12px;
    font-size: 10px;
    opacity: 0.5;
    font-weight: 600;
  }
  .back .actions {
    position: absolute;
    bottom: 8px;
    left: 10px;
    display: flex;
    gap: 4px;
  }
  .back .actions a,
  .back .actions button {
    font-size: 10px;
    color: #111;
    text-decoration: none;
    opacity: 0.6;
    padding: 3px 7px;
    border: 1px solid rgba(0,0,0,0.3);
    border-radius: 5px;
    background: rgba(255,255,255,0.3);
    cursor: pointer;
    font-family: inherit;
  }
  .back .actions a:active,
  .back .actions button:active { opacity: 1; }
  .back.edited::after {
    content: '✎';
    position: absolute;
    top: 8px;
    right: 12px;
    font-size: 13px;
    opacity: 0.55;
  }

  /* Flip button (full width of card-block) */
  .flip-btn {
    width: 100%;
    padding: 14px;
    font-size: 15px;
    font-weight: 600;
    border-radius: 12px;
    border: 1px solid #444;
    background: #1a1a1a;
    color: #eee;
    cursor: pointer;
  }
  .flip-btn:active { transform: scale(0.98); }

  /* Nav row: prev | next */
  .nav-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }
  .nav-row button {
    padding: 14px;
    font-size: 15px;
    font-weight: 600;
    border-radius: 12px;
    border: none;
    background: #2a2a2a;
    color: #eee;
    cursor: pointer;
  }
  .nav-row button.primary { background: #1db954; color: #fff; }
  .nav-row button:active { transform: scale(0.98); }
  .nav-row button:disabled { opacity: 0.35; }

  /* Footer */
  .footer {
    flex-shrink: 0;
    width: 100%;
    max-width: 480px;
    text-align: center;
    padding: 8px 0 12px;
    font-size: 10px;
    color: #555;
  }

  /* Toast */
  .status {
    position: fixed;
    top: 14px;
    left: 50%;
    transform: translateX(-50%);
    background: #1db954;
    color: #fff;
    padding: 6px 14px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 600;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.25s;
    z-index: 20;
  }
  .status.show { opacity: 1; }
  .status.err { background: #d04040; }

  /* Modals */
  .modal {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.7);
    display: none;
    align-items: center;
    justify-content: center;
    z-index: 10;
    padding: 16px;
  }
  .modal.open { display: flex; }
  .modal-box {
    background: #1a1a1a;
    color: #eee;
    border-radius: 14px;
    width: 100%;
    max-width: 420px;
    padding: 20px;
  }
  .modal-box h2 { margin: 0 0 4px; font-size: 18px; }
  .modal-box .sub { font-size: 12px; color: #888; margin-bottom: 8px; }
  .modal-box label { display: block; font-size: 12px; color: #888; margin: 10px 0 4px; }
  .modal-box input {
    width: 100%;
    padding: 10px 12px;
    font-size: 16px;
    border-radius: 8px;
    border: 1px solid #333;
    background: #0a0a0a;
    color: #fff;
  }
  .modal-actions { display: flex; gap: 8px; margin-top: 16px; }
  .modal-actions button {
    flex: 1;
    padding: 12px;
    border-radius: 10px;
    border: none;
    font-weight: 600;
    font-size: 14px;
    cursor: pointer;
  }
  .modal-actions .save { background: #1db954; color: #fff; }
  .modal-actions .cancel { background: #2a2a2a; color: #eee; }
  .modal-actions .reset { background: #5a2a2a; color: #fbb; }

  /* List in modal */
  .list-items { max-height: 60vh; overflow-y: auto; margin: 8px -4px 0; }
  .list-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 12px;
    border-radius: 8px;
    cursor: pointer;
  }
  .list-item:active { background: #2a2a2a; }
  .list-item .info { flex: 1; min-width: 0; }
  .list-item .title-text {
    font-size: 14px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .list-item .meta { font-size: 11px; color: #888; }
  .list-item .badge { font-size: 18px; font-weight: 800; color: #1db954; margin-left: 12px; }
  .list-item .badge.undo { color: #d04040; font-size: 16px; }
  .list-empty { text-align: center; color: #666; padding: 24px 0; font-size: 13px; }
</style>
</head>
<body>
<div id="mqGate" class="mq-gate">
  <div class="mq-gate-box">
    <h1 style="text-align:center;font-size:24px;margin:0 0 4px;color:#eee">Music Quiz</h1>
    <input type="password" id="mqGatePw" placeholder="Passwort" autocomplete="current-password">
    <button id="mqGateBtn">Öffnen</button>
    <div id="mqGateErr"></div>
  </div>
</div>
<style>
  .mq-gate { position: fixed; inset: 0; background: #0a0a0a; z-index: 9999; display: flex; align-items: center; justify-content: center; padding: 20px; }
  .mq-gate.unlocked { display: none; }
  .mq-gate-box { display: flex; flex-direction: column; gap: 12px; width: 100%; max-width: 280px; }
  .mq-gate input { padding: 12px 16px; font-size: 16px; border-radius: 8px; border: 1px solid #333; background: #1a1a1a; color: #fff; }
  .mq-gate button { padding: 12px; font-size: 14px; font-weight: 700; border-radius: 8px; border: none; background: #1db954; color: #fff; cursor: pointer; }
  .mq-gate #mqGateErr { color: #d04040; font-size: 12px; min-height: 16px; text-align: center; }
</style>
<script>
(async () => {
  const HASH = '03231b555c0bd8873659af9d9e88010b5f5af83c907b47d96957de3c84d9531f';
  async function sha(s){const b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s));return Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,'0')).join('');}
  function unlock(){document.getElementById('mqGate').classList.add('unlocked');}
  if (localStorage.getItem('mq_unlock') === '1') { unlock(); return; }
  const pw = document.getElementById('mqGatePw');
  const err = document.getElementById('mqGateErr');
  async function tryUnlock(){if(!pw.value)return;const h=await sha(pw.value);if(h===HASH){localStorage.setItem('mq_unlock','1');unlock();}else{err.textContent='Falsches Passwort';pw.value='';pw.focus();}}
  document.getElementById('mqGateBtn').addEventListener('click', tryUnlock);
  pw.addEventListener('keydown', e => { if (e.key === 'Enter') tryUnlock(); });
  setTimeout(() => pw.focus(), 100);
})();
</script>
<div class="status" id="status"></div>

<header>
  <span class="counter" id="counter">–</span>
  <div class="group">
    <button id="listBtn">Korrekturen <span id="corrCount">(0)</span></button>
    <button id="hiddenBtn">Ausgeblendet <span id="hiddenCount">(0)</span></button>
    <button id="shuffleBtn">Neu mischen</button>
  </div>
</header>

<main>
  <div class="loading" id="loading">Lade Songs…</div>
  <div class="card-block" id="cardBlock" style="display:none">
    <div class="card" id="card">
      <div class="face front" id="front">
        <div class="qr" id="qr"></div>
      </div>
      <div class="face back" id="back">
        <div class="artist" id="artist"></div>
        <div class="year" id="year"></div>
        <div class="title" id="title"></div>
        <div class="idx" id="idx"></div>
        <div class="actions">
          <a id="verify" href="#" target="_blank" rel="noopener" onclick="event.stopPropagation()">Google ↗</a>
          <button id="editBtn" onclick="event.stopPropagation(); openEdit()">Bearbeiten</button>
          <button id="hideBtn" onclick="event.stopPropagation(); hideCurrent()">Ausblenden</button>
        </div>
      </div>
    </div>
    <button class="flip-btn" id="flipBtn">Umdrehen</button>
    <div class="nav-row">
      <button id="prevBtn" disabled>Zurück</button>
      <button id="nextBtn" class="primary" disabled>Nächste</button>
    </div>
  </div>
</main>

<div class="footer" id="footer">Lade…</div>

<div class="modal" id="listModal">
  <div class="modal-box" onclick="event.stopPropagation()">
    <h2>Korrigierte Songs</h2>
    <div class="sub">Tipp einen Song, um direkt dort hinzuspringen.</div>
    <div class="list-items" id="corrList"></div>
    <div class="modal-actions">
      <button class="cancel" onclick="closeList()">Schließen</button>
    </div>
  </div>
</div>

<div class="modal" id="hiddenModal">
  <div class="modal-box" onclick="event.stopPropagation()">
    <h2>Ausgeblendete Songs</h2>
    <div class="sub">Tipp einen Song, um ihn wieder einzublenden.</div>
    <div class="list-items" id="hiddenList"></div>
    <div class="modal-actions">
      <button class="cancel" onclick="closeHidden()">Schließen</button>
    </div>
  </div>
</div>

<div class="modal" id="editModal">
  <div class="modal-box" onclick="event.stopPropagation()">
    <h2>Jahr korrigieren</h2>
    <div class="sub" id="editSongInfo"></div>
    <label for="editYear">Korrektes Jahr</label>
    <input id="editYear" type="number" inputmode="numeric" min="1900" max="2099">
    <div class="modal-actions">
      <button class="cancel" onclick="closeEdit()">Abbrechen</button>
      <button class="reset" onclick="resetOverride()">Zurücksetzen</button>
      <button class="save" onclick="saveOverride()">Speichern</button>
    </div>
  </div>
</div>

<script>
const BIN_ID = '__BIN_ID__';
const ACCESS_KEY = '__ACCESS_KEY__';
const BIN_URL = `https://api.jsonbin.io/v3/b/${BIN_ID}`;
const COLORS = ['#e8534a','#f08a3e','#f0c93a','#9ed24a','#4ac98a','#4ab7d2','#5a8de0','#a47ed2','#d26ea8','#e57e7e'];

let songs = [], corrections = {}, hidden = {};
let deck = [], pos = 0;
let songsVersion = '?';

// ---------- Toast ----------
function showStatus(msg, isErr) {
  const el = document.getElementById('status');
  el.textContent = msg;
  el.classList.toggle('err', !!isErr);
  el.classList.add('show');
  clearTimeout(showStatus._t);
  showStatus._t = setTimeout(() => el.classList.remove('show'), 1800);
}

// ---------- Data loading ----------
async function loadSongs() {
  const r = await fetch('./songs.json?v=' + Date.now());
  if (!r.ok) throw new Error('songs.json HTTP ' + r.status);
  const data = await r.json();
  songs = data.songs;
  songsVersion = data.version;
}
async function loadDb() {
  try {
    const r = await fetch(BIN_URL + '/latest', { headers: { 'X-Access-Key': ACCESS_KEY } });
    if (!r.ok) throw new Error('JSONBin HTTP ' + r.status);
    const data = await r.json();
    corrections = (data.record && data.record.corrections) || {};
    hidden = (data.record && data.record.hidden) || {};
  } catch (e) {
    console.warn('DB konnte nicht geladen werden:', e);
    showStatus('DB offline', true);
    corrections = {};
    hidden = {};
  }
}
async function saveDb() {
  const r = await fetch(BIN_URL, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'X-Access-Key': ACCESS_KEY },
    body: JSON.stringify({ corrections, hidden })
  });
  if (!r.ok) throw new Error('JSONBin PUT HTTP ' + r.status);
}

// ---------- Helpers ----------
function effectiveSong(s) {
  const c = corrections[s.id];
  if (c && c.year_correct) return { ...s, year: c.year_correct, _edited: true };
  return { ...s, year: s.year_init };
}
function visibleSongs() {
  return songs.filter(s => !hidden[s.id]);
}
function shuffle(arr) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ---------- Render ----------
function renderQR(url) {
  const el = document.getElementById('qr');
  el.innerHTML = '';
  const qr = qrcode(0, 'M');
  qr.addData(url);
  qr.make();
  el.innerHTML = qr.createSvgTag({ scalable: true, margin: 0 });
  el.onclick = (e) => { e.stopPropagation(); window.location.href = url; };
}
function render() {
  if (!deck.length) return;
  const card = document.getElementById('card');
  // If currently flipped, animate back to front first, THEN swap content
  // (so the next card's data isn't visible mid-flip).
  if (card.classList.contains('flipped')) {
    card.classList.remove('flipped');
    clearTimeout(render._t);
    render._t = setTimeout(doRender, 560);
    return;
  }
  doRender();
}
function doRender() {
  if (!deck.length) return;
  const raw = deck[pos];
  const song = effectiveSong(raw);
  const color = COLORS[pos % COLORS.length];
  const card = document.getElementById('card');
  document.getElementById('front').style.background = color;
  const back = document.getElementById('back');
  back.style.background = color;
  back.classList.toggle('edited', !!song._edited);
  document.getElementById('counter').textContent = `${pos + 1} / ${deck.length}`;
  document.getElementById('artist').textContent = song.artist;
  document.getElementById('year').textContent = song.year;
  document.getElementById('title').textContent = song.track_name;
  document.getElementById('idx').textContent = (pos + 1);
  document.getElementById('verify').href = 'https://www.google.com/search?q=' + encodeURIComponent(song.artist + ' ' + song.track_name + ' release year');
  document.getElementById('prevBtn').disabled = pos === 0;
  document.getElementById('nextBtn').disabled = pos === deck.length - 1;
  renderQR(song.spotify_url);
}
function reshuffle() {
  const vs = visibleSongs();
  if (!vs.length) {
    document.getElementById('cardBlock').style.display = 'none';
    document.getElementById('loading').style.display = '';
    document.getElementById('loading').textContent = 'Alle Songs ausgeblendet.';
    deck = [];
    return;
  }
  document.getElementById('loading').style.display = 'none';
  document.getElementById('cardBlock').style.display = '';
  deck = shuffle(vs);
  pos = 0;
  render();
}

// ---------- Counts ----------
function updateCorrCount() {
  document.getElementById('corrCount').textContent = `(${Object.keys(corrections).length})`;
}
function updateHiddenCount() {
  document.getElementById('hiddenCount').textContent = `(${Object.keys(hidden).length})`;
}

// ---------- Edit (year correction) ----------
function openEdit() {
  const raw = deck[pos];
  const song = effectiveSong(raw);
  document.getElementById('editSongInfo').textContent = `${song.artist} – ${song.track_name}`;
  document.getElementById('editYear').value = song.year;
  document.getElementById('editModal').classList.add('open');
  setTimeout(() => document.getElementById('editYear').focus(), 50);
}
function closeEdit() {
  document.getElementById('editModal').classList.remove('open');
}
async function saveOverride() {
  const raw = deck[pos];
  const y = parseInt(document.getElementById('editYear').value, 10);
  if (!y || y < 1900 || y > 2099) { showStatus('Ungültiges Jahr', true); return; }
  if (y === raw.year_init) return resetOverride();
  const prev = corrections[raw.id];
  corrections[raw.id] = { year_correct: y, correction_date: new Date().toISOString() };
  try {
    await saveDb();
    showStatus('Gespeichert');
    updateCorrCount();
    closeEdit();
    render();
  } catch (e) {
    if (prev) corrections[raw.id] = prev; else delete corrections[raw.id];
    showStatus('Speichern fehlgeschlagen', true);
    console.error(e);
  }
}
async function resetOverride() {
  const raw = deck[pos];
  const prev = corrections[raw.id];
  if (!prev) { closeEdit(); return; }
  delete corrections[raw.id];
  try {
    await saveDb();
    showStatus('Zurückgesetzt');
    updateCorrCount();
    closeEdit();
    render();
  } catch (e) {
    corrections[raw.id] = prev;
    showStatus('Zurücksetzen fehlgeschlagen', true);
    console.error(e);
  }
}

// ---------- Hide ----------
async function hideCurrent() {
  const raw = deck[pos];
  if (!raw) return;
  if (!confirm('Diesen Song dauerhaft ausblenden? Du kannst ihn später über „Ausgeblendet" wieder einblenden.')) return;
  hidden[raw.id] = { hidden_at: new Date().toISOString() };
  try {
    await saveDb();
    showStatus('Ausgeblendet');
    updateHiddenCount();
    deck.splice(pos, 1);
    if (!deck.length) { reshuffle(); return; }
    if (pos >= deck.length) pos = deck.length - 1;
    render();
  } catch (e) {
    delete hidden[raw.id];
    showStatus('Ausblenden fehlgeschlagen', true);
    console.error(e);
  }
}
async function unhide(id) {
  const prev = hidden[id];
  if (!prev) return;
  delete hidden[id];
  try {
    await saveDb();
    showStatus('Eingeblendet');
    updateHiddenCount();
    const s = songs.find(x => x.id === id);
    if (s) deck.splice(pos + 1, 0, s);
    openHidden();
  } catch (e) {
    hidden[id] = prev;
    showStatus('Einblenden fehlgeschlagen', true);
    console.error(e);
  }
}

// ---------- Modals: lists ----------
function openList() {
  const list = document.getElementById('corrList');
  const ids = Object.keys(corrections);
  if (!ids.length) {
    list.innerHTML = '<div class="list-empty">Noch keine Korrekturen vorhanden.</div>';
  } else {
    const songById = Object.fromEntries(songs.map(s => [s.id, s]));
    const items = ids.map(id => ({ id, c: corrections[id], s: songById[id] }))
      .filter(x => x.s)
      .sort((a,b) => (b.c.correction_date || '').localeCompare(a.c.correction_date || ''));
    list.innerHTML = items.map(x => {
      const safeArtist = (x.s.artist || '').replace(/</g,'&lt;');
      const safeTitle  = (x.s.track_name || '').replace(/</g,'&lt;');
      return `<div class="list-item" data-id="${x.id}">
        <div class="info">
          <div class="title-text">${safeArtist} – ${safeTitle}</div>
          <div class="meta">${x.s.year_init} → korrigiert ${new Date(x.c.correction_date).toLocaleDateString('de-DE')}</div>
        </div>
        <div class="badge">${x.c.year_correct}</div>
      </div>`;
    }).join('');
    list.querySelectorAll('.list-item').forEach(el => {
      el.onclick = () => jumpToSong(el.dataset.id);
    });
  }
  document.getElementById('listModal').classList.add('open');
}
function closeList() {
  document.getElementById('listModal').classList.remove('open');
}
function jumpToSong(id) {
  let idx = deck.findIndex(s => s.id === id);
  if (idx === -1) {
    const s = songs.find(x => x.id === id);
    if (!s || hidden[s.id]) return;
    deck = [s, ...deck.filter(x => x.id !== id)];
    idx = 0;
  }
  pos = idx;
  closeList();
  render();
}

function openHidden() {
  const list = document.getElementById('hiddenList');
  const ids = Object.keys(hidden);
  if (!ids.length) {
    list.innerHTML = '<div class="list-empty">Keine ausgeblendeten Songs.</div>';
  } else {
    const songById = Object.fromEntries(songs.map(s => [s.id, s]));
    const items = ids.map(id => ({ id, h: hidden[id], s: songById[id] }))
      .filter(x => x.s)
      .sort((a,b) => (b.h.hidden_at || '').localeCompare(a.h.hidden_at || ''));
    list.innerHTML = items.map(x => {
      const safeArtist = (x.s.artist || '').replace(/</g,'&lt;');
      const safeTitle  = (x.s.track_name || '').replace(/</g,'&lt;');
      return `<div class="list-item" data-id="${x.id}">
        <div class="info">
          <div class="title-text">${safeArtist} – ${safeTitle}</div>
          <div class="meta">${x.s.year_init} · ausgeblendet ${new Date(x.h.hidden_at).toLocaleDateString('de-DE')}</div>
        </div>
        <div class="badge undo">↩</div>
      </div>`;
    }).join('');
    list.querySelectorAll('.list-item').forEach(el => {
      el.onclick = () => unhide(el.dataset.id);
    });
  }
  document.getElementById('hiddenModal').classList.add('open');
}
function closeHidden() {
  document.getElementById('hiddenModal').classList.remove('open');
}

// ---------- Event wiring ----------
document.getElementById('flipBtn').onclick = () => document.getElementById('card').classList.toggle('flipped');
document.getElementById('nextBtn').onclick = () => { if (pos < deck.length - 1) { pos++; render(); } };
document.getElementById('prevBtn').onclick = () => { if (pos > 0) { pos--; render(); } };
document.getElementById('shuffleBtn').onclick = () => { if (confirm('Stapel wirklich neu mischen? Der aktuelle Spielverlauf geht verloren.')) reshuffle(); };
document.getElementById('listBtn').onclick = openList;
document.getElementById('hiddenBtn').onclick = openHidden;
document.getElementById('listModal').onclick = closeList;
document.getElementById('hiddenModal').onclick = closeHidden;
document.getElementById('editModal').onclick = closeEdit;

// ---------- Init ----------
(async () => {
  try {
    await Promise.all([loadSongs(), loadDb()]);
    document.getElementById('footer').textContent = `Daten v${songsVersion} · ${songs.length} Songs · App v__APP_VERSION__`;
    updateCorrCount();
    updateHiddenCount();
    reshuffle();
  } catch (e) {
    document.getElementById('loading').textContent = 'Fehler beim Laden: ' + e.message;
    console.error(e);
  }
})();
</script>
</body>
</html>
'@

$html = $template.Replace('__BIN_ID__', $BinId).Replace('__ACCESS_KEY__', $AccessKey).Replace('__APP_VERSION__', $version)
$indexPath = Join-Path $OutDir 'stable.html'
[IO.File]::WriteAllText($indexPath, $html, (New-Object Text.UTF8Encoding $false))
Write-Host "Wrote: $indexPath"
Write-Host ""
Write-Host "Done. App version: $version"
