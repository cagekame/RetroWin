<#
  aggiornamenti.ps1 (RetroWin)
  Lanciato in background da ES-DE quando si chiude (scripts\quit\retrowin-aggiornamenti.bat):
  al massimo una volta a settimana guarda se ci sono novita' di RetroWin, ES-DE,
  RetroDECK stabile e del tema RetroDECK. Se ce ne sono, prima lancia da solo
  l'installazione dell'ultima versione di RetroWin con -CheckOnly (scaricata in una
  cartella temporanea: non modifica nulla) e mostra in una finestra cosa farebbe
  l'aggiornamento. "Aggiorna adesso" = rilancia l'installazione da GitHub
  (bootstrap.ps1) con la stessa versione e le stesse opzioni; "Rimanda" = se ne
  riparla al prossimo controllo, tra una settimana. Lavora a ES-DE chiuso perche'
  l'installazione non parte con i programmi aperti.

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

# Note di una release: la parte italiana (dopo "**Novita':**") se c'e', senza il markdown.
function Get-NoteItaliane($body) {
    $b = "$body"
    $m = [regex]::Match($b, '(?s)\*\*Novit.{1,2}:\*\*\s*(.*)$')
    if ($m.Success) { $b = $m.Groups[1].Value }
    return ($b -replace '\*\*|`', '' -replace '\r?\n', "`r`n").Trim()
}

# Scarica la release $tag di RetroWin in una cartella temporanea e ne lancia
# l'installazione con -CheckOnly sulla cartella $Root: cosa farebbe l'aggiornamento,
# senza modificare nulla. Restituisce il testo del controllo. $attesa viene chiamato
# di continuo mentre si aspetta (per tenere viva la finestra "controllo in corso").
function Invoke-CheckOnly($tag, [scriptblock]$attesa) {
    $tmp = Join-Path $env:TEMP ("RetroWin-controllo-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp "RetroWin.zip"
        Invoke-WebRequest -Uri "https://github.com/$Repo/archive/$tag.zip" -OutFile $zip -UseBasicParsing -TimeoutSec 60 -Headers @{ "User-Agent" = "RetroWinUpdate" }
        Expand-Archive $zip (Join-Path $tmp "src")
        $inst = Get-ChildItem (Join-Path $tmp "src") -Recurse -Filter "install_retro_windows.ps1" | Select-Object -First 1
        if (-not $inst) { throw "install_retro_windows.ps1 non trovato in RetroWin $tag" }
        $out = Join-Path $tmp "out.txt"; $err = Join-Path $tmp "err.txt"
        $p = Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($inst.FullName)`" -Root `"$Root`" -CheckOnly $Opzioni"
        $null = $p.Handle   # senza, ExitCode a volte resta vuoto
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.HasExited) {
            if ($attesa) { & $attesa }
            if ($sw.Elapsed.TotalMinutes -gt 5) { $p.Kill(); throw "il controllo non ha finito entro 5 minuti" }
            Start-Sleep -Milliseconds 100
        }
        # solo le righe del controllo (non i download dei file RetroDECK)
        $righe = @(Get-Content $out -ErrorAction SilentlyContinue) |
            Where-Object { $_ -match '^\s*\[[*!]\]' -and $_ -notmatch "Scarico |Gia' scaricato|Download non riuscito" } |
            ForEach-Object { $_ -replace '^\s*\[\*\] ', '' -replace '^\s*\[!\] ', '(!) ' }
        $testo = $righe -join "`r`n"
        if ($p.ExitCode -ne 0) {
            $e = "$(Get-Content $err -Raw -ErrorAction SilentlyContinue)".Trim()
            throw "il controllo e' finito con un errore (codice $($p.ExitCode)).`r`n$testo`r`n$e"
        }
        if (-not $testo) { throw "il controllo non ha scritto nulla" }
        return $testo
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# Finestra con il risultato del controllo e i pulsanti Aggiorna (Yes) / Rimanda (No).
function New-RisultatoForm($intro, $testo) {
    $font = New-Object System.Drawing.Font "Segoe UI", 9
    $f = New-Object System.Windows.Forms.Form -Property @{
        Text = "Aggiornamento RetroWin"; Width = 860; Height = 600; StartPosition = "CenterScreen"
        TopMost = $true; MinimizeBox = $false; Font = $font }
    # l'ordine conta: il riquadro che riempie va aggiunto per primo
    $f.Controls.Add((New-Object System.Windows.Forms.TextBox -Property @{
        Multiline = $true; ReadOnly = $true; ScrollBars = "Vertical"; WordWrap = $true; Dock = "Fill"
        Font = (New-Object System.Drawing.Font "Consolas", 10); Text = $testo; BackColor = [System.Drawing.SystemColors]::Window }))
    $f.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text = $intro; Dock = "Top"; Height = 34; Padding = (New-Object System.Windows.Forms.Padding 8, 10, 8, 0) }))
    $f.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text = "Giochi, salvataggi e impostazioni restano. Prima di aggiornare viene fatta una copia delle impostazioni " +
               "(in backups\RetroWin) e, se poi un programma non va, si puo' tornare alla sua versione di prima."
        Dock = "Bottom"; Height = 44; Padding = (New-Object System.Windows.Forms.Padding 8, 6, 8, 0) }))
    # pulsanti in basso a destra (la fila si allinea da sola alla larghezza della finestra)
    $bar = New-Object System.Windows.Forms.FlowLayoutPanel -Property @{
        Dock = "Bottom"; Height = 46; FlowDirection = "RightToLeft"; Padding = (New-Object System.Windows.Forms.Padding 6, 4, 6, 6) }
    $no = New-Object System.Windows.Forms.Button -Property @{ Text = "Rimanda di una settimana"; DialogResult = "No"; Width = 190; Height = 30 }
    $yes = New-Object System.Windows.Forms.Button -Property @{ Text = "Aggiorna adesso"; DialogResult = "Yes"; Width = 150; Height = 30 }
    $bar.Controls.Add($no); $bar.Controls.Add($yes)
    $f.Controls.Add($bar)
    $f.CancelButton = $no   # chiudere la finestra o premere Esc = rimanda
    $f.ActiveControl = $no
    return $f
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
            $rel = Get-Json "https://api.github.com/repos/$Repo/releases/latest"
            $v = ConvertTo-Version $rel.tag_name
            if ($v) { $script:RwTag = $rel.tag_name }   # versione usata per il controllo e l'aggiornamento
            if ($v -and $v -gt $vInst) {
                $script:RwNote = Get-NoteItaliane $rel.body
                "RetroWin $($rel.tag_name) (hai la $installata)"
            }
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

    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    # mentre si controlla: finestrella "controllo in corso"
    $wait = New-Object System.Windows.Forms.Form -Property @{
        Text = "Aggiornamento RetroWin"; Width = 460; Height = 130; StartPosition = "CenterScreen"
        TopMost = $true; FormBorderStyle = "FixedDialog"; MaximizeBox = $false; MinimizeBox = $false; ControlBox = $false }
    $wait.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text = "Ci sono aggiornamenti. Sto controllando cosa cambierebbe (senza modificare nulla)...`n`nCi vuole circa un minuto."
        Dock = "Fill"; Padding = (New-Object System.Windows.Forms.Padding 12); Font = (New-Object System.Drawing.Font "Segoe UI", 9) }))
    $wait.Show(); [System.Windows.Forms.Application]::DoEvents()
    $tag = if ($script:RwTag) { $script:RwTag } else { $installata }
    try {
        $dettagli = Invoke-CheckOnly $tag { [System.Windows.Forms.Application]::DoEvents() }
        $intro = "Niente e' stato ancora modificato. Ecco cosa farebbe l'aggiornamento:"
        Write-Log "Controllo:`r`n$dettagli"
    } catch {
        $dettagli = $_.Exception.Message
        $intro = "Non sono riuscito a controllare i dettagli. Puoi aggiornare lo stesso o rimandare:"
        Write-Log "Controllo non riuscito: $dettagli"
    }
    $wait.Close(); $wait.Dispose()

    $testo = "Novita':`r`n- " + ($novita -join "`r`n- ") + "`r`n`r`n"
    if ($script:RwNote) { $testo += "Cosa c'e' di nuovo in RetroWin ${tag}:`r`n$($script:RwNote)`r`n`r`n" }
    $testo += $dettagli
    $f = New-RisultatoForm $intro $testo
    $risposta = $f.ShowDialog()
    $f.Dispose()
    if ($risposta -ne "Yes") { Write-Log "Aggiornamento rimandato"; return }

    Write-Log "Aggiornamento avviato (RetroWin $tag)"
    # -Ref: si installa la stessa versione di RetroWin usata per il controllo
    $cmd = "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/$Repo/main/bootstrap.ps1))) " +
           "-Root '$($Root -replace "'", "''")' -Ref '$tag' $Opzioni; " +
           "Write-Host ''; Read-Host 'Aggiornamento finito: premi Invio per chiudere'"
    # -EncodedCommand: nessun problema di virgolette tra Start-Process e PowerShell
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
} catch {
    Write-Log "Errore: $($_.Exception.Message)"
}
