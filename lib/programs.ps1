# Installazione e aggiornamento dei programmi (ES-DE, RetroArch, emulatori).
# Caricato da install_retro_windows.ps1: usa le sue variabili ($Root, $Dl, $Force...).

# Valori di desired_versions.sh di un commit, cosi' come sono scritti (es. RETROARCH ->
# "1.22.2", PCSX2 -> "v2.8.2"): con o senza export, con o senza virgolette. Le righe
# commentate (#) no; se una voce compare piu' volte vale l'ultima, come in bash.
function Read-RdVersions($commit) {
    $h = @{}
    foreach ($l in [IO.File]::ReadAllLines((Get-RdFile "desired_versions.sh" $commit))) {
        if ($l -match '^\s*(?:export\s+)?([A-Z0-9_]+)_DESIRED_VERSION=(?:"([^"]*)"|''([^'']*)''|([^\s#;]*))') {
            $h[$matches[1]] = "$($matches[2])$($matches[3])$($matches[4])"
        }
    }
    return $h
}
# Valori che RetroWin sa usare: un numero di versione oppure "latest" (= l'ultima).
# Il resto (hash, variabili, "newest"...) non dice cosa scaricare.
$RdVersionRx = '^(v?\d+(\.\d+)+|latest)$'

# Versioni dei programmi indicate dal commit RetroDECK in uso, solo quelle numeriche
# (es. RETROARCH -> 1.22.2): una voce assente vuol dire "l'ultima". Errore se il file
# non si legge: chi la usa decide se restare alla versione installata.
function Get-RdVersions {
    if ($null -eq $script:RdVersions) {
        $raw = Read-RdVersions $RdCommit
        $h = @{}
        foreach ($k in $raw.Keys) { if ($raw[$k] -match '^v?\d+(\.\d+)+$') { $h[$k] = $raw[$k] } }
        $script:RdVersions = $h
    }
    return $script:RdVersions
}

# Versione che RetroDECK chiede per $key ("" = l'ultima). Se le versioni RetroDECK non si
# leggono: con il programma gia' installato errore (resta quello), altrimenti l'ultima.
function Get-RdDesired($key, $progName) {
    try { return "$((Get-RdVersions)[$key])" }
    catch {
        if (Get-ProgramExe $progName) { throw "versioni RetroDECK non lette ($($_.Exception.Message))" }
        Note "Versioni RetroDECK non lette ($($_.Exception.Message)): installo l'ultima versione di $progName"
        return ""
    }
}

# Versione installata di un programma (file retrowin_version.txt nella sua cartella).
function Get-Installed($dir) { return Get-Stamp (Join-Path $dir "retrowin_version.txt") }
function Set-Installed($dir, $v) { Set-Stamp (Join-Path $dir "retrowin_version.txt") $v }

# Installa o aggiorna un programma. $resolve restituisce @{ Version; Url; File }
# (File = nome dell'archivio in _download). Se la rete non risponde e il programma
# c'e' gia', resta la versione installata. Non scende mai a una versione piu' vecchia.
# Gli archivi delle versioni precedenti ($oldFiles) vengono tolti da _download.
# $pinKey: nome del blocco (-Pin) che lo tiene fermo alla versione installata.
function Update-Program($name, $dir, [string[]]$markers, [scriptblock]$resolve, [string[]]$oldFiles, $pinKey) {
    $present = [bool](Get-ChildItem $dir -Filter $markers[0] -ErrorAction SilentlyContinue)
    $have = if ($present) { Get-Installed $dir } else { "" }
    if ($present -and $pinKey -and (Get-Pin $pinKey)) { Say "$name $have bloccato (per sbloccarlo: -Unpin $pinKey)"; return }
    try { $r = & $resolve }
    catch {
        if (-not $present) { throw }
        Note "${name}: non riesco a controllare gli aggiornamenti ($($_.Exception.Message)), resta la $have"
        return
    }
    if ($present -and -not $Force) {
        if ($have -eq $r.Version) { Say "$name $have gia' aggiornato"; return }
        $a = $have -replace '^v', ''; $b = $r.Version -replace '^v', ''
        if (($a -as [version]) -and ($b -as [version]) -and ([version]$a -gt [version]$b)) {
            Note "$name $have piu' recente della $($r.Version) indicata: resta questa"; return
        }
    }
    if ($present) { Say "${name}: aggiorno $have -> $($r.Version)" }
    else { Say "$name $($r.Version)" }
    $z = Join-Path $Dl $r.File
    try { Get-File $r.Url $z }
    catch {
        if (-not $present) { throw }
        Note "${name}: non riesco a scaricare la $($r.Version) ($($_.Exception.Message)), resta la $have"
        return
    }
    # la versione installata diventa la "precedente" (per -Rollback): il suo archivio resta
    $prev = if ($present) { Get-ArchiveInfo $dir $oldFiles $z $have } else { $null }
    if ($prev) { Set-Stamp (Join-Path $dir "retrowin_precedente.txt") $prev }
    try { Install-Archive $z $dir $markers | Out-Null }
    catch {
        $hint = if ($prev -and $pinKey) { " Per tornare alla ${have}: -Rollback $pinKey" } else { "" }
        throw "installazione di $name $($r.Version) non riuscita ($($_.Exception.Message)).$hint"
    }
    Set-Installed $dir $r.Version
    Set-Stamp (Join-Path $dir "retrowin_archivio.txt") "$($r.Version)|$($r.Url)|$($r.File)"
    $keep = if ($prev) { ($prev -split '\|')[2] } else { "" }
    foreach ($p in $oldFiles) {
        Get-ChildItem $Dl -Filter $p -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $z -and $_.Name -ne $keep } |
            ForEach-Object { Remove-Item $_.FullName -Force; Say "Tolto da _download: $($_.Name)" }
    }
}

# "versione|indirizzo|archivio" della versione installata in $dir: da retrowin_archivio.txt
# o, per le installazioni fatte prima che esistesse, dall'archivio rimasto in _download
# (indirizzo sconosciuto: serve l'archivio). $null se non si sa.
function Get-ArchiveInfo($dir, [string[]]$oldFiles, $exclude, $have) {
    $s = Get-Stamp (Join-Path $dir "retrowin_archivio.txt")
    if ($s -and ($s -split '\|')[0] -eq $have) { return $s }
    $f = @(foreach ($p in $oldFiles) { Get-ChildItem $Dl -Filter $p -File -ErrorAction SilentlyContinue }) |
        Where-Object { $_.FullName -ne $exclude } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return "$have||$($f.Name)" }
    return $null
}

# Torna alla versione precedente di un programma (retrowin_precedente.txt) reinstallando
# il suo archivio, da _download o riscaricato. La versione lasciata diventa a sua volta
# la "precedente". Le impostazioni non si toccano: gli archivi non le contengono.
function Restore-Previous($name, $dir, [string[]]$markers) {
    $p = Get-Stamp (Join-Path $dir "retrowin_precedente.txt")
    if (-not $p) { throw "${name}: nessuna versione precedente registrata (viene registrata a ogni aggiornamento)" }
    $v, $url, $file = $p -split '\|', 3
    $z = Join-Path $Dl $file
    if (-not (Test-Path $z) -and -not $url) { throw "${name} ${v}: l'archivio $file non e' piu' in $Dl e non so da dove riscaricarlo" }
    Get-File $url $z
    $have = Get-Installed $dir
    $cur = Get-Stamp (Join-Path $dir "retrowin_archivio.txt")
    Install-Archive $z $dir $markers | Out-Null
    Set-Installed $dir $v
    Set-Stamp (Join-Path $dir "retrowin_archivio.txt") $p
    if ($cur) { Set-Stamp (Join-Path $dir "retrowin_precedente.txt") $cur }
    else { Remove-Item (Join-Path $dir "retrowin_precedente.txt") -ErrorAction SilentlyContinue }
    Say "${name}: tornato dalla $have alla $v"
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

# Ultimo commit del ramo main di un repository GitHub.
function Get-RepoHead($repo) {
    return (Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/main" -Headers @{ "User-Agent" = "RetroWinSetup" }).sha
}

# Ultima build pubblicata di RetroDECK stabile: il tag main-AAAAMMGG-HHMM piu' recente
# di RetroDECK/components. I commit di main tra un tag e l'altro sono lavori in corso.
function Get-RdLatestTag {
    $tags = Invoke-RestMethod -Uri "https://api.github.com/repos/RetroDECK/components/tags?per_page=100" -Headers @{ "User-Agent" = "RetroWinSetup" }
    $t = @($tags | Where-Object { $_.name -match '^main-\d{8}-\d{4}$' } | Sort-Object name -Descending | Select-Object -First 1)
    if (-not $t) { throw "nessun tag main-AAAAMMGG-HHMM in RetroDECK/components" }
    return @{ Name = $t[0].name; Sha = $t[0].commit.sha }
}
# Commit RetroDECK da un commit (anche abbreviato) o da un tag.
function Resolve-RdRef($ref) {
    if ($ref -match '^[0-9a-f]{40}$') { return $ref }
    return (Invoke-RestMethod -Uri "https://api.github.com/repos/RetroDECK/components/commits/$ref" -Headers @{ "User-Agent" = "RetroWinSetup" }).sha
}

# --- Blocchi (-Pin / -Unpin) ---
# Un blocco tiene fermo un componente: RetroDECK su un commit, gli altri sulla versione
# installata. File Apps\RetroWin\bloccato-<nome>.txt (prima riga: commit o versione).
$PinNames = @("RetroDECK", "Theme", "ES-DE", "RetroArch", "DuckStation", "PCSX2")
function Get-PinFile($n) { return Join-Path $Apps "RetroWin\bloccato-$($n.ToLower()).txt" }
# Commit o versione bloccati ("" = non bloccato).
function Get-Pin($n) { return "$((Get-Stamp (Get-PinFile $n)) -split ' ' | Select-Object -First 1)" }
function Resolve-PinName($s) {
    $n = $PinNames | Where-Object { $_ -eq $s.Trim() }
    if (-not $n) { throw "'$s' non si puo' bloccare (validi: $($PinNames -join ', '))" }
    return $n
}

# Eseguibile di un programma della tabella $Prog ($null se non e' installato).
function Get-ProgramExe($name) {
    $p = $Prog[$name]
    return Get-ChildItem -Path $p.Dir -Filter $p.Exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
}

# Indirizzo di un file di una versione stabile di RetroArch per Windows x64.
function Get-RetroArchUrl($v, $file) { return "$RetroArchStableIndex$v/windows/x86_64/$file" }
