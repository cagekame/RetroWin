# Funzioni comuni: messaggi, cartelle, download, archivi, copie, collegamenti, backup.
# Caricato da install_retro_windows.ps1: usa le sue variabili ($Root, $Dl, $Force...).

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

function Run-Step($name, [scriptblock]$block) {
    Write-Host ""
    Write-Host "=== $name ===" -ForegroundColor Green
    try { & $block; $script:Results[$name] = "OK" }
    catch { $script:Results[$name] = "ERRORE: $($_.Exception.Message)"; Warn $_.Exception.Message }
}
