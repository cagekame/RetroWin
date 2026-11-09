<#
  aggiornamenti.ps1 (RetroWin)
  Lanciato in background da ES-DE quando si chiude (scripts\quit\retrowin-aggiornamenti.bat):
  al massimo una volta a settimana guarda se ci sono novita' di RetroWin, ES-DE,
  RetroDECK stabile e del tema RetroDECK. Se ce ne sono le elenca in un avviso di
  Windows e chiede se aggiornare. Si' = rilancia l'installazione da GitHub
  (bootstrap.ps1) con le stesse opzioni; No = se ne riparla al prossimo controllo,
  tra una settimana. Lavora a ES-DE chiuso perche' l'installazione non parte con i
  programmi aperti.

  DuckStation non fa scattare l'avviso: pubblica versioni nuove di continuo. Si
  aggiorna quando parte l'installazione per un altro motivo.

  Versione installata: <Versione> (scritta da bootstrap.ps1). Se manca, ad
  esempio con un'installazione fatta da una copia locale del progetto, non fa nulla.
#>
param(
    [string]$Root,
    [string]$Versione,
    [string]$UltimoControllo,
    [string]$Opzioni = "",      # es. "-SkipPCSX2 -NoDesktopShortcut"
    [string]$Log,
    [int]$Giorni = 7
)
$ErrorActionPreference = "Stop"
$Repo = "cagekame/RetroWin"
$Riuscito = $false              # almeno un controllo ha avuto risposta

function Write-Log($m) { if ($Log) { Add-Content -Path $Log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" -Encoding UTF8 } }

# "v1.3.2" -> [version] 1.3.2; $null se non e' una versione (es. "main")
function ConvertTo-Version($tag) {
    $v = $null
    if ([version]::TryParse(("$tag".Trim() -replace '^v', ''), [ref]$v)) { return $v }
    return $null
}

# Prima riga di un piccolo file di testo: "" se manca.
function Read-Stamp($file) {
    if (Test-Path $file) { return "$(Get-Content $file -TotalCount 1)".Trim() }
    return ""
}

function Get-Json($url) {
    return Invoke-RestMethod -Uri $url -TimeoutSec 20 -Headers @{ "User-Agent" = "RetroWinUpdate" }
}

# Ultimo commit del ramo main di un repository GitHub.
function Get-Head($repo) { return (Get-Json "https://api.github.com/repos/$repo/commits/main").sha }

# Esegue un controllo: restituisce la novita' trovata. Se uno non risponde, gli altri valgono lo stesso.
function Invoke-Controllo($nome, [scriptblock]$controllo) {
    try { & $controllo; $script:Riuscito = $true }
    catch { Write-Log "Errore controllo ${nome}: $($_.Exception.Message)" }
}

try {
    $installata = if (Test-Path $Versione) { Read-Stamp $Versione } else { "" }
    $vInst = ConvertTo-Version $installata
    if (-not $vInst) { return }

    if (Test-Path $UltimoControllo) {
        $ultimo = [datetime]::MinValue
        $txt = Read-Stamp $UltimoControllo
        if ([datetime]::TryParseExact($txt, "yyyy-MM-dd", $null, "None", [ref]$ultimo) -and
            ((Get-Date) - $ultimo).TotalDays -lt $Giorni) { return }
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $apps = Join-Path $Root "Apps"
    # componente bloccato con -Pin (file scritto da install_retro_windows.ps1): non si propone
    function Test-Bloccato($nome) { return [bool](Read-Stamp (Join-Path $apps "RetroWin\bloccato-$nome.txt")) }
    $novita = @(
        Invoke-Controllo "RetroWin" {
            $tag = (Get-Json "https://api.github.com/repos/$Repo/releases/latest").tag_name
            $v = ConvertTo-Version $tag
            if ($v -and $v -gt $vInst) { "RetroWin $tag (hai la $installata)" }
        }
        Invoke-Controllo "ES-DE" {
            if (Test-Bloccato "es-de") { return }
            $have = Read-Stamp (Join-Path $apps "ES-DE\retrowin_version.txt")
            $tag = (Get-Json "https://gitlab.com/api/v4/projects/18817634/releases/permalink/latest").tag_name
            $a = ConvertTo-Version $have; $b = ConvertTo-Version $tag
            if ($a -and $b -and $b -gt $a) { "ES-DE $tag (hai la $have)" }
        }
        Invoke-Controllo "RetroDECK" {
            if (Test-Bloccato "retrodeck") { return }
            # ultima build pubblicata (tag main-AAAAMMGG-HHMM), confrontata con il commit delle
            # impostazioni applicate; quella scartata dall'installazione non si ripropone
            $m = [regex]::Match((Read-Stamp (Join-Path $apps "_preset\es-de.txt")), 'components ([0-9a-f]{40})')
            if ($m.Success) {
                $tags = Get-Json "https://api.github.com/repos/RetroDECK/components/tags?per_page=100"
                $t = @($tags | Where-Object { $_.name -match '^main-\d{8}-\d{4}$' } | Sort-Object name -Descending | Select-Object -First 1)
                if (-not $t) { throw "nessun tag main-AAAAMMGG-HHMM in RetroDECK/components" }
                $sha = $t[0].commit.sha
                if ($sha -ne $m.Groups[1].Value -and $sha -ne (Read-Stamp (Join-Path $apps "RetroWin\retrodeck-scartata.txt"))) {
                    "RetroDECK $($t[0].name): impostazioni e versioni di RetroArch e PCSX2"
                }
            }
        }
        Invoke-Controllo "tema" {
            if (Test-Bloccato "theme") { return }
            $have = Read-Stamp (Join-Path $Root "ES-DE\themes\RetroDECK-theme-main\retrowin_version.txt")
            if ($have -and -not (Get-Head "RetroDECK/RetroDECK-theme").StartsWith($have)) { "Tema RetroDECK" }
        }
    )
    if (-not $Riuscito) { return }   # senza internet si riprova alla prossima chiusura
    # controllo riuscito: il prossimo tra una settimana, qualunque sia la risposta
    Set-Content -Path $UltimoControllo -Value (Get-Date -Format "yyyy-MM-dd") -Encoding ASCII
    if ($novita.Count -eq 0) { Write-Log "Nessun aggiornamento (RetroWin $installata)"; return }
    Write-Log "Disponibile: $($novita -join '; ')"

    # aspetta che ES-DE e gli emulatori si chiudano del tutto (al massimo un minuto)
    for ($i = 0; $i -lt 60; $i++) {
        $aperti = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
        if ($aperti.Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }

    Add-Type -AssemblyName System.Windows.Forms
    # finestra invisibile "sempre in primo piano" come proprietaria: l'avviso non resta sotto le altre
    $top = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
    $risposta = [System.Windows.Forms.MessageBox]::Show($top,
        "Ci sono aggiornamenti:`n`n- $($novita -join "`n- ")`n`n" +
        "Vuoi aggiornare adesso? Ci vogliono pochi minuti e giochi e impostazioni restano.`n`n" +
        "Se scegli No te lo ricordo tra una settimana.",
        "Aggiornamento RetroWin", "YesNo", "Information")
    $top.Dispose()
    if ($risposta -ne "Yes") { Write-Log "Aggiornamento rimandato"; return }

    Write-Log "Aggiornamento avviato"
    $cmd = "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/$Repo/main/bootstrap.ps1))) " +
           "-Root '$($Root -replace "'", "''")' $Opzioni; " +
           "Write-Host ''; Read-Host 'Aggiornamento finito: premi Invio per chiudere'"
    # -EncodedCommand: nessun problema di virgolette tra Start-Process e PowerShell
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
} catch {
    Write-Log "Errore: $($_.Exception.Message)"
}
