<#
  aggiornamenti.ps1 (RetroWin)
  Lanciato in background da ES-DE quando si chiude (scripts\quit\retrowin-aggiornamenti.bat):
  al massimo una volta a settimana chiede a GitHub l'ultima release di RetroWin
  e, se e' piu' nuova di quella installata, chiede con un avviso di Windows se
  aggiornare. Si' = rilancia l'installazione da GitHub (bootstrap.ps1) con le
  stesse opzioni; No = se ne riparla al prossimo controllo, tra una settimana.
  Lavora a ES-DE chiuso perche' l'installazione non parte con i programmi aperti.

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

function Write-Log($m) { if ($Log) { Add-Content -Path $Log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" -Encoding UTF8 } }

# "v1.3.2" -> [version] 1.3.2; $null se non e' una versione (es. "main")
function ConvertTo-Version($tag) {
    $v = $null
    if ([version]::TryParse(("$tag".Trim() -replace '^v', ''), [ref]$v)) { return $v }
    return $null
}

try {
    $installata = if (Test-Path $Versione) { "$(Get-Content $Versione -TotalCount 1)".Trim() } else { "" }
    $vInst = ConvertTo-Version $installata
    if (-not $vInst) { return }

    if (Test-Path $UltimoControllo) {
        $ultimo = [datetime]::MinValue
        $txt = "$(Get-Content $UltimoControllo -TotalCount 1)".Trim()
        if ([datetime]::TryParseExact($txt, "yyyy-MM-dd", $null, "None", [ref]$ultimo) -and
            ((Get-Date) - $ultimo).TotalDays -lt $Giorni) { return }
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 20 -Headers @{ "User-Agent" = "RetroWinUpdate" }
    # controllo riuscito: il prossimo tra una settimana, qualunque sia la risposta
    Set-Content -Path $UltimoControllo -Value (Get-Date -Format "yyyy-MM-dd") -Encoding ASCII
    $vNuova = ConvertTo-Version $rel.tag_name
    if (-not $vNuova -or $vNuova -le $vInst) { Write-Log "Nessun aggiornamento ($installata, ultima $($rel.tag_name))"; return }
    Write-Log "Disponibile $($rel.tag_name) (installata $installata)"

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
        "E' disponibile RetroWin $($rel.tag_name) (hai la $installata).`n`n" +
        "Vuoi aggiornare adesso? Ci vogliono pochi minuti e giochi e impostazioni restano.`n`n" +
        "Se scegli No te lo ricordo tra una settimana.",
        "Aggiornamento RetroWin", "YesNo", "Information")
    $top.Dispose()
    if ($risposta -ne "Yes") { Write-Log "Aggiornamento rimandato"; return }

    Write-Log "Aggiornamento a $($rel.tag_name) avviato"
    $cmd = "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/$Repo/main/bootstrap.ps1))) " +
           "-Root '$($Root -replace "'", "''")' $Opzioni; " +
           "Write-Host ''; Read-Host 'Aggiornamento finito: premi Invio per chiudere'"
    # -EncodedCommand: nessun problema di virgolette tra Start-Process e PowerShell
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
} catch {
    # senza internet o con GitHub che non risponde si riprova alla prossima chiusura
    Write-Log "Errore: $($_.Exception.Message)"
}
