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
    $sec = ""; $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in [IO.File]::ReadAllLines($file)) {
        if ($l -match '^\s*\[(.+)\]\s*$') { $sec = $matches[1]; continue }
        if ($l -match '^\s*([^=;#\[]+?)\s*=\s?(.*)$') { $out.Add(@($sec, $matches[1], $matches[2])) }
    }
    return $out.ToArray()
}
# Il file viene diviso in blocchi (righe prima della prima sezione, poi una
# sezione per blocco) con un indice delle chiavi: ogni voce si trova subito,
# senza rileggere il file. Le voci nuove vanno in fondo alla loro sezione.
function Set-IniValues($file, $triples) {
    $blocks = New-Object System.Collections.Generic.List[object]
    $cur = New-Object System.Collections.Generic.List[string]
    $blocks.Add($cur)
    $secIdx = @{}   # sezione -> blocco (la prima, se ripetuta)
    if (Test-Path $file) {
        foreach ($l in [IO.File]::ReadAllLines($file)) {
            if ($l -match '^\s*\[(.+)\]\s*$') {
                $cur = New-Object System.Collections.Generic.List[string]
                $blocks.Add($cur)
                if (-not $secIdx.ContainsKey($matches[1])) { $secIdx[$matches[1]] = $cur }
            }
            $cur.Add($l)
        }
    }
    $keyIdx = @{}   # sezione -> @{ chiave -> riga nel blocco }
    foreach ($t in $triples) {
        $sec = $t[0]; $key = $t[1]; $new = "$($t[1]) = $($t[2])"
        $b = $secIdx[$sec]
        if (-not $b) {
            $last = $blocks[$blocks.Count - 1]
            if ($last.Count -gt 0 -and $last[$last.Count - 1].Trim() -ne "") { $last.Add("") }
            $b = New-Object System.Collections.Generic.List[string]
            $b.Add("[$sec]")
            $blocks.Add($b); $secIdx[$sec] = $b
        }
        if (-not $keyIdx.ContainsKey($sec)) {
            $k = @{}
            for ($i = $b.Count - 1; $i -ge 1; $i--) { if ($b[$i] -match '^\s*([^=;#\[]+?)\s*=') { $k[$matches[1]] = $i } }
            $keyIdx[$sec] = $k
        }
        $k = $keyIdx[$sec]
        if ($k.ContainsKey($key)) { $b[$k[$key]] = $new; continue }
        # dopo le righe vuote finali ci sono solo righe vuote: gli indici gia' salvati non cambiano
        $ins = $b.Count
        while ($ins -gt 1 -and $b[$ins - 1].Trim() -eq "") { $ins-- }
        $b.Insert($ins, $new); $k[$key] = $ins
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($b in $blocks) { $lines.AddRange($b) }
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
# $changed: le impostazioni sono cambiate, quindi le personalizzazioni vanno riapplicate sopra.
function Set-PresetDone($name, [bool]$changed) {
    if ($changed) { $script:PresetApplied = $true }
    Set-Stamp (Join-Path $Preset "$name.txt") "Impostazioni RetroDECK (components $RdCommit) applicate il $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

# File RetroDECK di un commit. Restano in _preset\retrodeck (non in _download, che si
# puo' cancellare): servono come base per gli aggiornamenti anche se GitHub non li
# avesse piu'. Vengono riusati quelli gia' scaricati in _download dalle versioni precedenti.
function Get-RdFile($name, $commit = $RdCommit) {
    $c8 = $commit.Substring(0, 8)
    $dest = Join-Path $Preset "retrodeck\$c8\$name"
    $old = Join-Path $Dl "retrodeck\$c8\$name"
    if (-not (Test-Path $dest) -and (Test-Path $old)) { New-Dir (Split-Path $dest); Copy-Item $old $dest }
    Get-File "https://raw.githubusercontent.com/RetroDECK/components/$commit/$($RdFiles[$name])" $dest
    return $dest
}

# Toglie da _preset\retrodeck i commit che non servono piu': restano quelli delle
# impostazioni applicate e quello in uso.
function Remove-UnusedRdFiles {
    $dir = Join-Path $Preset "retrodeck"
    if (-not (Test-Path $dir)) { return }
    $keep = @($RdCommit) + @("es-de", "retroarch", "duckstation" | ForEach-Object { Get-PresetCommit $_ }) |
        Where-Object { $_ } | ForEach-Object { $_.Substring(0, 8) }
    Get-ChildItem $dir -Directory | Where-Object { $_.Name -notin $keep } | Remove-Item -Recurse -Force
}

# Voci delle personalizzazioni RetroWin (custom\overrides), raggruppate per il file
# RetroDECK corrispondente (stesse chiavi di Get-RdSets).
function Get-CustomKeys {
    $ov = Join-Path $Custom "overrides"
    $h = @{}
    $f = Join-Path $ov "retroarch.cfg"
    if (Test-Path $f) { $h["retroarch.cfg"] = @((Read-Cfg $f).Keys) }
    $opt = @()
    $f = Join-Path $ov "retroarch-core-options.cfg"
    if (Test-Path $f) { $opt += @((Read-Cfg $f).Keys) }
    $d = Join-Path $ov "core-options"
    if (Test-Path $d) { Get-ChildItem $d -Recurse -File -Filter "*.opt" | ForEach-Object { $opt += @((Read-Cfg $_.FullName).Keys) } }
    $h["retroarch-core-options.cfg"] = $opt
    $f = Join-Path $ov "duckstation.ini"
    if (Test-Path $f) { $h["settings.ini"] = @(Read-IniTriples $f | ForEach-Object { "$($_[0])`t$($_[1])" }) }
    $f = Join-Path $ov "es_settings.xml"
    if (Test-Path $f) { $h["es_settings.xml"] = @((Read-EsSettings ([regex]::Replace([IO.File]::ReadAllText($f), '(?s)<!--.*?-->', ''))).Keys) }
    return $h
}
# Voci delle personalizzazioni che c'erano nelle impostazioni RetroDECK $old e non ci
# sono piu' nelle $new (risultati di Get-RdSets): RetroDECK le ha tolte o rinominate,
# quindi probabilmente la personalizzazione non ha piu' effetto.
function Get-CustomKeysRemoved($old, $new) {
    $c = Get-CustomKeys
    foreach ($f in $c.Keys) {
        foreach ($k in $c[$f]) {
            if ($old[$f].Contains($k) -and -not $new[$f].Contains($k)) { "${f}: $($k -replace "`t", '/')" }
        }
    }
}

# Tutte le impostazioni RetroDECK di un commit, per file (come le legge RetroWin).
function Get-RdSets($commit) {
    $ra = Get-RdRetroArch $commit
    return [ordered]@{
        "retroarch.cfg"              = $ra.cfg
        "retroarch-core-options.cfg" = $ra.opt
        "settings.ini"               = Get-RdDuckStation $commit
        "es_settings.xml"            = Read-EsSettings (Get-RdEsDe $commit)
    }
}

# Controlla che un commit RetroDECK sia utilizzabile prima di adottarlo. Errore se:
#  - un file manca o e' vuoto;
#  - le versioni di RetroArch o PCSX2 mancano o non sono numeri di versione (o "latest");
#  - manca una voce da cui dipende RetroWin ($RdSentinels);
#  - rispetto al commit in uso ($base) sparisce piu' del $RdMaxLost % delle voci di un
#    file: quasi sempre vuol dire chiavi rinominate o formato cambiato, e l'aggiornamento
#    voce per voce farebbe danni.
# Con -Accept (opzione -AcceptRetroDECK) si saltano gli ultimi due controlli: le
# versioni dei programmi invece servono sempre, per sapere cosa scaricare.
function Test-RdCommit($commit, $base, [switch]$Accept) {
    $v = Read-RdVersions $commit
    foreach ($k in "RETROARCH", "PCSX2") {
        if (-not $v.ContainsKey($k)) { throw "desired_versions.sh senza la versione di $k" }
        if ($v[$k] -notmatch $RdVersionRx) { throw "versione di $k non riconosciuta in desired_versions.sh: '$($v[$k])'" }
    }
    $new = Get-RdSets $commit
    foreach ($f in $new.Keys) {
        if ($new[$f].Count -eq 0) { throw "$f vuoto o illeggibile" }
        if ($Accept) { continue }
        foreach ($rx in @($RdSentinels[$f])) {
            if ($rx -and -not @($new[$f].Keys | Where-Object { $_ -match $rx }).Count) {
                throw "$f senza la voce $($rx -replace '\\t', '/' -replace '[\^\$]', '')"
            }
        }
    }
    if (-not $base -or $base -eq $commit) { return }
    $old = Get-RdSets $base
    foreach ($f in $old.Keys) {
        # meno della meta' delle voci: RetroWin non sa piu' leggere il file (formato
        # cambiato), va aggiornato RetroWin. Vale anche con -Accept: adottarlo
        # rovinerebbe la base del prossimo aggiornamento.
        if ($new[$f].Count -lt $old[$f].Count / 2) {
            throw "${f}: lette solo $($new[$f].Count) voci invece di circa $($old[$f].Count). Formato cambiato? Serve una nuova versione di RetroWin"
        }
    }
    if ($Accept) { return }
    foreach ($f in $old.Keys) {
        $lost = @($old[$f].Keys | Where-Object { -not $new[$f].Contains($_) })
        if ($lost.Count -gt $old[$f].Count * $RdMaxLost / 100) {
            $ex = ($lost | Select-Object -First 3 | ForEach-Object { $_ -replace "`t", "/" }) -join ", "
            throw "${f}: spariscono $($lost.Count) voci su $($old[$f].Count) (es. $ex). Chiavi rinominate o formato cambiato?"
        }
    }
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
