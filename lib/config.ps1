# File di impostazioni (retroarch.cfg, settings.ini, es_settings.xml) e impostazioni
# RetroDECK: lettura, scrittura, aggiornamento voce per voce.
# Caricato da install_retro_windows.ps1: usa le sue variabili ($Root, $Dl, $Force...).

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

# Le impostazioni RetroDECK si applicano per intero la prima volta (o con
# -ResetConfig); quando cambia $RdCommit si aggiornano solo le voci cambiate.
# Commit RetroDECK delle impostazioni gia' applicate ("" = mai applicate).
function Get-PresetCommit($name) {
    $m = [regex]::Match((Get-Stamp (Join-Path $Preset "$name.txt")), 'components ([0-9a-f]{40})')
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
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

function Get-RdFile($name, $commit = $RdCommit) {
    $dest = Join-Path $Dl "retrodeck\$($commit.Substring(0, 8))\$name"
    Get-File "https://raw.githubusercontent.com/RetroDECK/components/$commit/$($RdFiles[$name])" $dest
    return $dest
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
