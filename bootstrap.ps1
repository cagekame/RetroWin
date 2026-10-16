<#
  bootstrap.ps1
  Installa RetroWin senza scaricare nulla a mano: scarica da GitHub il
  progetto cagekame/RetroWin (ultima release, oppure il ramo main se non ci
  sono release) e lancia install_retro_windows.ps1 con le sue personalizzazioni.

  Uso (PowerShell):
    irm https://raw.githubusercontent.com/cagekame/RetroWin/main/bootstrap.ps1 | iex
  con opzioni:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/cagekame/RetroWin/main/bootstrap.ps1))) -SkipPCSX2

  Opzioni: le stesse di install_retro_windows.ps1, piu'
    -Ref  release, tag o ramo da usare (es. v1.0.0 o main)
#>
param(
    [string]$Root = "$env:USERPROFILE\RetroWin",
    [string]$Ref = "",
    [switch]$SkipPCSX2,
    [switch]$Force,
    [switch]$ResetConfig,
    [switch]$NoDesktopShortcut
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Repo = "cagekame/RetroWin"

if (-not $Ref) {
    try {
        $Ref = (Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "RetroWinSetup" }).tag_name
        Write-Host "[*] RetroWin $Ref (ultima release)" -ForegroundColor Cyan
    } catch {
        $Ref = "main"
        Write-Host "[!] Nessuna release trovata: uso il ramo main" -ForegroundColor Yellow
    }
}

# Il progetto resta in <Root>\Apps\_setup\<ref>: custom\ serve anche alle esecuzioni successive.
$setup = Join-Path $Root "Apps\_setup"
$zip = Join-Path $setup "RetroWin-$Ref.zip"
$dir = Join-Path $setup $Ref
New-Item -ItemType Directory -Force -Path $setup | Out-Null
# PowerShell 5.1 con l'output rediretto tratta lo stderr di curl come errore: qui non deve fermare
$ErrorActionPreference = "Continue"
& curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -A "Mozilla/5.0 RetroWinSetup" -o $zip "https://github.com/$Repo/archive/$Ref.zip"
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -ne 0) { throw "Download di $Repo ($Ref) fallito (curl codice $LASTEXITCODE)" }
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $dir -Force
$script = Get-ChildItem $dir -Recurse -Filter "install_retro_windows.ps1" | Select-Object -First 1
if (-not $script) { throw "install_retro_windows.ps1 non trovato nel progetto scaricato" }

$a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script.FullName, "-Root", $Root)
if ($SkipPCSX2)         { $a += "-SkipPCSX2" }
if ($Force)             { $a += "-Force" }
if ($ResetConfig)       { $a += "-ResetConfig" }
if ($NoDesktopShortcut) { $a += "-NoDesktopShortcut" }
& powershell.exe @a
