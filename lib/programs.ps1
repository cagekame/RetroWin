# Installazione e aggiornamento dei programmi (ES-DE, RetroArch, emulatori).
# Caricato da install_retro_windows.ps1: usa le sue variabili ($Root, $Dl, $Force...).

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
