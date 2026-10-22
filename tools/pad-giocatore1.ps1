<#
  pad-giocatore1.ps1 (RetroWin)
  Lanciato in background da ES-DE all'avvio (scripts\startup\retrowin-pad.bat):
  aspetta il primo pulsante premuto su un pad XInput e assegna quel pad al
  Giocatore 1 di tutti gli emulatori, l'altro pad al Giocatore 2. Poi si
  chiude; si chiude anche se ES-DE viene chiuso prima che si prema un pulsante.

  - DuckStation e PCSX2 chiamano i pad SDL-0..3 nello stesso ordine dei posti
    XInput di Windows (0..3): basta riscrivere SDL-<n> nelle sezioni [Pad1] e
    [Pad2].
  - RetroArch vede i pad in un altro ordine e senza il loro codice VID:PID
    (li vede tutti come 3:0): il "pad preferito" di ogni giocatore va indicato
    con il nome del pad, quello che SDL ricava dal nome registrato in Windows.
  I file che non esistono ancora (es. PCSX2 mai avviato) vengono saltati.
#>
param(
    [string]$DuckStationIni,
    [string]$Pcsx2Ini,
    [string]$RetroArchCfg,
    [string]$Log
)
$ErrorActionPreference = "Stop"
Add-Type -Namespace RetroWin -Name XInput -MemberDefinition @'
[DllImport("xinput1_4.dll")] public static extern int XInputGetState(int index, byte[] state);
[DllImport("xinput1_4.dll", EntryPoint = "#108")] public static extern int XInputGetCapabilitiesEx(int one, int index, int flags, byte[] caps);
'@

function Write-Log($m) { if ($Log) { Add-Content -Path $Log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" -Encoding UTF8 } }

# 1 = pulsante, croce o grilletto premuto, 0 = niente, -1 = nessun pad in quel posto
function Get-Pressed($slot) {
    $s = New-Object byte[] 16
    if ([RetroWin.XInput]::XInputGetState($slot, $s) -ne 0) { return -1 }
    return [int]([BitConverter]::ToUInt16($s, 4) -ne 0 -or $s[6] -gt 30 -or $s[7] -gt 30)
}

# Codice del pad "VID_xxxx&PID_yyyy" (es. VID_2DC8&PID_3106), $null se non si legge
function Get-PadId($slot) {
    $c = New-Object byte[] 32
    if ([RetroWin.XInput]::XInputGetCapabilitiesEx(1, $slot, 0, $c) -ne 0) { return $null }
    return "VID_{0:X4}&PID_{1:X4}" -f [BitConverter]::ToUInt16($c, 20), [BitConverter]::ToUInt16($c, 22)
}

# Nome del pad come lo vede RetroArch (SDL): il nome registrato in Windows, senza
# la prima parola se si ripete piu' avanti, come fa SDL. Es.
# "Controller (Victrix Pro BFG Wired Controller for PC)" -> "(Victrix Pro BFG Wired Controller for PC)"
# $null se Windows non ha un nome per quel pad.
function Get-PadName($id) {
    if (-not $id) { return $null }
    $n = $null
    foreach ($root in "HKCU:", "HKLM:") {
        $key = "$root\System\CurrentControlSet\Control\MediaProperties\PrivateProperties\Joystick\OEM\$id"
        $n = (Get-ItemProperty $key -ErrorAction SilentlyContinue).OEMName
        if ($n) { break }
    }
    if (-not $n) { return $null }
    $n = ($n.Trim() -replace '\s+', ' ')
    # stesso controllo di SDL_CreateJoystickName: l'inizio del nome ricompare piu' avanti?
    for ($i = 1; $i -lt $n.Length - 1; $i++) {
        $m = 0
        while ($i + $m -lt $n.Length -and [char]::ToLower($n[$m]) -eq [char]::ToLower($n[$i + $m])) { $m++ }
        if ($m -gt 0 -and $n[$m - 1] -eq ' ') { return $n.Substring($m) }
        if ($m -gt 0 -and $m -lt $n.Length -and $n[$m] -eq ' ') { return $n.Substring($m + 1) }
    }
    return $n
}

# DuckStation / PCSX2: SDL-<n> nelle sezioni [Pad1] e [Pad2]
function Set-SdlPads($name, $ini, $p1, $p2) {
    if (-not $ini) { return }
    if (-not (Test-Path $ini)) { Write-Log "${name}: manca $ini (mai avviato?), saltato"; return }
    $lines = [IO.File]::ReadAllLines($ini)
    $map = @{ "Pad1" = $p1; "Pad2" = $p2 }
    $sec = ""; $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[(.+)\]\s*$') { $sec = $matches[1]; continue }
        if ($map.ContainsKey($sec)) {
            $new = $lines[$i] -replace 'SDL-\d+/', "SDL-$($map[$sec])/"
            if ($new -cne $lines[$i]) { $lines[$i] = $new; $changed = $true }
        }
    }
    if ($changed) { [IO.File]::WriteAllLines($ini, $lines); Write-Log "${name} aggiornato" }
    else { Write-Log "${name} era gia' cosi'" }
}

# RetroArch: "pad preferito" di ogni giocatore (tipo 1 = preferito, 0 = nessuno).
# $names: nomi dei pad dei giocatori 1 e 2 ($null = nessun pad preferito)
function Set-RetroArchPads($cfg, $names) {
    if (-not $cfg) { return }
    if (-not (Test-Path $cfg)) { Write-Log "RetroArch: manca $cfg, saltato"; return }
    $values = [ordered]@{}
    for ($n = 1; $n -le 2; $n++) {
        $name = $names[$n - 1]
        $values["input_player${n}_device_reservation_type"] = if ($name) { "1" } else { "0" }
        $values["input_player${n}_reserved_device"] = if ($name) { $name } else { "" }
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.AddRange([string[]][IO.File]::ReadAllLines($cfg))
    $changed = $false
    foreach ($k in $values.Keys) {
        $line = "$k = `"$($values[$k])`""
        $i = $lines.FindIndex({ param($l) $l -match ('^\s*' + [regex]::Escape($k) + '\s*=') })
        if ($i -ge 0) {
            if ($lines[$i] -cne $line) { $lines[$i] = $line; $changed = $true }
        } else { $lines.Add($line); $changed = $true }
    }
    if ($changed) { [IO.File]::WriteAllLines($cfg, $lines); Write-Log "RetroArch aggiornato" }
    else { Write-Log "RetroArch era gia' cosi'" }
}

if ($Log -and (Test-Path $Log)) { Remove-Item $Log }   # il log tiene solo l'ultimo avvio
$prev = @(0..3 | ForEach-Object { Get-Pressed $_ })   # pulsanti gia' premuti all'avvio non contano
$p1 = -1; $tick = 0
while ($p1 -lt 0) {
    Start-Sleep -Milliseconds 30
    # ogni 2 secondi circa: ES-DE e' ancora aperto?
    if ((++$tick % 66) -eq 0 -and -not (Get-Process ES-DE -ErrorAction SilentlyContinue)) {
        Write-Log "ES-DE chiuso senza pulsanti premuti: niente da fare"; return
    }
    foreach ($i in 0..3) {
        $now = Get-Pressed $i
        if ($now -eq 1 -and $prev[$i] -ne 1) { $p1 = $i; break }
        $prev[$i] = $now
    }
}

# Giocatore 2: il primo altro pad collegato (o un posto libero se c'e' un solo pad)
$p2pad = @(0..3 | Where-Object { $_ -ne $p1 -and (Get-Pressed $_) -ge 0 })[0]
$p2 = if ($null -ne $p2pad) { $p2pad } elseif ($p1 -eq 0) { 1 } else { 0 }
$id1 = Get-PadId $p1
$id2 = if ($null -ne $p2pad) { Get-PadId $p2pad } else { $null }
$name1 = Get-PadName $id1
$name2 = Get-PadName $id2
Write-Log "Giocatore 1 = pad nel posto $p1 ($id1 '$name1'), Giocatore 2 = posto $p2 ($(if ($id2) { "$id2 '$name2'" } else { 'nessun pad' }))"

Set-SdlPads "DuckStation" $DuckStationIni $p1 $p2
Set-SdlPads "PCSX2" $Pcsx2Ini $p1 $p2
if (-not $name1) {
    Write-Log "RetroArch: Windows non ha un nome per il pad del Giocatore 1, saltato"
} elseif ($name1 -eq $name2) {
    # due pad uguali: RetroArch non li distingue dal nome, resta il suo ordine
    Write-Log "RetroArch: i due pad hanno lo stesso nome, saltato"
} else {
    Set-RetroArchPads $RetroArchCfg @($name1, $name2)
}
