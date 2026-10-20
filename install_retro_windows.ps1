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
    -Force        riscarica e reinstalla i programmi anche se aggiornati
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

  Lo script e' idempotente e fa anche da aggiornamento: installa o aggiorna i
  programmi alle versioni di RetroDECK (o alle ultime), applica le impostazioni
  RetroDECK per intero solo la prima volta e, quando cambia $RdCommit, aggiorna
  solo le voci che l'utente non ha modificato; ad ogni esecuzione riallinea i
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
$CheatsUrl = "https://buildbot.libretro.com/assets/frontend/cheats.zip"

# Impostazioni ufficiali RetroDECK (repo RetroDECK/components), fissate a un
# commit preciso perche' il risultato sia riproducibile (commit del 2026-10-03).
# Dallo stesso commit si leggono le versioni dei programmi (desired_versions.sh).
# Per aggiornare RetroWin a una RetroDECK piu' recente basta cambiare questo
# commit: chi rilancia lo script riceve programmi e impostazioni nuove, senza
# perdere le impostazioni che ha modificato.
$RdCommit  = "fcd0d72995d7aa2e741e2753ac6914025b2ff1ac"
$RdFiles   = [ordered]@{
    "es_settings.xml" = "es-de/rd_assets/rd_config/es_settings.xml"
    "retroarch.cfg"   = "retroarch/rd_assets/rd_config/retroarch.cfg"
    "settings.ini"    = "duckstation/rd_assets/rd_config/settings.ini"
    "retroarch-core-options.cfg" = "retroarch/rd_assets/rd_config/retroarch-core-options.cfg"
    "desired_versions.sh" = "automation-tools/alchemist/desired_versions.sh"
}
# Tema ES-DE ufficiale RetroDECK (repo RetroDECK/RetroDECK-theme, 2026-10-03).
$RdThemeUrl  = "https://github.com/RetroDECK/RetroDECK-theme/archive/c50205283cbb4a1bb2b05c11e897cf129f23f076.zip"
$RdThemeName = "RetroDECK-theme-main"   # nome usato da RetroDECK in es_settings.xml

# Backup .bak tenuti per ogni file di impostazioni (i piu' vecchi vengono tolti).
$KeepBackups = 3
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
function New-EmptyFile($p) { if (-not (Test-Path $p)) { New-Item -ItemType File -Path $p | Out-Null } }

# $true se nella cartella (o nelle sottocartelle) c'e' almeno un file, anche nascosto.
function Test-HasFiles($dir) {
    return [bool](Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

# Piccoli file di testo con un solo valore (versione installata, impronta...): "" se mancano.
function Get-Stamp($file) {
    if (Test-Path $file) { return "$(Get-Content $file -TotalCount 1)".Trim() }
    return ""
}
function Set-Stamp($file, $value) {
    New-Dir (Split-Path $file)
    Set-Content -Path $file -Value $value -Encoding ASCII
}

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

# Porta il contenuto di $src in $dst. Se $dst non c'e' o e' vuota basta rinominare
# la cartella (istantaneo, nessuna copia dei dati); altrimenti i file vengono uniti
# con robocopy (sovrascrive, non cancella nulla in $dst, regge i percorsi lunghi).
function Move-Tree($src, $dst) {
    $di = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    if ($di) {
        if (($di.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Get-ChildItem -LiteralPath $dst -Force | Select-Object -First 1)) { Copy-Tree $src $dst; return }
        Remove-Item -LiteralPath $dst -Force
    }
    New-Dir (Split-Path $dst)
    try { [IO.Directory]::Move($src, $dst) }
    catch { Copy-Tree $src $dst }   # dischi diversi: si copia
}

# Cancella una cartella temporanea anche con percorsi oltre 260 caratteri (dove
# Remove-Item fallisce): robocopy la svuota specchiando una cartella vuota.
function Remove-Tree($dir) {
    if (-not (Test-Path $dir)) { return }
    $empty = Join-Path $Dl "_empty"
    New-Dir $empty
    & robocopy.exe $empty $dir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    Remove-Item $dir -Recurse -Force
    Remove-Item $empty -Force
}

# Estrae in una cartella temporanea, trova la cartella che contiene uno dei
# file $markerNames e ne sposta il contenuto in $dest (unisce/sovrascrive, non
# cancella nulla di cio' che c'e' gia' in $dest: impostazioni, salvataggi restano).
function Install-Archive($archive, $dest, [string[]]$markerNames) {
    $tmp = Join-Path $Dl (([IO.Path]::GetFileNameWithoutExtension($archive)) + "_tmp")
    Remove-Tree $tmp
    Say "Estraggo $(Split-Path $archive -Leaf)"
    Expand-Any $archive $tmp
    $f = Get-ChildItem -Path $tmp -Recurse -Include $markerNames -File -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $f) { throw "Non trovo $($markerNames -join ' / ') dentro $(Split-Path $archive -Leaf)" }
    Move-Tree $f.DirectoryName $dest
    Remove-Tree $tmp   # gia' assente se e' stata spostata tutta
    return (Join-Path $dest $f.Name)
}

# Sposta il contenuto di $src dentro $dst senza sovrascrivere nulla.
# Restituisce $true se $src e' rimasta vuota (ed e' stata rimossa).
function Move-Content($src, $dst) {
    New-Dir $dst
    & robocopy.exe $src $dst /E /MOVE /XC /XN /XO /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Spostamento da $src a $dst fallito (robocopy codice $LASTEXITCODE)" }
    if (Test-Path $src) {
        if (Test-HasFiles $src) { return $false }
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
$EsLineRx = '<(bool|int|float|string) name="([^"]+)" value="([^"]*)"\s*/>'
function Set-EsSetting([string]$txt, $type, $name, $value) {
    $line = "<$type name=`"$name`" value=`"$([Security.SecurityElement]::Escape($value))`" />"
    $rx = '<(bool|int|float|string) name="' + [regex]::Escape($name) + '" value="[^"]*"\s*/>'
    if ([regex]::IsMatch($txt, $rx)) { return [regex]::Replace($txt, $rx, { param($m) $line }.GetNewClosure()) }
    return $txt.TrimEnd() + "`r`n" + $line + "`r`n"
}
# Nome -> "tipo|valore" (valore come scritto nel file)
function Read-EsSettings([string]$txt) {
    $d = [ordered]@{}
    foreach ($m in [regex]::Matches($txt, $EsLineRx)) {
        $d[$m.Groups[2].Value] = $m.Groups[1].Value + "|" + $m.Groups[3].Value
    }
    return $d
}
# Applica a $txt le voci lette con Read-EsSettings.
function Set-EsSettings([string]$txt, $values) {
    foreach ($k in $values.Keys) {
        $tv = $values[$k] -split '\|', 2
        $txt = Set-EsSetting $txt $tv[0] $k ([Net.WebUtility]::HtmlDecode($tv[1]))
    }
    return $txt
}

# Copia $f in <file>.<data>.bak e tiene solo gli ultimi $KeepBackups backup.
function Backup-File($f) {
    if (-not (Test-Path $f)) { return }
    $leaf = Split-Path $f -Leaf
    $b = "$f." + (Get-Date -Format "yyyyMMdd_HHmmss") + ".bak"
    Copy-Item $f $b
    Say "Backup: $(Split-Path $b -Leaf)"
    $rx = '^' + [regex]::Escape($leaf) + '\.\d{8}_\d{6}\.bak$'
    Get-ChildItem -LiteralPath (Split-Path $f) -Filter "$leaf.*.bak" -File |
        Where-Object { $_.Name -match $rx } | Sort-Object Name -Descending |
        Select-Object -Skip $KeepBackups | Remove-Item -Force
}

# Le impostazioni RetroDECK si applicano per intero la prima volta (o con
# -ResetConfig); quando cambia $RdCommit si aggiornano solo le voci cambiate.
# Commit RetroDECK delle impostazioni gia' applicate ("" = mai applicate).
function Get-PresetCommit($name) {
    $f = Join-Path $Preset "$name.txt"
    if (-not (Test-Path $f)) { return "" }
    $m = [regex]::Match((Get-Content $f -Raw), 'components ([0-9a-f]{40})')
    if ($m.Success) { return $m.Groups[1].Value }
    return $RdCommit   # formato sconosciuto: considerate gia' attuali
}
# "full" = applica tutto, "merge" = aggiorna dal commit precedente, "" = niente da fare
function Get-PresetMode($name) {
    if ($ResetConfig) { return "full" }
    $c = Get-PresetCommit $name
    if (-not $c) { return "full" }
    if ($c -ne $RdCommit) { return "merge" }
    return ""
}
# Voci da scrivere per passare dalle impostazioni RetroDECK $old alle $new:
# una voce cambiata da RetroDECK prende il nuovo valore solo se l'utente non
# l'ha modificata (valore attuale uguale al vecchio, o assente); le voci nuove
# si aggiungono sempre. Kept = voci lasciate come le ha modificate l'utente.
function Get-RdChanges($old, $new, $cur) {
    $set = [ordered]@{}; $kept = 0
    foreach ($k in $new.Keys) {
        if ($old.Contains($k) -and $old[$k] -ceq $new[$k]) { continue }
        if (-not $old.Contains($k) -or -not $cur.Contains($k) -or $cur[$k] -ceq $old[$k]) { $set[$k] = $new[$k] }
        else { $kept++ }
    }
    return @{ Set = $set; Kept = $kept }
}
function Say-RdUpdate($what, $n, $kept) {
    $m = "Impostazioni RetroDECK di $what aggiornate: $n voci cambiate"
    if ($kept) { $m += ", $kept lasciate come le avevi modificate" }
    Say $m
}
function Set-PresetDone($name) {
    $script:PresetApplied = $true   # le personalizzazioni vanno riapplicate sopra
    Set-Stamp (Join-Path $Preset "$name.txt") "Impostazioni RetroDECK (components $RdCommit) applicate il $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
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

function Get-RdFile($name, $commit = $RdCommit) {
    $dest = Join-Path $Dl "retrodeck\$($commit.Substring(0, 8))\$name"
    Get-File "https://raw.githubusercontent.com/RetroDECK/components/$commit/$($RdFiles[$name])" $dest
    return $dest
}

# Versioni dei programmi usate da RetroDECK (es. RETROARCH -> 1.22.2).
# Valori come "latest" o con variabili non sono versioni: ignorati.
function Get-RdVersions {
    if ($null -ne $script:RdVersions) { return $script:RdVersions }
    $h = @{}
    try {
        foreach ($l in [IO.File]::ReadAllLines((Get-RdFile "desired_versions.sh"))) {
            if ($l -match '^\s*export\s+([A-Z0-9_]+)_DESIRED_VERSION="([^"$]+)"' -and $matches[2] -notmatch '^(latest|preview)$') {
                $h[$matches[1]] = $matches[2]
            }
        }
    } catch { Warn "Versioni dei programmi RetroDECK non lette ($($_.Exception.Message)): uso le ultime" }
    $script:RdVersions = $h
    return $h
}

# Impostazioni RetroDECK di un commit, gia' filtrate per Windows.
function Get-RdRetroArch($commit) {
    $rd = Read-Cfg (Get-RdFile "retroarch.cfg" $commit)
    # esclusi: driver Linux (pulse, x, sdl2, vulkan...), percorsi Linux, URL
    # dei core Linux e valori legati all'hardware della Steam Deck o alla lingua.
    # input_joypad_driver (sdl2) si tiene: i tasti di RetroDECK sono numerati per SDL
    # e con xinput finirebbero su altri pulsanti (croce direzionale, assi invertiti).
    $skip = '(_driver|_directory|_dir|_path)$|^core_updater_buildbot_|^(audio_device|camera_device|microphone_device|video_refresh_rate|crt_video_refresh_rate|video_monitor_index|vulkan_gpu_index|video_max_swapchain_images|input_keyboard_layout|user_language|video_fullscreen_x|video_fullscreen_y)$'
    $vals = [ordered]@{}
    foreach ($k in $rd.Keys) { if ($k -in "menu_driver", "input_joypad_driver" -or $k -notmatch $skip) { $vals[$k] = $rd[$k] } }
    return @{ cfg = $vals; opt = (Read-Cfg (Get-RdFile "retroarch-core-options.cfg" $commit)) }
}
# DuckStation: chiavi "Sezione<tab>Chiave"
function ConvertTo-IniDict($triples) {
    $d = [ordered]@{}
    foreach ($t in $triples) { $d["$($t[0])`t$($t[1])"] = $t[2] }
    return $d
}
function ConvertTo-Triples($d) {
    foreach ($k in $d.Keys) { $p = $k -split "`t", 2; , @($p[0], $p[1], $d[$k]) }
}
function Get-RdDuckStation($commit) {
    # RetroDECK usa DuckStation "Legacy": escluse le voci di quella versione o
    # dell'hardware Steam Deck (UI, renderer/scheda video, backend audio
    # Linux, vecchie sezioni ControllerN) e i percorsi (impostati a parte).
    $skipSec = '^(UI|Controller\d)$'
    $skipKey = '^(Main/SettingsVersion|Main/ControllerBackend|GPU/Renderer|GPU/Adapter|GPU/UseThread|GPU/ThreadedPresentation|Audio/Backend)$'
    return ConvertTo-IniDict @(Read-IniTriples (Get-RdFile "settings.ini" $commit) | Where-Object {
        $_[0] -notmatch $skipSec -and "$($_[0])/$($_[1])" -notmatch $skipKey -and $_[2] -notmatch 'RETRODECKHOMEDIR' })
}
function Get-RdEsDe($commit) {
    $txt = [IO.File]::ReadAllText((Get-RdFile "es_settings.xml" $commit))
    return (Set-EsSetting $txt "string" "ScreensaverSlideshowImageDir" "")   # percorso Linux
}

# Versione installata di un programma (file retrowin_version.txt nella sua cartella).
function Get-Installed($dir) { return Get-Stamp (Join-Path $dir "retrowin_version.txt") }
function Set-Installed($dir, $v) { Set-Stamp (Join-Path $dir "retrowin_version.txt") $v }

# Installa o aggiorna un programma. $resolve restituisce @{ Version; Url; File }
# (File = nome dell'archivio in _download). Se la rete non risponde e il programma
# c'e' gia', resta la versione installata. Non scende mai a una versione piu' vecchia.
# Gli archivi delle versioni precedenti ($oldFiles) vengono tolti da _download.
function Update-Program($name, $dir, [string[]]$markers, [scriptblock]$resolve, [string[]]$oldFiles) {
    $present = [bool](Get-ChildItem $dir -Filter $markers[0] -ErrorAction SilentlyContinue)
    $have = if ($present) { Get-Installed $dir } else { "" }
    try { $r = & $resolve }
    catch {
        if (-not $present) { throw }
        Warn "${name}: non riesco a controllare gli aggiornamenti ($($_.Exception.Message)), resta la versione installata"
        return
    }
    if ($present -and -not $Force) {
        if ($have -eq $r.Version) { Say "$name $have gia' aggiornato"; return }
        $a = $have -replace '^v', ''; $b = $r.Version -replace '^v', ''
        if (($a -as [version]) -and ($b -as [version]) -and ([version]$a -gt [version]$b)) {
            Say "$name $have piu' recente di $($r.Version): resta questa"; return
        }
    }
    if ($present) { Say "${name}: aggiorno $(if ($have) { $have } else { 'versione precedente' }) -> $($r.Version)" }
    else { Say "$name $($r.Version)" }
    $z = Join-Path $Dl $r.File
    Get-File $r.Url $z
    Install-Archive $z $dir $markers | Out-Null
    Set-Installed $dir $r.Version
    foreach ($p in $oldFiles) {
        Get-ChildItem $Dl -Filter $p -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $z } |
            ForEach-Object { Remove-Item $_.FullName -Force; Say "Tolto da _download: $($_.Name)" }
    }
}

# Release letta da un'API GitHub o GitLab (GitLab elenca gli asset in assets.links)
# e il suo primo asset il cui nome corrisponde a $rx. Uso: $rel, $a = Get-ReleaseAsset ...
function Get-ReleaseAsset($api, $rx, $what) {
    $rel = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "RetroWinSetup" }
    $list = if ($rel.assets.PSObject.Properties["links"]) { $rel.assets.links } else { $rel.assets }
    $a = $list | Where-Object { $_.name -match $rx } | Select-Object -First 1
    if (-not $a) { throw "Asset $what non trovato nella release $($rel.tag_name)" }
    return $rel, $a
}

# Indirizzo di un file di una versione stabile di RetroArch per Windows x64.
function Get-RetroArchUrl($v, $file) { return "$RetroArchStableIndex$v/windows/x86_64/$file" }

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
    Update-Program "ES-DE" $EsDeApp @("ES-DE.exe") {
        try {
            $rel, $a = Get-ReleaseAsset $EsDeReleaseApi $EsDeAssetRegex "portable"
            return @{ Version = $rel.tag_name; Url = $a.direct_asset_url; File = "ES-DE-$($rel.tag_name).zip" }
        } catch {
            if (Test-Path (Join-Path $EsDeApp "ES-DE.exe")) { throw }
            Warn "API GitLab non raggiungibile ($($_.Exception.Message)), uso il link fisso"
            return @{ Version = "v3.5.0"; Url = $EsDeFallbackUrl; File = "esde.zip" }
        }
    } @("ES-DE-*.zip", "esde.zip")
}

# ---------------- RetroArch ----------------
# Versione indicata da RetroDECK, altrimenti l'ultima stabile. L'archivio non
# contiene retroarch.cfg: aggiornando, le impostazioni restano.
Run-Step "RetroArch" {
    $dest = Join-Path $Emu "RetroArch"
    Update-Program "RetroArch" $dest @("retroarch.exe") {
        $v = (Get-RdVersions)["RETROARCH"]
        if (-not $v) {
            $idx = Invoke-WebRequest -Uri $RetroArchStableIndex -UseBasicParsing
            $v = [regex]::Matches($idx.Content, 'href="(?:/stable/)?(\d+\.\d+\.\d+)/"') |
                ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending | Select-Object -First 1
            if (-not $v) { throw "Non riesco a leggere le versioni stabili di RetroArch da $RetroArchStableIndex" }
        }
        return @{ Version = "$v"; Url = (Get-RetroArchUrl $v "RetroArch.7z"); File = "RetroArch-$v.7z" }
    } @("RetroArch-*.7z", "RetroArch.7z")
    # retroarch.cfg accanto all'exe: su Windows RetroArch lo usa (modalita' portable)
    New-EmptyFile (Join-Path $dest "retroarch.cfg")
}

# ---------------- Core libretro ----------------
# Tutti i core del pacchetto della stessa versione di RetroArch.
Run-Step "Core libretro" {
    $ra = Join-Path $Emu "RetroArch"
    $v = Get-Installed $ra
    if (-not $v) { throw "RetroArch non installato: core non scaricati" }
    $coresDir = Join-Path $ra "cores"
    New-Dir $coresDir
    # un core a caso basta come "eseguibile": serve solo a sapere se ci sono gia'
    Update-Program "Core RetroArch" $coresDir @("*_libretro.dll") {
        return @{ Version = $v; Url = (Get-RetroArchUrl $v "RetroArch_cores.7z"); File = "RetroArch_cores-$v.7z" }
    } @("RetroArch_cores-*.7z", "*_libretro.dll.zip")
    Say "Core installati: $(@(Get-ChildItem $coresDir -Filter '*_libretro.dll').Count)"
}

# ---------------- DuckStation ----------------
# RetroDECK usa una sua versione per Linux: qui l'ultima release ufficiale
# (rilasci continui sotto il tag "latest", riconosciuti dalla data).
Run-Step "DuckStation" {
    $dest = Join-Path $Emu "DuckStation"
    Update-Program "DuckStation" $dest @("duckstation-qt*.exe") {
        $rel, $a = Get-ReleaseAsset "https://api.github.com/repos/stenzek/duckstation/releases/tags/latest" 'windows-x64-release\.zip$' "Windows x64 di DuckStation"
        $d = ([datetime]$rel.published_at).ToUniversalTime().ToString("yyyyMMdd-HHmm")
        return @{ Version = "latest-$d"; Url = $a.browser_download_url; File = "duckstation-$d.zip" }
    } @("duckstation-*.zip")
    # portable.txt => impostazioni accanto all'exe
    New-EmptyFile (Join-Path $dest "portable.txt")
}

# ---------------- PCSX2 (opzionale) ----------------
# Versione indicata da RetroDECK, altrimenti l'ultima release.
if (-not $SkipPCSX2) {
    Run-Step "PCSX2" {
        $dest = Join-Path $Emu "PCSX2"
        Update-Program "PCSX2" $dest @("pcsx2-qt.exe") {
            $v = (Get-RdVersions)["PCSX2"]
            $api = if ($v) { "https://api.github.com/repos/PCSX2/pcsx2/releases/tags/$v" } else { "https://api.github.com/repos/PCSX2/pcsx2/releases/latest" }
            $rel, $a = Get-ReleaseAsset $api 'windows-x64-Qt\.7z$' "Windows x64 di PCSX2"
            return @{ Version = $rel.tag_name; Url = $a.browser_download_url; File = $a.name }
        } @("pcsx2-*.7z")
        New-EmptyFile (Join-Path $dest "portable.ini")
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
        if (Test-HasFiles $old) {
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
    $mode = Get-PresetMode "es-de"
    if ($mode -eq "full" -or ($mode -and -not (Test-Path $f))) {
        Backup-File $f
        [IO.File]::WriteAllText($f, (Get-RdEsDe $RdCommit))
        Set-PresetDone "es-de"
        Say "Impostazioni RetroDECK applicate a ES-DE"
    } elseif ($mode -eq "merge") {
        $txt = [IO.File]::ReadAllText($f)
        $c = Get-RdChanges (Read-EsSettings (Get-RdEsDe (Get-PresetCommit "es-de"))) (Read-EsSettings (Get-RdEsDe $RdCommit)) (Read-EsSettings $txt)
        if ($c.Set.Count) { Backup-File $f; [IO.File]::WriteAllText($f, (Set-EsSettings $txt $c.Set)) }
        Set-PresetDone "es-de"
        Say-RdUpdate "ES-DE" $c.Set.Count $c.Kept
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
    $tv = [IO.Path]::GetFileNameWithoutExtension($RdThemeUrl).Substring(0, 8)   # commit del tema
    if ((Test-Path (Join-Path $theme "theme.xml")) -and ((Get-Installed $theme) -in @($tv, "")) -and -not $Force) {
        if (-not (Get-Installed $theme)) { Set-Installed $theme $tv }
        Say "Tema $RdThemeName gia' presente"
    } else {
        $z = Join-Path $Dl "RetroDECK-theme-$tv.zip"
        Get-File $RdThemeUrl $z
        Install-Archive $z $theme @("theme.xml") | Out-Null
        Set-Installed $theme $tv
        Get-ChildItem $Dl -Filter "RetroDECK-theme*.zip" -File | Where-Object { $_.FullName -ne $z } | Remove-Item -Force
        $script:PresetApplied = $true   # custom\files puo' sostituire file del tema: va riapplicato
        Say "Tema $RdThemeName installato ($tv)"
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
    $opt = Join-Path $ra "retroarch-core-options.cfg"
    $mode = Get-PresetMode "retroarch"
    if ($mode -eq "full") {
        $new = Get-RdRetroArch $RdCommit
        Backup-File $cfg; Set-CfgValues $cfg $new.cfg
        Backup-File $opt; Set-CfgValues $opt $new.opt
        Set-PresetDone "retroarch"
        Say "Impostazioni RetroDECK applicate a RetroArch ($($new.cfg.Count) voci, $($new.opt.Count) opzioni core)"
    } elseif ($mode -eq "merge") {
        $old = Get-RdRetroArch (Get-PresetCommit "retroarch")
        $new = Get-RdRetroArch $RdCommit
        $n = 0; $kept = 0
        foreach ($p in @(@($cfg, "cfg"), @($opt, "opt"))) {
            $cur = if (Test-Path $p[0]) { Read-Cfg $p[0] } else { @{} }
            $c = Get-RdChanges $old[$p[1]] $new[$p[1]] $cur
            if ($c.Set.Count) { Backup-File $p[0]; Set-CfgValues $p[0] $c.Set }
            $n += $c.Set.Count; $kept += $c.Kept
        }
        Set-PresetDone "retroarch"
        Say-RdUpdate "RetroArch" $n $kept
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
        if ((Test-Path $src) -and ($ResetConfig -or -not (Test-HasFiles $pair[1]))) { Copy-Tree $src $pair[1] -OnlyNew; Say "Copiati $($pair[0]) in $($pair[1])" }
    }
    # cheat (RetroDECK li fornisce gia' pronti): dal buildbot libretro
    $ch = Join-Path $Paths.cheats "retroarch"
    if ($ResetConfig -or -not (Test-HasFiles $ch)) {
        $z = Join-Path $Dl "cheats.zip"
        Get-File $CheatsUrl $z
        Expand-Any $z $ch
        Say "Cheat installati in $ch"
    }
    # vecchi salvataggi RetroArch (prima erano ordinati per core, ora per sistema):
    # copiati in backups, da spostare a mano in saves\<sistema> / states\<sistema>
    foreach ($d in @("saves", "states")) {
        $old = Join-Path $ra $d
        if (Test-HasFiles $old) {
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
    $mode = Get-PresetMode "duckstation"
    if ($mode -eq "full") {
        $vals = @(ConvertTo-Triples (Get-RdDuckStation $RdCommit))
        Backup-File $ini
        Set-IniValues $ini $vals
        Set-PresetDone "duckstation"
        Say "Impostazioni RetroDECK applicate a DuckStation ($($vals.Count) voci)"
    } elseif ($mode -eq "merge") {
        $cur = if (Test-Path $ini) { ConvertTo-IniDict @(Read-IniTriples $ini) } else { @{} }
        $c = Get-RdChanges (Get-RdDuckStation (Get-PresetCommit "duckstation")) (Get-RdDuckStation $RdCommit) $cur
        if ($c.Set.Count) { Backup-File $ini; Set-IniValues $ini @(ConvertTo-Triples $c.Set) }
        Set-PresetDone "duckstation"
        Say-RdUpdate "DuckStation" $c.Set.Count $c.Kept
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
        if (Test-HasFiles $old) {
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
    if (-not ($ResetConfig -or $script:PresetApplied -or (Get-Stamp $stampFile) -ne $stamp)) { Say "Personalizzazioni gia' applicate"; return }

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
        $v = Read-EsSettings ([regex]::Replace([IO.File]::ReadAllText($src), '(?s)<!--.*?-->', ''))
        if ($v.Count) {
            Backup-File $es
            [IO.File]::WriteAllText($es, (Set-EsSettings ([IO.File]::ReadAllText($es)) $v))
            Say "es_settings.xml: $($v.Count) voci"
        }
    }
    if (Test-Path $fs) { Copy-Tree $fs $Root; Say "File personalizzati copiati in $Root" }
    Set-Stamp $stampFile $stamp
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
        if (-not (Test-Path $ico) -or (Get-Stamp $stampFile) -ne $h) {
            Backup-File $ico
            New-IcoFromPng $bPng $ico
            Set-Stamp $stampFile $h
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
# riepilogo: mostrato a schermo e all'inizio del report
$summary = @("RISULTATI")
$Results.GetEnumerator() | ForEach-Object { $summary += ("  {0,-22} {1}" -f $_.Key, $_.Value) }
$summary += ""
$summary += "VERIFICA EXE (percorsi attesi)"
$summary += $exeLines
$summary += ""
$summary += "VERIFICA IMPOSTAZIONI"
$summary += $cfgLines
$lines = $summary
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
$summary | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Report completo: $report" -ForegroundColor Green
Write-Host "Se vuoi liberare spazio puoi cancellare la cartella: $Dl"
