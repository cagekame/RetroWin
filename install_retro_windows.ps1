<#
  install_retro_windows.ps1
  Prepara una "mini RetroDECK" su Windows, con la stessa struttura di cartelle
  e le stesse impostazioni predefinite di RetroDECK:
    ES-DE (portable) + RetroArch + core + DuckStation (+ PCSX2 opzionale)

  Uso (PowerShell, anche non amministratore):
    powershell -ExecutionPolicy Bypass -File .\install_retro_windows.ps1
    powershell -ExecutionPolicy Bypass -File .\install_retro_windows.ps1 -Root D:\Retro -SkipPCSX2
  oppure, senza scaricare nulla a mano, con bootstrap.ps1 (vedi README.md).

  Opzioni:
    -Force        riscarica e reinstalla i programmi
    -ResetConfig  riapplica le impostazioni predefinite RetroDECK
                  (come "reset" in RetroDECK; prima fa un backup .bak)
                  e poi le personalizzazioni RetroWin
    -SkipPCSX2    non installa PCSX2
    -NoDesktopShortcut  non crea il collegamento RetroWin sul Desktop

  Personalizzazioni RetroWin (cartella custom\ accanto allo script):
    overrides\  solo le voci che cambiano rispetto a RetroDECK
    files\      file copiati cosi' come sono in <Root>
    branding\   splash e icona
  Si applicano sopra le impostazioni RetroDECK (dettagli in README.md).

  Struttura (come ~/retrodeck in RetroDECK, nomi da retrodeck.json):
    <Root>\roms bios saves states screenshots shaders cheats mods
           texture_packs borders logs backups storage videos
    <Root>\ES-DE\downloaded_media themes gamelists collections scripts
                 screensavers custom_systems
    <Root>\Apps\   programmi (in RetroDECK sono dentro il Flatpak)
      ES-DE\  Emulators\RetroArch  Emulators\DuckStation  Emulators\PCSX2

  Lo script e' idempotente: salta cio' che e' gia' installato, applica le
  impostazioni RetroDECK una sola volta e ad ogni esecuzione riallinea solo i
  percorsi (come "postmove" in RetroDECK). Non cancella file dell'utente:
  quando deve sostituire una cartella con un collegamento ne sposta prima il
  contenuto. Alla fine scrive report_struttura.txt nella cartella Root.
#>
param(
    [string]$Root = "$env:USERPROFILE\RetroWin",
    [switch]$SkipPCSX2,
    [switch]$Force,
    [switch]$ResetConfig,
    [switch]$NoDesktopShortcut
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest molto piu' veloce
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------- CONFIGURAZIONE (modificabile) ----------------
# ES-DE: l'ultima release viene letta dall'API GitLab (progetto 18817634 =
# es-de/emulationstation-de) cercando l'asset "*-x64_Portable.zip".
# Se l'API non risponde si usa il link fisso (3.5.0). In alternativa scarica
# lo zip "Windows portable" da https://es-de.org, mettilo in
# <Root>\Apps\_download\esde.zip e rilancia.
$EsDeReleaseApi  = "https://gitlab.com/api/v4/projects/18817634/releases/permalink/latest"
$EsDeAssetRegex  = '-x64_Portable\.zip$'
$EsDeFallbackUrl = "https://gitlab.com/es-de/emulationstation-de/-/package_files/357718057/download"

# L'indice usa link assoluti: href="/stable/1.22.2/"
$RetroArchStableIndex = "https://buildbot.libretro.com/stable/"
$CoreBase  = "https://buildbot.libretro.com/nightly/windows/x86_64/latest/"
$CheatsUrl = "https://buildbot.libretro.com/assets/frontend/cheats.zip"

# Impostazioni ufficiali RetroDECK (repo RetroDECK/components), fissate a un
# commit preciso perche' il risultato sia riproducibile (commit del 2026-10-03).
$RdCommit  = "fcd0d72995d7aa2e741e2753ac6914025b2ff1ac"
$RdBase    = "https://raw.githubusercontent.com/RetroDECK/components/$RdCommit/"
$RdFiles   = [ordered]@{
    "es_settings.xml" = "es-de/rd_assets/rd_config/es_settings.xml"
    "retroarch.cfg"   = "retroarch/rd_assets/rd_config/retroarch.cfg"
    "settings.ini"    = "duckstation/rd_assets/rd_config/settings.ini"
    "retroarch-core-options.cfg" = "retroarch/rd_assets/rd_config/retroarch-core-options.cfg"
}
# Tema ES-DE ufficiale RetroDECK (repo RetroDECK/RetroDECK-theme, 2026-10-03).
$RdThemeUrl  = "https://github.com/RetroDECK/RetroDECK-theme/archive/c50205283cbb4a1bb2b05c11e897cf129f23f076.zip"
$RdThemeName = "RetroDECK-theme-main"   # nome usato da RetroDECK in es_settings.xml

# Core libretro da installare (nomi verificati sul buildbot).
$Cores = @(
    "fceumm",            # NES
    "snes9x",            # SNES
    "gambatte",          # Game Boy / Color
    "mgba",              # GBA
    "genesis_plus_gx",   # Master System / Mega Drive / Game Gear / Sega CD
    "mednafen_pce_fast", # PC Engine
    "mupen64plus_next",  # N64
    "fbneo"              # Arcade / Neo Geo
)
# ----------------------------------------------------------------

# Personalizzazioni RetroWin rispetto a RetroDECK (vedi README.md)
$Custom = Join-Path $PSScriptRoot "custom"
$Brand  = Join-Path $Custom "branding"

$Apps    = Join-Path $Root "Apps"
$Dl      = Join-Path $Apps "_download"
$Emu     = Join-Path $Apps "Emulators"
$EsDeApp = Join-Path $Apps "ES-DE"
$EsDeCfg = Join-Path $EsDeApp "ES-DE"          # dati interni di ES-DE portable
$Preset  = Join-Path $Apps "_preset"            # segna le impostazioni RetroDECK gia' applicate
$Results = [ordered]@{}
$PresetApplied = $false   # impostazioni RetroDECK applicate in questa esecuzione

# Cartelle utente RetroDECK (retrodeck.json -> paths). PortMaster escluso: solo Linux.
$Paths = [ordered]@{
    roms             = Join-Path $Root "roms"
    saves            = Join-Path $Root "saves"
    states           = Join-Path $Root "states"
    shaders          = Join-Path $Root "shaders"
    bios             = Join-Path $Root "bios"
    backups          = Join-Path $Root "backups"
    downloaded_media = Join-Path $Root "ES-DE\downloaded_media"
    themes           = Join-Path $Root "ES-DE\themes"
    logs             = Join-Path $Root "logs"
    screenshots      = Join-Path $Root "screenshots"
    mods             = Join-Path $Root "mods"
    texture_packs    = Join-Path $Root "texture_packs"
    borders          = Join-Path $Root "borders"
    cheats           = Join-Path $Root "cheats"
    storage          = Join-Path $Root "storage"
    videos           = Join-Path $Root "videos"
}

function Say($m)  { Write-Host "[*] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }

function New-Dir($p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }

# 7-Zip senza installare nulla (per verifiche/estrazioni veloci se c'e' gia').
function Get-7zPath {
    $c = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")
    foreach ($p in $c) { if (Test-Path $p) { return $p } }
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# 7-Zip obbligatorio (archivi .7z): se manca prova winget.
function Find-7z {
    $p = Get-7zPath
    if ($p) { return $p }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Say "7-Zip non trovato: provo a installarlo con winget"
        winget install --id 7zip.7zip -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
        $p = Get-7zPath
        if ($p) { return $p }
    }
    throw "7-Zip non trovato. Installalo da https://www.7-zip.org e rilancia lo script."
}

# Verifica che un file scaricato sia completo: archivi testati, altri file non vuoti.
function Test-Download($path) {
    if (-not (Test-Path $path)) { return $false }
    if ($path -notmatch '\.(zip|7z)$') { return ((Get-Item $path).Length -gt 0) }
    $7z = Get-7zPath
    if ($7z) {
        & $7z t $path -y -bso0 -bse0 -bsp0 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    if ($path -match '\.zip$') {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $z = [IO.Compression.ZipFile]::OpenRead($path); $z.Dispose(); return $true
        } catch { return $false }
    }
    return $true   # .7z senza 7-Zip: lo verifichera' l'estrazione
}

function Get-File($url, $dest) {
    $leaf = Split-Path $dest -Leaf
    New-Dir (Split-Path $dest)
    if ((Test-Path $dest) -and -not $Force) {
        if (Test-Download $dest) { Say "Gia' scaricato (integro): $leaf"; return }
        # non cancello: rinomino in .bad (sovrascrive solo un .bad precedente)
        Warn "$leaf in cache e' incompleto o corrotto: lo rinomino in $leaf.bad e lo riscarico"
        Move-Item $dest "$dest.bad" -Force
    }
    $tmp = "$dest.part"
    $err = ""
    for ($try = 1; $try -le 2; $try++) {
        Say "Scarico $url (tentativo $try)"
        # curl.exe e' incluso in Windows 10/11: segue i redirect, mostra l'avanzamento
        # e si interrompe se per 30 secondi non arriva nulla (niente blocchi silenziosi).
        Remove-Item $tmp -ErrorAction SilentlyContinue
        & curl.exe -L --fail --retry 3 --retry-delay 3 --progress-bar --connect-timeout 20 --speed-time 30 --speed-limit 1000 `
            -A "Mozilla/5.0 RetroWinSetup" -o $tmp $url
        $code = $LASTEXITCODE
        if ($code -ne 0 -or -not (Test-Path $tmp) -or (Get-Item $tmp).Length -eq 0) {
            $err = "curl codice $code"
        } else {
            Move-Item $tmp $dest -Force
            if (Test-Download $dest) { return }
            $err = "file scaricato incompleto o corrotto"
            Move-Item $dest "$dest.bad" -Force
        }
        Warn "Download non riuscito ($err)"
    }
    Remove-Item $tmp -ErrorAction SilentlyContinue
    throw "Download fallito ($err) da $url . Scaricalo a mano dal browser e salvalo come: $dest  poi rilancia lo script."
}

function Expand-Any($archive, $dest) {
    New-Dir $dest
    $7z = if ($archive -match '\.zip$') { Get-7zPath } else { Find-7z }
    if ($7z) {
        & $7z x $archive "-o$dest" -y -bso0 -bsp0 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7-Zip ha fallito su $archive (codice $LASTEXITCODE)" }
    } else {
        Expand-Archive -Path $archive -DestinationPath $dest -Force
    }
}

# Copia i file di $src in $dst (anche sottocartelle). Con -OnlyNew non
# sovrascrive i file gia' presenti. Non cancella mai nulla in $dst.
function Copy-Tree($src, $dst, [switch]$OnlyNew) {
    New-Dir $dst
    $opt = @("/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
    if ($OnlyNew) { $opt += @("/XC", "/XN", "/XO") }
    & robocopy.exe $src $dst @opt | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copia da $src a $dst fallita (robocopy codice $LASTEXITCODE)" }
}

# Estrae in una cartella temporanea, trova la cartella che contiene uno dei
# file $markerNames e ne copia il contenuto in $dest (unisce/sovrascrive, non
# cancella nulla di cio' che c'e' gia' in $dest: impostazioni, salvataggi restano).
function Install-Archive($archive, $dest, [string[]]$markerNames) {
    $tmp = Join-Path $Dl (([IO.Path]::GetFileNameWithoutExtension($archive)) + "_tmp")
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Say "Estraggo $(Split-Path $archive -Leaf)"
    Expand-Any $archive $tmp
    $f = Get-ChildItem -Path $tmp -Recurse -Include $markerNames -File -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $f) { throw "Non trovo $($markerNames -join ' / ') dentro $(Split-Path $archive -Leaf)" }
    Copy-Tree $f.DirectoryName $dest
    Remove-Item $tmp -Recurse -Force
    return (Join-Path $dest $f.Name)
}

# Sposta il contenuto di $src dentro $dst senza sovrascrivere nulla.
# Restituisce $true se $src e' rimasta vuota (ed e' stata rimossa).
function Move-Content($src, $dst) {
    New-Dir $dst
    & robocopy.exe $src $dst /E /MOVE /XC /XN /XO /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Spostamento da $src a $dst fallito (robocopy codice $LASTEXITCODE)" }
    if (Test-Path $src) {
        if (Get-ChildItem $src -Recurse -File -Force -ErrorAction SilentlyContinue) { return $false }
        Remove-Item $src -Recurse -Force
    }
    return $true
}

# Equivalente di dir_prep di RetroDECK: $link diventa un collegamento (junction,
# non servono permessi di amministratore) alla cartella reale $real.
# Se $link e' una cartella normale, il suo contenuto viene spostato in $real;
# se restano file in conflitto la cartella viene rinominata in .old_<data>.
function Set-Junction($real, $link) {
    New-Dir $real
    $realFull = (Resolve-Path $real).Path.TrimEnd('\')
    $li = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($li -and ($li.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $t = @($li.Target)[0]
        if ($t -and ($t.TrimEnd('\') -eq $realFull)) { return }
        $li.Delete()   # rimuove solo il collegamento, non il contenuto
    } elseif ($li) {
        if (-not (Move-Content $link $real)) {
            $old = "$link.old_" + (Get-Date -Format "yyyyMMdd_HHmmss")
            Rename-Item $link $old
            Warn "In $link c'erano file gia' presenti in $real : lasciati in $old"
        }
    }
    New-Dir (Split-Path $link)
    New-Item -ItemType Junction -Path $link -Value $realFull | Out-Null
}

# Rinomina una cartella cambiando solo maiuscole/minuscole (es. ROMs -> roms).
function Rename-Case($parent, $name) {
    $d = Get-ChildItem $parent -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name }
    if ($d -and $d.Name -cne $name) {
        $tmp = "$name.rename_tmp"
        Rename-Item $d.FullName $tmp
        Rename-Item (Join-Path $parent $tmp) $name
        Say "Rinominata $($d.Name) in $name"
    }
}

# --- File di configurazione ---
# retroarch.cfg: righe  chiave = "valore"
function Read-Cfg($file) {
    $h = [ordered]@{}
    foreach ($l in [IO.File]::ReadAllLines($file)) {
        if ($l -match '^\s*([A-Za-z0-9_.]+)\s*=\s*"(.*)"\s*$') { $h[$matches[1]] = $matches[2] }
    }
    return $h
}
function Set-CfgValues($file, $values) {
    $list = New-Object System.Collections.Generic.List[string]
    if (Test-Path $file) { $list.AddRange([string[]][IO.File]::ReadAllLines($file)) }
    $idx = @{}
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($list[$i] -match '^\s*([A-Za-z0-9_.]+)\s*=') { $idx[$matches[1]] = $i }
    }
    foreach ($k in $values.Keys) {
        $line = "$k = `"$($values[$k])`""
        if ($idx.ContainsKey($k)) { $list[$idx[$k]] = $line } else { $list.Add($line); $idx[$k] = $list.Count - 1 }
    }
    [IO.File]::WriteAllLines($file, $list)
}

# settings.ini (DuckStation): [Sezione] + righe  Chiave = Valore
function Read-IniTriples($file) {
    $sec = ""; $out = @()
    foreach ($l in [IO.File]::ReadAllLines($file)) {
        if ($l -match '^\s*\[(.+)\]\s*$') { $sec = $matches[1]; continue }
        if ($l -match '^\s*([^=;#\[]+?)\s*=\s?(.*)$') { $out += ,@($sec, $matches[1], $matches[2]) }
    }
    return $out
}
function Set-IniValues($file, $triples) {
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path $file) { $lines.AddRange([string[]][IO.File]::ReadAllLines($file)) }
    foreach ($t in $triples) {
        $sec = $t[0]; $key = $t[1]; $new = "$($t[1]) = $($t[2])"
        $start = -1; $end = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[(.+)\]\s*$') {
                if ($start -ge 0) { $end = $i; break }
                if ($matches[1] -eq $sec) { $start = $i }
            }
        }
        if ($start -lt 0) {
            if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne "") { $lines.Add("") }
            $lines.Add("[$sec]"); $lines.Add($new); continue
        }
        $found = $false
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match '^\s*([^=;#\[]+?)\s*=' -and $matches[1] -eq $key) { $lines[$i] = $new; $found = $true; break }
        }
        if (-not $found) {
            $ins = $end
            while ($ins -gt $start + 1 -and $lines[$ins - 1].Trim() -eq "") { $ins-- }
            $lines.Insert($ins, $new)
        }
    }
    [IO.File]::WriteAllLines($file, $lines)
}

# es_settings.xml (ES-DE): righe  <tipo name="Nome" value="Valore" />
function Set-EsSetting([string]$txt, $type, $name, $value) {
    $line = "<$type name=`"$name`" value=`"$([Security.SecurityElement]::Escape($value))`" />"
    $rx = '<(bool|int|float|string) name="' + [regex]::Escape($name) + '" value="[^"]*"\s*/>'
    if ([regex]::IsMatch($txt, $rx)) { return [regex]::Replace($txt, $rx, { param($m) $line }.GetNewClosure()) }
    return $txt.TrimEnd() + "`r`n" + $line + "`r`n"
}

function Backup-File($f) {
    if (Test-Path $f) {
        $b = "$f." + (Get-Date -Format "yyyyMMdd_HHmmss") + ".bak"
        Copy-Item $f $b
        Say "Backup: $(Split-Path $b -Leaf)"
    }
}

# Le impostazioni RetroDECK si applicano una volta sola (o con -ResetConfig).
function Test-PresetNeeded($name) { return ($ResetConfig -or -not (Test-Path (Join-Path $Preset "$name.txt"))) }
function Set-PresetDone($name) {
    $script:PresetApplied = $true   # le personalizzazioni vanno riapplicate sopra
    New-Dir $Preset
    Set-Content -Path (Join-Path $Preset "$name.txt") -Encoding ASCII `
        -Value "Impostazioni RetroDECK (components $RdCommit) applicate il $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

# Impronta (SHA256) dei file di alcune cartelle: percorso relativo + contenuto.
function Get-TreeHash([string[]]$dirs) {
    $sb = New-Object Text.StringBuilder
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { continue }
        Get-ChildItem $d -Recurse -File | Sort-Object FullName | ForEach-Object {
            [void]$sb.AppendLine($_.FullName.Substring($Custom.Length) + "|" + (Get-FileHash $_.FullName -Algorithm SHA256).Hash)
        }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString()))) -replace '-', '') }
    finally { $sha.Dispose() }
}

# Crea un .ico da un'immagine, con tutte le dimensioni usate da Windows.
# Fino a 128 px formato BMP classico (letto ovunque, anche dalle vecchie API),
# 256 px in PNG. L'immagine viene centrata in un quadrato trasparente.
function New-IcoFromPng($src, $dst) {
    Add-Type -AssemblyName System.Drawing
    $img = [Drawing.Image]::FromFile($src)
    $sizes = 16, 20, 24, 32, 40, 48, 64, 96, 128, 256
    $data = @()
    try {
        foreach ($s in $sizes) {
            $bmp = New-Object Drawing.Bitmap $s, $s, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
            $g.Clear([Drawing.Color]::Transparent)
            $k = [Math]::Min($s / $img.Width, $s / $img.Height)
            $w = [int]($img.Width * $k); $h = [int]($img.Height * $k)
            $g.DrawImage($img, [int](($s - $w) / 2), [int](($s - $h) / 2), $w, $h)
            $g.Dispose()
            $ms = New-Object IO.MemoryStream
            if ($s -ge 256) { $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png) }
            else {
                # BITMAPINFOHEADER (altezza doppia: colori + maschera), righe dal basso
                $bw = New-Object IO.BinaryWriter $ms
                $bw.Write([UInt32]40); $bw.Write([Int32]$s); $bw.Write([Int32]($s * 2)); $bw.Write([UInt16]1); $bw.Write([UInt16]32)
                $bw.Write([UInt32]0); $bw.Write([UInt32]0); $bw.Write([Int32]0); $bw.Write([Int32]0); $bw.Write([UInt32]0); $bw.Write([UInt32]0)
                for ($y = $s - 1; $y -ge 0; $y--) {
                    for ($x = 0; $x -lt $s; $x++) { $c = $bmp.GetPixel($x, $y); $bw.Write([byte]$c.B); $bw.Write([byte]$c.G); $bw.Write([byte]$c.R); $bw.Write([byte]$c.A) }
                }
                $stride = [int]([Math]::Ceiling($s / 32.0) * 4)
                for ($y = $s - 1; $y -ge 0; $y--) {
                    $row = New-Object byte[] $stride
                    for ($x = 0; $x -lt $s; $x++) { if ($bmp.GetPixel($x, $y).A -eq 0) { $row[[Math]::Floor($x / 8)] = $row[[Math]::Floor($x / 8)] -bor (0x80 -shr ($x % 8)) } }
                    $bw.Write($row)
                }
                $bw.Flush()
            }
            $data += , $ms.ToArray()
            $bmp.Dispose()
        }
    } finally { $img.Dispose() }
    $out = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter $out
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
    $off = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
        $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([UInt16]1); $bw.Write([UInt16]32)
        $bw.Write([UInt32]$data[$i].Length); $bw.Write([UInt32]$off)
        $off += $data[$i].Length
    }
    foreach ($p in $data) { $bw.Write($p) }
    $bw.Flush()
    [IO.File]::WriteAllBytes($dst, $out.ToArray())
}

function Get-RdFile($name) {
    $dest = Join-Path $Dl "retrodeck\$name"
    Get-File ($RdBase + $RdFiles[$name]) $dest
    return $dest
}

function Get-GitHubAsset($repoApi, $patterns, $exclude) {
    $rel = Invoke-RestMethod -Uri $repoApi -Headers @{ "User-Agent" = "RetroWinSetup" }
    foreach ($pat in $patterns) {
        $a = $rel.assets | Where-Object { $_.name -match $pat -and (-not $exclude -or $_.name -notmatch $exclude) } | Select-Object -First 1
        if ($a) { return $a }
    }
    $names = ($rel.assets | ForEach-Object { $_.name }) -join "`n  "
    throw "Nessun asset corrispondente. Asset disponibili:`n  $names"
}

function Run-Step($name, [scriptblock]$block) {
    Write-Host ""
    Write-Host "=== $name ===" -ForegroundColor Green
    try { & $block; $script:Results[$name] = "OK" }
    catch { $script:Results[$name] = "ERRORE: $($_.Exception.Message)"; Warn $_.Exception.Message }
}

# ---------------- Controllo programmi aperti ----------------
# Spostare cartelle o modificare configurazioni con i programmi aperti non funziona.
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and $_.Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
if ($running.Count -gt 0) {
    Warn "Chiudi prima questi programmi e rilancia lo script: $(($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', ')"
    exit 1
}

New-Dir $Root
Say "Cartella di lavoro: $Root"

# ---------------- Migrazione dalla vecchia struttura ----------------
# Versioni precedenti: <Root>\ES-DE (programma), <Root>\Emulators, <Root>\_download,
# <Root>\ROMs, <Root>\BIOS. Ora i programmi stanno in <Root>\Apps.
Run-Step "Migrazione struttura" {
    New-Dir $Apps
    $oldEs = Join-Path $Root "ES-DE"
    if ((Test-Path (Join-Path $oldEs "ES-DE.exe")) -and -not (Test-Path $EsDeApp)) {
        Say "Sposto il programma ES-DE in Apps\ES-DE"
        Move-Item $oldEs $EsDeApp
    }
    foreach ($pair in @(@("Emulators", $Emu), @("_download", $Dl))) {
        $old = Join-Path $Root $pair[0]
        if (Test-Path $old) {
            if (-not (Test-Path $pair[1])) { Say "Sposto $($pair[0]) in Apps\$($pair[0])"; Move-Item $old $pair[1] }
            else { Warn "Esistono sia $old che $($pair[1]): controlla a mano" }
        }
    }
    Rename-Case $Root "roms"
    Rename-Case $Root "bios"
}
New-Dir $Dl; New-Dir $Emu

# ---------------- ES-DE ----------------
Run-Step "ES-DE" {
    if ((Test-Path (Join-Path $EsDeApp "ES-DE.exe")) -and -not $Force) { Say "ES-DE gia' presente"; return }
    $url = $EsDeFallbackUrl
    try {
        $rel = Invoke-RestMethod -Uri $EsDeReleaseApi -Headers @{ "User-Agent" = "RetroWinSetup" }
        $a = $rel.assets.links | Where-Object { $_.name -match $EsDeAssetRegex } | Select-Object -First 1
        if ($a) { $url = $a.direct_asset_url; Say "ES-DE $($rel.tag_name): $($a.name)" }
        else { Warn "Asset portable non trovato nell'ultima release, uso il link fisso" }
    } catch { Warn "API GitLab non raggiungibile ($($_.Exception.Message)), uso il link fisso" }
    $zip = Join-Path $Dl "esde.zip"
    Get-File $url $zip
    Install-Archive $zip $EsDeApp @("ES-DE.exe") | Out-Null
}

# ---------------- RetroArch ----------------
Run-Step "RetroArch" {
    $dest = Join-Path $Emu "RetroArch"
    if ((Test-Path (Join-Path $dest "retroarch.exe")) -and -not $Force) { Say "RetroArch gia' presente" }
    else {
        $idx = Invoke-WebRequest -Uri $RetroArchStableIndex -UseBasicParsing
        $vers = [regex]::Matches($idx.Content, 'href="(?:/stable/)?(\d+\.\d+\.\d+)/"') |
            ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Unique -Descending
        if (-not $vers) { throw "Non riesco a leggere le versioni stabili di RetroArch da $RetroArchStableIndex" }
        $ok = $false
        foreach ($v in $vers | Select-Object -First 3) {
            $url = "$RetroArchStableIndex$v/windows/x86_64/RetroArch.7z"
            try { Get-File $url (Join-Path $Dl "RetroArch.7z"); $ok = $true; Say "RetroArch $v"; break }
            catch { Warn "RetroArch $v non disponibile ($($_.Exception.Message)), provo la precedente" }
        }
        if (-not $ok) { throw "Download RetroArch fallito" }
        Install-Archive (Join-Path $Dl "RetroArch.7z") $dest @("retroarch.exe") | Out-Null
    }
    # retroarch.cfg accanto all'exe: su Windows RetroArch lo usa (modalita' portable)
    $cfg = Join-Path $dest "retroarch.cfg"
    if (-not (Test-Path $cfg)) { New-Item -ItemType File -Path $cfg | Out-Null }
}

# ---------------- Core libretro ----------------
Run-Step "Core libretro" {
    $ra = Join-Path $Emu "RetroArch"
    if (-not (Test-Path (Join-Path $ra "retroarch.exe"))) { throw "RetroArch non installato: core non scaricati" }
    $coresDir = Join-Path $ra "cores"
    New-Dir $coresDir
    $failed = @()
    foreach ($c in $Cores) {
        $dll = Join-Path $coresDir "${c}_libretro.dll"
        if ((Test-Path $dll) -and -not $Force) { Say "Core $c gia' presente"; continue }
        try {
            $z = Join-Path $Dl "${c}_libretro.dll.zip"
            Get-File "$CoreBase${c}_libretro.dll.zip" $z
            Expand-Any $z $coresDir
            if (-not (Test-Path $dll)) { throw "${c}_libretro.dll non presente nello zip" }
            Say "Core $c OK"
        } catch { Warn "Core $c non installato: $($_.Exception.Message)"; $failed += $c }
    }
    if ($failed) { throw "Core non installati: $($failed -join ', ')" }
}

# ---------------- DuckStation ----------------
Run-Step "DuckStation" {
    $dest = Join-Path $Emu "DuckStation"
    if ((Get-ChildItem $dest -Filter "duckstation-qt*.exe" -ErrorAction SilentlyContinue) -and -not $Force) { Say "DuckStation gia' presente" }
    else {
        $a = Get-GitHubAsset "https://api.github.com/repos/stenzek/duckstation/releases/tags/latest" @('windows-x64.*\.zip$', 'windows.*x64.*\.zip$', 'x64.*\.zip$') 'symbols|arm|debug'
        Say "Asset: $($a.name)"
        $z = Join-Path $Dl $a.name
        Get-File $a.browser_download_url $z
        Install-Archive $z $dest @("duckstation-qt*.exe") | Out-Null
    }
    # portable.txt => impostazioni accanto all'exe
    $p = Join-Path $dest "portable.txt"
    if (-not (Test-Path $p)) { New-Item -ItemType File -Path $p | Out-Null }
}

# ---------------- PCSX2 (opzionale) ----------------
if (-not $SkipPCSX2) {
    Run-Step "PCSX2" {
        $dest = Join-Path $Emu "PCSX2"
        if ((Test-Path (Join-Path $dest "pcsx2-qt.exe")) -and -not $Force) { Say "PCSX2 gia' presente" }
        else {
            $a = Get-GitHubAsset "https://api.github.com/repos/PCSX2/pcsx2/releases/latest" @('windows-x64.*Qt.*\.7z$', 'windows.*x64.*\.7z$', 'windows.*\.7z$') 'symbols|arm|avx2-qt-debug'
            Say "Asset: $($a.name)"
            $z = Join-Path $Dl $a.name
            Get-File $a.browser_download_url $z
            Install-Archive $z $dest @("pcsx2-qt.exe") | Out-Null
        }
        $p = Join-Path $dest "portable.ini"
        if (-not (Test-Path $p)) { New-Item -ItemType File -Path $p | Out-Null }
    }
} else {
    $Results["PCSX2"] = "saltato (-SkipPCSX2)"
}

# ---------------- Cartelle RetroDECK ----------------
Run-Step "Cartelle RetroDECK" {
    foreach ($d in $Paths.Values) { New-Dir $d }
    # sottocartelle create da RetroDECK (framework, retroarch, duckstation)
    foreach ($s in @(
        "bios\np2kai", "bios\dc", "bios\Mupen64plus", "bios\quasi88", "bios\fbneo\samples",
        "saves\psx\duckstation\memcards", "states\psx\duckstation",
        "screenshots\retroarch", "screenshots\Duckstation", "videos\retroarch",
        "shaders\retroarch\shaders", "shaders\retroarch\filters", "shaders\Duckstation",
        "cheats\retroarch", "borders\retroarch\overlays",
        "texture_packs\Duckstation\textures", "logs\retroarch", "logs\ES-DE")) {
        New-Dir (Join-Path $Root $s)
    }
    # collegamenti dei core (dir_prep in retroarch/component_prepare.sh)
    Set-Junction (Join-Path $Paths.texture_packs "retroarch-core\Mupen64Plus\cache")         (Join-Path $Paths.bios "Mupen64plus\cache")
    Set-Junction (Join-Path $Paths.texture_packs "retroarch-core\Mupen64Plus\hires_texture") (Join-Path $Paths.bios "Mupen64plus\hires_texture")
    Set-Junction (Join-Path $Paths.cheats  "retroarch-core\fbneo")          (Join-Path $Paths.bios "fbneo\cheats")
    Set-Junction (Join-Path $Paths.shaders "retroarch-core\fbneo\blend")    (Join-Path $Paths.bios "fbneo\blend")
    Set-Junction (Join-Path $Paths.mods    "retroarch-core\fbneo\patched")  (Join-Path $Paths.bios "fbneo\patched")
    Set-Junction (Join-Path $Paths.mods    "retroarch-core\fbneo\ips")      (Join-Path $Paths.bios "fbneo\ips")
    Set-Junction (Join-Path $Paths.mods    "retroarch-core\fbneo\romdata")  (Join-Path $Paths.bios "fbneo\romdata")
    # BIOS gia' messi nelle cartelle dei singoli emulatori: copiati in bios (originali lasciati)
    foreach ($old in @((Join-Path $Emu "DuckStation\bios"), (Join-Path $Emu "RetroArch\system"))) {
        if ((Test-Path $old) -and (Get-ChildItem $old -Recurse -File -ErrorAction SilentlyContinue)) {
            Copy-Tree $old $Paths.bios -OnlyNew
            Say "BIOS copiati da $old in $($Paths.bios)"
        }
    }
}

# ---------------- ES-DE: impostazioni RetroDECK ----------------
Run-Step "ES-DE config" {
    if (-not (Test-Path (Join-Path $EsDeApp "ES-DE.exe"))) { throw "ES-DE non installato" }
    $setDir = Join-Path $EsDeCfg "settings"
    New-Dir $setDir
    $f = Join-Path $setDir "es_settings.xml"
    if (Test-PresetNeeded "es-de") {
        $rd = Get-RdFile "es_settings.xml"
        Backup-File $f
        $txt = [IO.File]::ReadAllText($rd)
        $txt = Set-EsSetting $txt "string" "ScreensaverSlideshowImageDir" ""   # percorso Linux
        [IO.File]::WriteAllText($f, $txt)
        Set-PresetDone "es-de"
        Say "Impostazioni RetroDECK applicate a ES-DE"
    }
    # percorsi (come component_prepare.sh di RetroDECK), riallineati ad ogni esecuzione
    $txt = [IO.File]::ReadAllText($f)
    $txt = Set-EsSetting $txt "string" "ROMDirectory"       $Paths.roms
    $txt = Set-EsSetting $txt "string" "MediaDirectory"     $Paths.downloaded_media
    $txt = Set-EsSetting $txt "string" "UserThemeDirectory" $Paths.themes
    [IO.File]::WriteAllText($f, $txt)
    # cartelle di ES-DE esposte nella cartella utente
    foreach ($d in @("gamelists", "collections", "scripts", "screensavers", "custom_systems")) {
        Set-Junction (Join-Path $Root "ES-DE\$d") (Join-Path $EsDeCfg $d)
    }
    Set-Junction (Join-Path $Paths.logs "ES-DE") (Join-Path $EsDeCfg "logs")
    # tema RetroDECK
    $theme = Join-Path $Paths.themes $RdThemeName
    if ((Test-Path (Join-Path $theme "theme.xml")) -and -not $Force) { Say "Tema $RdThemeName gia' presente" }
    else {
        $z = Join-Path $Dl "RetroDECK-theme.zip"
        Get-File $RdThemeUrl $z
        Install-Archive $z $theme @("theme.xml") | Out-Null
        $script:PresetApplied = $true   # custom\files puo' sostituire file del tema: va riapplicato
        Say "Tema $RdThemeName installato"
    }
    # cartelle sistema in roms (RetroDECK: start_esde --create-system-dirs)
    $before = @(Get-ChildItem $Paths.roms -Directory).Count
    $proc = Start-Process -FilePath (Join-Path $EsDeApp "ES-DE.exe") -ArgumentList "--create-system-dirs" `
        -WorkingDirectory $EsDeApp -WindowStyle Hidden -PassThru
    if (-not $proc.WaitForExit(120000)) { $proc.Kill(); throw "ES-DE --create-system-dirs non ha terminato entro 2 minuti" }
    $after = @(Get-ChildItem $Paths.roms -Directory).Count
    if ($after -lt 100) { throw "Cartelle sistema in roms non create (trovate $after)" }
    Say "Cartelle sistema in roms: $after (prima $before)"
}

# ---------------- RetroArch: impostazioni RetroDECK ----------------
Run-Step "RetroArch config" {
    $ra  = Join-Path $Emu "RetroArch"
    $cfg = Join-Path $ra "retroarch.cfg"
    if (-not (Test-Path (Join-Path $ra "retroarch.exe"))) { throw "RetroArch non installato" }
    if (Test-PresetNeeded "retroarch") {
        $rd = Read-Cfg (Get-RdFile "retroarch.cfg")
        # esclusi: driver Linux (pulse, x, sdl2, vulkan...), percorsi Linux, URL
        # dei core Linux e valori legati all'hardware della Steam Deck o alla lingua.
        $skip = '(_driver|_directory|_dir|_path)$|^core_updater_buildbot_|^(audio_device|camera_device|microphone_device|video_refresh_rate|crt_video_refresh_rate|video_monitor_index|vulkan_gpu_index|video_max_swapchain_images|input_keyboard_layout|user_language|video_fullscreen_x|video_fullscreen_y)$'
        $vals = [ordered]@{}
        foreach ($k in $rd.Keys) { if ($k -eq "menu_driver" -or $k -notmatch $skip) { $vals[$k] = $rd[$k] } }
        Backup-File $cfg
        Set-CfgValues $cfg $vals
        $opt = Join-Path $ra "retroarch-core-options.cfg"
        $co = Read-Cfg (Get-RdFile "retroarch-core-options.cfg")
        Backup-File $opt
        Set-CfgValues $opt $co
        Set-PresetDone "retroarch"
        Say "Impostazioni RetroDECK applicate a RetroArch ($($vals.Count) voci, $($co.Count) opzioni core)"
    }
    # percorsi (come retroarch/component_prepare.sh), riallineati ad ogni esecuzione
    Set-CfgValues $cfg ([ordered]@{
        savefile_directory         = $Paths.saves
        savestate_directory        = $Paths.states
        screenshot_directory       = Join-Path $Paths.screenshots "retroarch"
        recording_output_directory = Join-Path $Paths.videos "retroarch"
        log_dir                    = $Paths.logs
        rgui_browser_directory     = $Paths.roms
        cheat_database_path        = Join-Path $Paths.cheats "retroarch"
        audio_filter_dir           = Join-Path $Paths.shaders "retroarch\filters\audio"
        video_filter_dir           = Join-Path $Paths.shaders "retroarch\filters\video"
        video_shader_dir           = Join-Path $Paths.shaders "retroarch\shaders"
        overlay_directory          = Join-Path $Paths.borders "retroarch"
        system_directory           = $Paths.bios
    })
    Set-Junction (Join-Path $Paths.logs "retroarch") (Join-Path $ra "logs")
    # shaders, filtri e bordi (retroarch_updater di RetroDECK): presi dal pacchetto RetroArch
    foreach ($pair in @(
        @("shaders",  (Join-Path $Paths.shaders "retroarch\shaders")),
        @("filters",  (Join-Path $Paths.shaders "retroarch\filters")),
        @("overlays", (Join-Path $Paths.borders "retroarch\overlays")))) {
        $src = Join-Path $ra $pair[0]
        $empty = -not (Get-ChildItem $pair[1] -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ((Test-Path $src) -and ($empty -or $ResetConfig)) { Copy-Tree $src $pair[1] -OnlyNew; Say "Copiati $($pair[0]) in $($pair[1])" }
    }
    # cheat (RetroDECK li fornisce gia' pronti): dal buildbot libretro
    $ch = Join-Path $Paths.cheats "retroarch"
    if (-not (Get-ChildItem $ch -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1) -or $ResetConfig) {
        $z = Join-Path $Dl "cheats.zip"
        Get-File $CheatsUrl $z
        Expand-Any $z $ch
        Say "Cheat installati in $ch"
    }
    # vecchi salvataggi RetroArch (prima erano ordinati per core, ora per sistema):
    # copiati in backups, da spostare a mano in saves\<sistema> / states\<sistema>
    foreach ($d in @("saves", "states")) {
        $old = Join-Path $ra $d
        if ((Test-Path $old) -and (Get-ChildItem $old -Recurse -File -ErrorAction SilentlyContinue)) {
            $bk = Join-Path $Paths.backups "retroarch-pre-retrodeck\$d"
            Copy-Tree $old $bk -OnlyNew
            Warn "Trovati vecchi $d di RetroArch: copiati in $bk (spostali in $d\<sistema>)"
        }
    }
}

# ---------------- DuckStation: impostazioni RetroDECK ----------------
Run-Step "DuckStation config" {
    $ds  = Join-Path $Emu "DuckStation"
    $ini = Join-Path $ds "settings.ini"
    if (-not (Get-ChildItem $ds -Filter "duckstation-qt*.exe" -ErrorAction SilentlyContinue)) { throw "DuckStation non installato" }
    if (Test-PresetNeeded "duckstation") {
        # RetroDECK usa DuckStation "Legacy": escluse le voci di quella versione o
        # dell'hardware Steam Deck (UI, renderer/scheda video, backend audio
        # Linux, vecchie sezioni ControllerN) e i percorsi (impostati sotto).
        $skipSec = '^(UI|Controller\d)$'
        $skipKey = '^(Main/SettingsVersion|Main/ControllerBackend|GPU/Renderer|GPU/Adapter|GPU/UseThread|GPU/ThreadedPresentation|Audio/Backend)$'
        $vals = @(Read-IniTriples (Get-RdFile "settings.ini") | Where-Object {
            $_[0] -notmatch $skipSec -and "$($_[0])/$($_[1])" -notmatch $skipKey -and $_[2] -notmatch 'RETRODECKHOMEDIR' })
        Backup-File $ini
        Set-IniValues $ini $vals
        Set-PresetDone "duckstation"
        Say "Impostazioni RetroDECK applicate a DuckStation ($($vals.Count) voci)"
    }
    $mc = Join-Path $Paths.saves "psx\duckstation\memcards"
    $folders = [ordered]@{
        SaveStates  = Join-Path $Paths.states "psx\duckstation"
        Screenshots = Join-Path $Paths.screenshots "Duckstation"
        Shaders     = Join-Path $Paths.shaders "Duckstation"
        Textures    = Join-Path $Paths.texture_packs "Duckstation\textures"
    }
    # contenuto delle vecchie cartelle interne (memcards, savestates...) spostato nelle nuove
    $moves = @(@("memcards", $mc)) + @($folders.Keys | ForEach-Object { ,@($_.ToLower(), $folders[$_]) })
    foreach ($m in $moves) {
        $old = Join-Path $ds $m[0]
        if ((Test-Path $old) -and (Get-ChildItem $old -Recurse -File -ErrorAction SilentlyContinue)) {
            if (-not (Move-Content $old $m[1])) { Warn "Alcuni file in $old esistono gia' in $($m[1]): lasciati dove sono" }
            else { Say "Spostato il contenuto di $($m[0]) in $($m[1])" }
        }
    }
    # percorsi (come duckstation/component_prepare.sh); DuckStation moderna li
    # gestisce con la sezione [Folders] invece dei collegamenti della versione Legacy
    $t = @(
        @("BIOS", "SearchDirectory", $Paths.bios),
        @("MemoryCards", "Card1Path", (Join-Path $mc "shared_card_1.mcd")),
        @("MemoryCards", "Card2Path", (Join-Path $mc "shared_card_2.mcd")),
        @("MemoryCards", "Directory", $mc),
        @("GameList", "RecursivePaths", (Join-Path $Paths.roms "psx")))
    foreach ($k in $folders.Keys) { $t += ,@("Folders", $k, $folders[$k]) }
    Set-IniValues $ini $t
}

# ---------------- Personalizzazioni RetroWin ----------------
# Le modifiche rispetto a RetroDECK stanno in custom\ accanto allo script:
#   overrides\retroarch.cfg               righe  chiave = "valore"
#   overrides\retroarch-core-options.cfg  righe  chiave = "valore"
#   overrides\core-options\<core>\<cartella roms>.opt  opzioni core per cartella
#   overrides\duckstation.ini             [Sezione] + righe  Chiave = Valore
#   overrides\es_settings.xml             righe  <tipo name="Nome" value="Valore" />
#   files\                                copiati cosi' come sono in <Root>
# Si applicano quando cambiano, quando sono appena state applicate le
# impostazioni RetroDECK o con -ResetConfig: le modifiche fatte poi dai menu
# degli emulatori restano finche' non cambi le personalizzazioni.
Run-Step "Personalizzazioni" {
    if (-not (Test-Path $Custom)) { Say "Nessuna cartella custom accanto allo script: niente da applicare"; return }
    $ov = Join-Path $Custom "overrides"
    $fs = Join-Path $Custom "files"
    $stamp = Get-TreeHash @($ov, $fs)
    $stampFile = Join-Path $Preset "custom.txt"
    $old = if (Test-Path $stampFile) { Get-Content $stampFile -TotalCount 1 } else { "" }
    if (-not ($ResetConfig -or $script:PresetApplied -or $old -ne $stamp)) { Say "Personalizzazioni gia' applicate"; return }

    $ra = Join-Path $Emu "RetroArch"
    if (Test-Path (Join-Path $ra "retroarch.exe")) {
        foreach ($n in @("retroarch.cfg", "retroarch-core-options.cfg")) {
            $src = Join-Path $ov $n
            if (-not (Test-Path $src)) { continue }
            $v = Read-Cfg $src
            if ($v.Count) { $dst = Join-Path $ra $n; Backup-File $dst; Set-CfgValues $dst $v; Say "${n}: $($v.Count) voci" }
        }
        $coDir = Join-Path $ov "core-options"
        if (Test-Path $coDir) {
            Get-ChildItem $coDir -Recurse -File -Filter "*.opt" | ForEach-Object {
                $rel = $_.FullName.Substring($coDir.Length + 1)
                $dst = Join-Path $ra "config\$rel"
                New-Dir (Split-Path $dst)
                # opzioni per cartella: partono da quelle generali del core, se esistono
                $coreOpt = Join-Path (Split-Path $dst) ((Split-Path (Split-Path $dst) -Leaf) + ".opt")
                if (-not (Test-Path $dst) -and (Test-Path $coreOpt)) { Copy-Item $coreOpt $dst }
                Set-CfgValues $dst (Read-Cfg $_.FullName)
                Say "Opzioni core: config\$rel"
            }
        }
    }
    $src = Join-Path $ov "duckstation.ini"
    $ini = Join-Path $Emu "DuckStation\settings.ini"
    if ((Test-Path $src) -and (Test-Path $ini)) {
        $v = @(Read-IniTriples $src)
        if ($v.Count) { Backup-File $ini; Set-IniValues $ini $v; Say "duckstation.ini: $($v.Count) voci" }
    }
    $src = Join-Path $ov "es_settings.xml"
    $es = Join-Path $EsDeCfg "settings\es_settings.xml"
    if ((Test-Path $src) -and (Test-Path $es)) {
        # i commenti XML possono contenere righe d'esempio: ignorati
        $o = [regex]::Replace([IO.File]::ReadAllText($src), '(?s)<!--.*?-->', '')
        $m = [regex]::Matches($o, '<(bool|int|float|string) name="([^"]+)" value="([^"]*)"\s*/>')
        if ($m.Count) {
            Backup-File $es
            $txt = [IO.File]::ReadAllText($es)
            foreach ($x in $m) { $txt = Set-EsSetting $txt $x.Groups[1].Value $x.Groups[2].Value ([Net.WebUtility]::HtmlDecode($x.Groups[3].Value)) }
            [IO.File]::WriteAllText($es, $txt)
            Say "es_settings.xml: $($m.Count) voci"
        }
    }
    if (Test-Path $fs) { Copy-Tree $fs $Root; Say "File personalizzati copiati in $Root" }
    New-Dir $Preset
    Set-Content -Path $stampFile -Value $stamp -Encoding ASCII
}

# ---------------- Splash screen ES-DE ----------------
# ES-DE cerca le proprie risorse prima in <dati ES-DE>\resources\ (override
# previsto da ES-DE, non tocca i file del programma) e accetta solo
# graphics\splash.svg. Sorgente: splash.svg, oppure splash.png / splash.jpg che
# viene incorporata (senza ricompressione) in un SVG; cercata in custom\branding
# e poi in <Root>. Senza file sorgente si usa lo splash originale di ES-DE.
Run-Step "Splash screen" {
    $dst = Join-Path $EsDeCfg "resources\graphics\splash.svg"
    $src = foreach ($dir in @($Brand, $Root)) {
        foreach ($n in @("splash.svg", "splash.png", "splash.jpg")) { Join-Path $dir $n }
    }
    $src = $src | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $src) {
        if (Test-Path $dst) { Warn "Nessuno splash.png/.svg: resta lo splash personalizzato gia' presente" }
        else { Say "Nessuno splash.png/.svg: uso lo splash originale di ES-DE" }
        return
    }
    New-Dir (Split-Path $dst)
    if ($src -match '\.svg$') { Copy-Item $src $dst -Force }
    else {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($src)
        try { $w = $img.Width; $h = $img.Height } finally { $img.Dispose() }
        $mime = if ($src -match '\.png$') { "image/png" } else { "image/jpeg" }
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($src))
        $svg = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" ' +
               "width=`"$w`" height=`"$h`" viewBox=`"0 0 $w $h`">" +
               "<image x=`"0`" y=`"0`" width=`"$w`" height=`"$h`" xlink:href=`"data:$mime;base64,$b64`"/></svg>"
        [IO.File]::WriteAllText($dst, $svg)
    }
    Say "Splash screen: $(Split-Path $src -Leaf) -> $dst"
}

# ---------------- Collegamento RetroWin ----------------
# RetroWin.lnk in <Root> e sul Desktop (salvo -NoDesktopShortcut) avvia ES-DE,
# come l'icona "RetroDECK". Icona <Root>\RetroWin.ico, presa da:
#   - custom\branding\RetroWin.ico, se esiste;
#   - altrimenti generata da custom\branding\RetroWin.png (solo se cambia);
#   - altrimenti quella gia' presente in <Root>, o quella di ES-DE.
Run-Step "Collegamento RetroWin" {
    $exe = Join-Path $EsDeApp "ES-DE.exe"
    if (-not (Test-Path $exe)) { throw "ES-DE non installato" }
    $ico = Join-Path $Root "RetroWin.ico"
    $bIco = Join-Path $Brand "RetroWin.ico"
    $bPng = Join-Path $Brand "RetroWin.png"
    $changed = $false
    if (Test-Path $bIco) {
        if (-not (Test-Path $ico) -or (Get-FileHash $bIco).Hash -ne (Get-FileHash $ico).Hash) {
            Copy-Item $bIco $ico -Force; $changed = $true; Say "Icona copiata da custom\branding"
        }
    } elseif (Test-Path $bPng) {
        $stampFile = Join-Path $Preset "icon.txt"
        $h = (Get-FileHash $bPng).Hash
        $old = if (Test-Path $stampFile) { Get-Content $stampFile -TotalCount 1 } else { "" }
        if (-not (Test-Path $ico) -or $old -ne $h) {
            if (Test-Path $ico) { Backup-File $ico }
            New-IcoFromPng $bPng $ico
            New-Dir $Preset
            Set-Content -Path $stampFile -Value $h -Encoding ASCII
            $changed = $true
            Say "Icona generata da custom\branding\RetroWin.png"
        }
    }
    $icon = if (Test-Path $ico) { "$ico,0" } else { "$exe,0" }
    $links = @(Join-Path $Root "RetroWin.lnk")
    if (-not $NoDesktopShortcut) { $links += Join-Path ([Environment]::GetFolderPath("Desktop")) "RetroWin.lnk" }
    $sh = New-Object -ComObject WScript.Shell
    foreach ($l in $links) {
        $lnk = $sh.CreateShortcut($l)
        $lnk.TargetPath       = $exe
        $lnk.WorkingDirectory = $EsDeApp
        $lnk.Description      = "RetroWin (ES-DE)"
        $lnk.IconLocation     = $icon
        $lnk.Save()
        Say "Collegamento: $l"
    }
    # Windows tiene in cache le icone per percorso del file: chiede di aggiornarle
    if ($changed) { & ie4uinit.exe -show }
}

# ---------------- Verifica ----------------
# Ogni exe nel percorso atteso e valido (header MZ), impostazioni chiave al loro posto.
$Expected = [ordered]@{
    "ES-DE"       = "Apps\ES-DE\ES-DE.exe"
    "RetroArch"   = "Apps\Emulators\RetroArch\retroarch.exe"
    "DuckStation" = "Apps\Emulators\DuckStation\duckstation-qt*.exe"
}
if (-not $SkipPCSX2) { $Expected["PCSX2"] = "Apps\Emulators\PCSX2\pcsx2-qt.exe" }
$exeLines = @()
foreach ($k in $Expected.Keys) {
    $f = Get-Item -Path (Join-Path $Root $Expected[$k]) -ErrorAction SilentlyContinue | Select-Object -First 1
    $state = "MANCANTE"
    if ($f) {
        $fs = [IO.File]::OpenRead($f.FullName)
        try { $b = New-Object byte[] 2; [void]$fs.Read($b, 0, 2) } finally { $fs.Close() }
        $state = if ($b[0] -eq 0x4D -and $b[1] -eq 0x5A) { "OK" } else { "NON VALIDO" }
        $rel = $f.FullName.Substring($Root.Length)
    } else { $rel = "\" + $Expected[$k] }
    $exeLines += ("  {0,-12} {1,-10} {2}" -f $k, $state, $rel)
    if ($state -ne "OK" -and $Results[$k] -eq "OK") { $Results[$k] = "ERRORE: eseguibile $state ($rel)" }
}

$cfgLines = @()
function Add-Check($label, $actual, $expected) {
    $ok = if ($actual -eq $expected) { "OK" } else { "DIVERSO" }
    $script:cfgLines += ("  {0,-34} {1,-8} {2}" -f $label, $ok, $actual)
}
$esF = Join-Path $EsDeCfg "settings\es_settings.xml"
if (Test-Path $esF) {
    $esT = [IO.File]::ReadAllText($esF)
    foreach ($n in @("ROMDirectory", "MediaDirectory", "UserThemeDirectory", "Theme")) {
        $m = [regex]::Match($esT, '<string name="' + $n + '" value="([^"]*)"')
        $exp = @{ ROMDirectory = $Paths.roms; MediaDirectory = $Paths.downloaded_media; UserThemeDirectory = $Paths.themes; Theme = $RdThemeName }[$n]
        Add-Check "ES-DE $n" $m.Groups[1].Value $exp
    }
}
$raF = Join-Path $Emu "RetroArch\retroarch.cfg"
if (Test-Path $raF) {
    $raC = Read-Cfg $raF
    Add-Check "RetroArch system_directory" $raC["system_directory"] $Paths.bios
    Add-Check "RetroArch savefile_directory" $raC["savefile_directory"] $Paths.saves
    Add-Check "RetroArch savestate_directory" $raC["savestate_directory"] $Paths.states
    Add-Check "RetroArch sort_savefiles_by_content" $raC["sort_savefiles_by_content_enable"] "true"
}
$dsF = Join-Path $Emu "DuckStation\settings.ini"
if (Test-Path $dsF) {
    $dsT = Read-IniTriples $dsF
    $get = { param($s, $k) ($dsT | Where-Object { $_[0] -eq $s -and $_[1] -eq $k } | Select-Object -First 1)[2] }
    Add-Check "DuckStation BIOS SearchDirectory" (& $get "BIOS" "SearchDirectory") $Paths.bios
    Add-Check "DuckStation Folders SaveStates" (& $get "Folders" "SaveStates") (Join-Path $Paths.states "psx\duckstation")
}

# ---------------- Report ----------------
$report = Join-Path $Root "report_struttura.txt"
$lines = @()
$lines += "RISULTATI"
$Results.GetEnumerator() | ForEach-Object { $lines += ("  {0,-22} {1}" -f $_.Key, $_.Value) }
$lines += ""
$lines += "VERIFICA EXE (percorsi attesi)"
$lines += $exeLines
$lines += ""
$lines += "VERIFICA IMPOSTAZIONI"
$lines += $cfgLines
$lines += ""
$lines += "STRUTTURA di $Root (roms: solo il numero di cartelle sistema)"
Get-ChildItem -Path $Root -Depth 1 -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(Apps|roms)\\' } |
    ForEach-Object {
        $tag = if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { "  -> " + @($_.Target)[0] } else { "" }
        $lines += "  " + $_.FullName.Substring($Root.Length) + $tag
    }
$lines += "  \roms\ : $(@(Get-ChildItem $Paths.roms -Directory -ErrorAction SilentlyContinue).Count) cartelle sistema"
$lines += ""
$lines += "CORE"
Get-ChildItem -Path (Join-Path $Emu "RetroArch\cores") -Filter "*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object { $lines += "  " + $_.Name }
$lines | Set-Content -Path $report -Encoding UTF8

Write-Host ""
Write-Host "================ RIEPILOGO ================" -ForegroundColor Green
$lines | Select-Object -First ($Results.Count + $exeLines.Count + $cfgLines.Count + 7) | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Report completo: $report" -ForegroundColor Green
Write-Host "Se vuoi liberare spazio puoi cancellare la cartella: $Dl"
