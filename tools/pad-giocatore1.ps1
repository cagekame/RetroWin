<#
  pad-giocatore1.ps1 (RetroWin)
  Lanciato in background da ES-DE all'avvio (scripts\startup\retrowin-pad.bat):
  aspetta il primo pulsante premuto su un pad XInput e assegna quel pad al
  Giocatore 1 di DuckStation, l'altro pad al Giocatore 2. Poi si chiude; si
  chiude anche se ES-DE viene chiuso prima che si prema un pulsante.

  DuckStation chiama i pad SDL-0..3 nello stesso ordine dei posti XInput di
  Windows (0..3): basta riscrivere SDL-<n> nelle sezioni [Pad1] e [Pad2].
#>
param(
    [Parameter(Mandatory = $true)][string]$DuckStationIni,
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

# Identificativo del pad (VID:PID), solo per il log
function Get-PadId($slot) {
    $c = New-Object byte[] 32
    if ([RetroWin.XInput]::XInputGetCapabilitiesEx(1, $slot, 0, $c) -ne 0) { return "?" }
    return "{0:X4}:{1:X4}" -f [BitConverter]::ToUInt16($c, 20), [BitConverter]::ToUInt16($c, 22)
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
$p2 = @(0..3 | Where-Object { $_ -ne $p1 -and (Get-Pressed $_) -ge 0 })[0]
if ($null -eq $p2) { $p2 = if ($p1 -eq 0) { 1 } else { 0 } }
Write-Log "Giocatore 1 = pad nel posto $p1 ($(Get-PadId $p1)), Giocatore 2 = posto $p2 ($(Get-PadId $p2))"

if (-not (Test-Path $DuckStationIni)) { Write-Log "Manca $DuckStationIni"; return }
$lines = [IO.File]::ReadAllLines($DuckStationIni)
$map = @{ "Pad1" = $p1; "Pad2" = $p2 }
$sec = ""; $changed = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[(.+)\]\s*$') { $sec = $matches[1]; continue }
    if ($map.ContainsKey($sec)) {
        $new = $lines[$i] -replace 'SDL-\d+/', "SDL-$($map[$sec])/"
        if ($new -cne $lines[$i]) { $lines[$i] = $new; $changed = $true }
    }
}
if ($changed) { [IO.File]::WriteAllLines($DuckStationIni, $lines); Write-Log "DuckStation aggiornato" }
else { Write-Log "DuckStation era gia' cosi'" }
