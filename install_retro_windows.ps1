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

  Le funzioni stanno in lib\ accanto allo script (common, config, programs,
  branding); qui restano configurazione e passi dell'installazione.

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

# Programmi: cartella e nome dell'eseguibile (installazione, controlli, verifica finale).
$Prog = [ordered]@{
    "ES-DE"       = @{ Dir = $EsDeApp;                       Exe = "ES-DE.exe" }
    "RetroArch"   = @{ Dir = (Join-Path $Emu "RetroArch");   Exe = "retroarch.exe" }
    "DuckStation" = @{ Dir = (Join-Path $Emu "DuckStation"); Exe = "duckstation-qt*.exe" }
    "PCSX2"       = @{ Dir = (Join-Path $Emu "PCSX2");       Exe = "pcsx2-qt.exe" }
}
$RaDir = $Prog["RetroArch"].Dir
$DsDir = $Prog["DuckStation"].Dir
$EsSettingsFile = Join-Path $EsDeCfg "settings\es_settings.xml"
$PadScript = Join-Path $Apps "RetroWin\pad-giocatore1.ps1"   # copiato da tools\

# Percorsi scritti nelle impostazioni ad ogni esecuzione (come component_prepare.sh
# di RetroDECK) e controllati alla fine.
$EsDePaths = [ordered]@{
    ROMDirectory       = $Paths.roms
    MediaDirectory     = $Paths.downloaded_media
    UserThemeDirectory = $Paths.themes
}
$RaPaths = [ordered]@{
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
}
# DuckStation: chiavi "Sezione<tab>Chiave". DuckStation moderna gestisce le cartelle
# con la sezione [Folders] invece dei collegamenti della versione Legacy di RetroDECK.
$DsMemcards = Join-Path $Paths.saves "psx\duckstation\memcards"
$DsPaths = [ordered]@{
    "BIOS`tSearchDirectory"   = $Paths.bios
    "MemoryCards`tCard1Path"  = Join-Path $DsMemcards "shared_card_1.mcd"
    "MemoryCards`tCard2Path"  = Join-Path $DsMemcards "shared_card_2.mcd"
    "MemoryCards`tDirectory"  = $DsMemcards
    "GameList`tRecursivePaths" = Join-Path $Paths.roms "psx"
    "Folders`tSaveStates"     = Join-Path $Paths.states "psx\duckstation"
    "Folders`tScreenshots"    = Join-Path $Paths.screenshots "Duckstation"
    "Folders`tShaders"        = Join-Path $Paths.shaders "Duckstation"
    "Folders`tTextures"       = Join-Path $Paths.texture_packs "Duckstation\textures"
}

# Funzioni (cartella lib\ accanto allo script)
foreach ($n in "common", "config", "programs", "branding") {
    $lib = Join-Path $PSScriptRoot "lib\$n.ps1"
    if (-not (Test-Path $lib)) { throw "Manca $lib : scarica il progetto completo (vedi README.md) e rilancia lo script." }
    . $lib
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
New-Dir $Apps; New-Dir $Dl; New-Dir $Emu

# ---------------- ES-DE ----------------
Run-Step "ES-DE" {
    Update-Program "ES-DE" $EsDeApp @($Prog["ES-DE"].Exe) {
        try {
            $rel, $a = Get-ReleaseAsset $EsDeReleaseApi $EsDeAssetRegex "portable"
            return @{ Version = $rel.tag_name; Url = $a.direct_asset_url; File = "ES-DE-$($rel.tag_name).zip" }
        } catch {
            if (Get-ProgramExe "ES-DE") { throw }
            Warn "API GitLab non raggiungibile ($($_.Exception.Message)), uso il link fisso"
            return @{ Version = "v3.5.0"; Url = $EsDeFallbackUrl; File = "esde.zip" }
        }
    } @("ES-DE-*.zip", "esde.zip")
}

# ---------------- RetroArch ----------------
# Versione indicata da RetroDECK, altrimenti l'ultima stabile. L'archivio non
# contiene retroarch.cfg: aggiornando, le impostazioni restano.
Run-Step "RetroArch" {
    Update-Program "RetroArch" $RaDir @($Prog["RetroArch"].Exe) {
        $v = (Get-RdVersions)["RETROARCH"]
        if (-not $v) {
            $idx = Invoke-WebRequest -Uri $RetroArchStableIndex -UseBasicParsing
            $v = [regex]::Matches($idx.Content, 'href="(?:/stable/)?(\d+\.\d+\.\d+)/"') |
                ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending | Select-Object -First 1
            if (-not $v) { throw "Non riesco a leggere le versioni stabili di RetroArch da $RetroArchStableIndex" }
        }
        return @{ Version = "$v"; Url = (Get-RetroArchUrl $v "RetroArch.7z"); File = "RetroArch-$v.7z" }
    } @("RetroArch-*.7z")
    # retroarch.cfg accanto all'exe: su Windows RetroArch lo usa (modalita' portable)
    New-EmptyFile (Join-Path $RaDir "retroarch.cfg")
}

# ---------------- Core libretro ----------------
# Tutti i core del pacchetto della stessa versione di RetroArch.
Run-Step "Core libretro" {
    $v = Get-Installed $RaDir
    if (-not $v) { throw "RetroArch non installato: core non scaricati" }
    $coresDir = Join-Path $RaDir "cores"
    New-Dir $coresDir
    # un core a caso basta come "eseguibile": serve solo a sapere se ci sono gia'
    Update-Program "Core RetroArch" $coresDir @("*_libretro.dll") {
        return @{ Version = $v; Url = (Get-RetroArchUrl $v "RetroArch_cores.7z"); File = "RetroArch_cores-$v.7z" }
    } @("RetroArch_cores-*.7z")
    Say "Core installati: $(@(Get-ChildItem $coresDir -Filter '*_libretro.dll').Count)"
}

# ---------------- DuckStation ----------------
# RetroDECK usa una sua versione per Linux: qui l'ultima release ufficiale
# (rilasci continui sotto il tag "latest", riconosciuti dalla data).
Run-Step "DuckStation" {
    Update-Program "DuckStation" $DsDir @($Prog["DuckStation"].Exe) {
        $rel, $a = Get-ReleaseAsset "https://api.github.com/repos/stenzek/duckstation/releases/tags/latest" 'windows-x64-release\.zip$' "Windows x64 di DuckStation"
        $d = ([datetime]$rel.published_at).ToUniversalTime().ToString("yyyyMMdd-HHmm")
        return @{ Version = "latest-$d"; Url = $a.browser_download_url; File = "duckstation-$d.zip" }
    } @("duckstation-*.zip")
    # portable.txt => impostazioni accanto all'exe
    New-EmptyFile (Join-Path $DsDir "portable.txt")
}

# ---------------- PCSX2 (opzionale) ----------------
# Versione indicata da RetroDECK, altrimenti l'ultima release.
if (-not $SkipPCSX2) {
    Run-Step "PCSX2" {
        $dest = $Prog["PCSX2"].Dir
        Update-Program "PCSX2" $dest @($Prog["PCSX2"].Exe) {
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
}

# ---------------- ES-DE: impostazioni RetroDECK ----------------
Run-Step "ES-DE config" {
    if (-not (Get-ProgramExe "ES-DE")) { throw "ES-DE non installato" }
    $f = $EsSettingsFile
    New-Dir (Split-Path $f)
    $orig = if (Test-Path $f) { [IO.File]::ReadAllText($f) } else { "" }
    $txt = $orig
    $mode = Get-PresetMode "es-de"
    if ($mode -eq "full" -or ($mode -and -not $orig)) {
        Backup-File $f
        $txt = Get-RdEsDe $RdCommit
        Set-PresetDone "es-de" $true
        Say "Impostazioni RetroDECK applicate a ES-DE"
    } elseif ($mode -eq "merge") {
        $c = Get-RdChanges (Read-EsSettings (Get-RdEsDe (Get-PresetCommit "es-de"))) (Read-EsSettings (Get-RdEsDe $RdCommit)) (Read-EsSettings $txt)
        if ($c.Set.Count) { Backup-File $f; $txt = Set-EsSettings $txt $c.Set }
        Set-PresetDone "es-de" ($c.Set.Count -gt 0)
        Say-RdUpdate "ES-DE" $c.Set.Count $c.Kept
    }
    foreach ($k in $EsDePaths.Keys) { $txt = Set-EsSetting $txt "string" $k $EsDePaths[$k] }
    # script di evento: servono a RetroWin (pad del Giocatore 1, vedi sotto)
    $txt = Set-EsSetting $txt "bool" "CustomEventScripts" "true"
    if ($txt -cne $orig) { [IO.File]::WriteAllText($f, $txt) }
    # cartelle di ES-DE esposte nella cartella utente
    foreach ($d in @("gamelists", "collections", "scripts", "screensavers", "custom_systems")) {
        Set-Junction (Join-Path $Root "ES-DE\$d") (Join-Path $EsDeCfg $d)
    }
    Set-Junction (Join-Path $Paths.logs "ES-DE") (Join-Path $EsDeCfg "logs")
    # tema RetroDECK (versione = inizio del commit nell'indirizzo)
    $theme = Join-Path $Paths.themes $RdThemeName
    $tv = [IO.Path]::GetFileNameWithoutExtension($RdThemeUrl).Substring(0, 8)
    $had = Get-Installed $theme
    Update-Program "Tema $RdThemeName" $theme @("theme.xml") {
        return @{ Version = $tv; Url = $RdThemeUrl; File = "RetroDECK-theme-$tv.zip" }
    } @("RetroDECK-theme*.zip")
    # custom\files puo' sostituire file del tema: va riapplicato
    if ($Force -or (Get-Installed $theme) -ne $had) { $script:PresetApplied = $true }
    # cartelle sistema in roms (RetroDECK: start_esde --create-system-dirs)
    $before = @(Get-ChildItem $Paths.roms -Directory).Count
    $proc = Start-Process -FilePath (Get-ProgramExe "ES-DE").FullName -ArgumentList "--create-system-dirs" `
        -WorkingDirectory $EsDeApp -WindowStyle Hidden -PassThru
    if (-not $proc.WaitForExit(120000)) { $proc.Kill(); throw "ES-DE --create-system-dirs non ha terminato entro 2 minuti" }
    $after = @(Get-ChildItem $Paths.roms -Directory).Count
    if ($after -lt 100) { throw "Cartelle sistema in roms non create (trovate $after)" }
    Say "Cartelle sistema in roms: $after (prima $before)"
}

# ---------------- RetroArch: impostazioni RetroDECK ----------------
Run-Step "RetroArch config" {
    $ra  = $RaDir
    $cfg = Join-Path $ra "retroarch.cfg"
    if (-not (Get-ProgramExe "RetroArch")) { throw "RetroArch non installato" }
    $opt = Join-Path $ra "retroarch-core-options.cfg"
    $mode = Get-PresetMode "retroarch"
    if ($mode -eq "full") {
        $new = Get-RdRetroArch $RdCommit
        Backup-File $cfg; Set-CfgValues $cfg $new.cfg
        Backup-File $opt; Set-CfgValues $opt $new.opt
        Set-PresetDone "retroarch" $true
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
        Set-PresetDone "retroarch" ($n -gt 0)
        Say-RdUpdate "RetroArch" $n $kept
    }
    Set-CfgValues $cfg $RaPaths
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
}

# ---------------- DuckStation: impostazioni RetroDECK ----------------
Run-Step "DuckStation config" {
    $ini = Join-Path $DsDir "settings.ini"
    if (-not (Get-ProgramExe "DuckStation")) { throw "DuckStation non installato" }
    $mode = Get-PresetMode "duckstation"
    if ($mode -eq "full") {
        $vals = @(ConvertTo-Triples (Get-RdDuckStation $RdCommit))
        Backup-File $ini
        Set-IniValues $ini $vals
        Set-PresetDone "duckstation" $true
        Say "Impostazioni RetroDECK applicate a DuckStation ($($vals.Count) voci)"
    } elseif ($mode -eq "merge") {
        $cur = if (Test-Path $ini) { ConvertTo-IniDict @(Read-IniTriples $ini) } else { @{} }
        $c = Get-RdChanges (Get-RdDuckStation (Get-PresetCommit "duckstation")) (Get-RdDuckStation $RdCommit) $cur
        if ($c.Set.Count) { Backup-File $ini; Set-IniValues $ini @(ConvertTo-Triples $c.Set) }
        Set-PresetDone "duckstation" ($c.Set.Count -gt 0)
        Say-RdUpdate "DuckStation" $c.Set.Count $c.Kept
    }
    Set-IniValues $ini @(ConvertTo-Triples $DsPaths)
}

# ---------------- Pad del Giocatore 1 ----------------
# All'avvio di ES-DE (evento "startup") parte in background tools\pad-giocatore1.ps1:
# il primo pad che preme un pulsante diventa il Giocatore 1 di DuckStation.
# ES-DE su Windows esegue solo .bat e aspetta che finiscano: il .bat lancia lo
# script con "start" e termina subito.
Run-Step "Pad Giocatore 1" {
    $src = Join-Path $PSScriptRoot "tools\pad-giocatore1.ps1"
    if (-not (Test-Path $src)) { throw "Manca $src" }
    New-Dir (Split-Path $PadScript)
    Copy-Item $src $PadScript -Force
    $bat = Join-Path $EsDeCfg "scripts\startup\retrowin-pad.bat"
    New-Dir (Split-Path $bat)
    $log = Join-Path $Apps "RetroWin\pad-giocatore1.log"
    $cmd = "start `"`" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PadScript`" " +
           "-DuckStationIni `"$(Join-Path $DsDir 'settings.ini')`" -Log `"$log`""
    [IO.File]::WriteAllLines($bat, [string[]]@(
        "@echo off",
        "rem RetroWin: il primo pad che preme un pulsante diventa il Giocatore 1 (creato da install_retro_windows.ps1)",
        $cmd))
    Say "Pad Giocatore 1: $bat"
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

    $ra = $RaDir
    if (Get-ProgramExe "RetroArch") {
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
    $ini = Join-Path $DsDir "settings.ini"
    if ((Test-Path $src) -and (Test-Path $ini)) {
        $v = @(Read-IniTriples $src)
        if ($v.Count) { Backup-File $ini; Set-IniValues $ini $v; Say "duckstation.ini: $($v.Count) voci" }
    }
    $src = Join-Path $ov "es_settings.xml"
    $es = $EsSettingsFile
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
# Rigenerato solo quando cambia il file sorgente (impronta in _preset\splash.txt).
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
    $stampFile = Join-Path $Preset "splash.txt"
    $stamp = "$src|$((Get-FileHash $src).Hash)"
    if ((Test-Path $dst) -and (Get-Stamp $stampFile) -eq $stamp) { Say "Splash screen gia' aggiornato"; return }
    New-Dir (Split-Path $dst)
    if ($src -match '\.svg$') { Copy-Item $src $dst -Force }
    else { New-SvgFromImage $src $dst }
    Set-Stamp $stampFile $stamp
    Say "Splash screen: $(Split-Path $src -Leaf) -> $dst"
}

# ---------------- Collegamento RetroWin ----------------
# RetroWin.lnk in <Root> e sul Desktop (salvo -NoDesktopShortcut) avvia ES-DE,
# come l'icona "RetroDECK". Icona <Root>\RetroWin.ico, presa da:
#   - custom\branding\RetroWin.ico, se esiste;
#   - altrimenti generata da custom\branding\RetroWin.png (solo se cambia);
#   - altrimenti quella gia' presente in <Root>, o quella di ES-DE.
Run-Step "Collegamento RetroWin" {
    $exe = (Get-ProgramExe "ES-DE").FullName
    if (-not $exe) { throw "ES-DE non installato" }
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
$exeLines = @()
foreach ($k in $Prog.Keys) {
    if ($k -eq "PCSX2" -and $SkipPCSX2) { continue }
    $f = Get-ProgramExe $k
    $state = "MANCANTE"
    if ($f) {
        $fs = [IO.File]::OpenRead($f.FullName)
        try { $b = New-Object byte[] 2; [void]$fs.Read($b, 0, 2) } finally { $fs.Close() }
        $state = if ($b[0] -eq 0x4D -and $b[1] -eq 0x5A) { "OK" } else { "NON VALIDO" }
        $rel = $f.FullName.Substring($Root.Length)
    } else { $rel = (Join-Path $Prog[$k].Dir $Prog[$k].Exe).Substring($Root.Length) }
    $exeLines += ("  {0,-12} {1,-10} {2}" -f $k, $state, $rel)
    if ($state -ne "OK" -and $Results[$k] -eq "OK") { $Results[$k] = "ERRORE: eseguibile $state ($rel)" }
}

# Valori attesi ($expected) confrontati con quelli letti dal file: una riga per gruppo.
$cfgLines = @()
function Add-Check($label, $expected, $actual) {
    $bad = @($expected.Keys | Where-Object { "$($actual[$_])" -ne "$($expected[$_])" })
    $ok = if ($bad.Count) { "DIVERSO" } else { "OK" }
    $detail = if ($bad.Count) { ($bad -replace "`t", "/") -join ", " } else { "$($expected.Count) voci" }
    $script:cfgLines += ("  {0,-32} {1,-8} {2}" -f $label, $ok, $detail)
}
if (Test-Path $EsSettingsFile) {
    $es = Read-EsSettings ([IO.File]::ReadAllText($EsSettingsFile))
    $act = @{}
    foreach ($k in $es.Keys) { $act[$k] = [Net.WebUtility]::HtmlDecode(($es[$k] -split '\|', 2)[1]) }
    Add-Check "ES-DE percorsi" $EsDePaths $act
    Add-Check "ES-DE tema" @{ Theme = $RdThemeName } $act
    Add-Check "ES-DE script di evento" @{ CustomEventScripts = "true" } $act
}
$raF = Join-Path $RaDir "retroarch.cfg"
if (Test-Path $raF) {
    $act = Read-Cfg $raF
    Add-Check "RetroArch percorsi" $RaPaths $act
    Add-Check "RetroArch salvataggi per sistema" @{ sort_savefiles_by_content_enable = "true" } $act
}
$dsF = Join-Path $DsDir "settings.ini"
if (Test-Path $dsF) { Add-Check "DuckStation percorsi" $DsPaths (ConvertTo-IniDict @(Read-IniTriples $dsF)) }

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
Get-ChildItem -Path (Join-Path $RaDir "cores") -Filter "*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object { $lines += "  " + $_.Name }
$lines | Set-Content -Path $report -Encoding UTF8

Write-Host ""
Write-Host "================ RIEPILOGO ================" -ForegroundColor Green
$summary | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Report completo: $report" -ForegroundColor Green
Write-Host "Se vuoi liberare spazio puoi cancellare la cartella: $Dl"
