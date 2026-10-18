# RetroWin

Una "mini RetroDECK" per Windows: ES-DE (portable) + RetroArch con i core + DuckStation
(+ PCSX2 opzionale), con la stessa struttura di cartelle e le stesse impostazioni
predefinite di [RetroDECK](https://retrodeck.net), più le personalizzazioni RetroWin.

## Sistemi ed emulatori

RetroArch viene installato con **tutti i core** del pacchetto ufficiale della stessa
versione stabile (circa 200 core, 1,5 GB), come in RetroDECK. In tabella i principali:

| Sistema | Emulatore |
|---|---|
| NES | RetroArch – FCEUmm |
| SNES | RetroArch – Snes9x |
| Game Boy / Game Boy Color | RetroArch – Gambatte |
| Game Boy Advance | RetroArch – mGBA |
| Master System / Mega Drive / Game Gear / Sega CD (BIOS CD) | RetroArch – Genesis Plus GX |
| PC Engine / PC Engine CD (BIOS: `syscard3.pce`) | RetroArch – Beetle PCE Fast |
| Nintendo 64 | RetroArch – Mupen64Plus-Next |
| Sega Saturn | RetroArch – Beetle Saturn (BIOS: `sega_101.bin` JP, `mpr-17933.bin` US/EU) |
| Arcade / Neo Geo | RetroArch – FinalBurn Neo |
| Sega 32X | RetroArch – PicoDrive |
| Dreamcast | RetroArch – Flycast (BIOS: `dc\dc_boot.bin`) |
| Nintendo DS | RetroArch – melonDS DS |
| PSP | RetroArch – PPSSPP |
| Atari 2600 / 7800 / Lynx | RetroArch – Stella / ProSystem / Handy |
| Neo Geo Pocket, WonderSwan | RetroArch – Beetle NeoPop / Beetle Cygne |
| MSX, Commodore 64, Amiga, DOS | RetroArch – blueMSX / VICE / PUAE / DOSBox Pure |
| PlayStation | DuckStation |
| PlayStation 2 | PCSX2 (opzionale, `-SkipPCSX2` per non installarlo) |

I BIOS vanno in `<Root>\bios`.

## Installazione

Da PowerShell (non servono i permessi di amministratore):

```powershell
irm https://raw.githubusercontent.com/cagekame/RetroWin/main/bootstrap.ps1 | iex
```

Con opzioni (ad esempio senza PCSX2):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cagekame/RetroWin/main/bootstrap.ps1))) -SkipPCSX2
```

`bootstrap.ps1` scarica l'ultima release di questo progetto (o il ramo `main` se non ci
sono release) in `<Root>\Apps\_setup` e lancia `install_retro_windows.ps1`.
Da una copia locale del progetto si può lanciare direttamente:

```powershell
powershell -ExecutionPolicy Bypass -File .\install_retro_windows.ps1 -SkipPCSX2
```

| Opzione | Effetto |
|---|---|
| `-Root <cartella>` | cartella di installazione (predefinita `%USERPROFILE%\RetroWin`) |
| `-SkipPCSX2` | non installa PCSX2 |
| `-Force` | riscarica e reinstalla i programmi |
| `-ResetConfig` | riapplica le impostazioni RetroDECK e poi le personalizzazioni (con backup `.bak`) |
| `-NoDesktopShortcut` | non crea il collegamento sul Desktop |
| `-Ref <tag/ramo>` | solo `bootstrap.ps1`: versione del progetto da usare |

Lo script si può rilanciare quando si vuole: salta ciò che è già installato e non
cancella file dell'utente.

## Personalizzazioni

Le differenze rispetto a RetroDECK stanno in `custom/` e vengono applicate **sopra**
le impostazioni RetroDECK. Si scrivono solo le voci che cambiano, così gli
aggiornamenti delle impostazioni RetroDECK continuano ad arrivare.

```
custom/
  overrides/
    retroarch.cfg                 chiave = "valore"
    retroarch-core-options.cfg    chiave = "valore"
    core-options/<core>/<cartella roms>.opt   opzioni core valide solo per quella cartella
    duckstation.ini               [Sezione] + Chiave = Valore
    es_settings.xml               <tipo name="Nome" value="Valore" />
  files/                          copiati così come sono in <Root> (stessa struttura)
  branding/
    RetroWin.png                  da cui viene generata l'icona (oppure RetroWin.ico)
    splash.png                    schermata di avvio di ES-DE (o splash.svg / splash.jpg)
```

Le personalizzazioni si applicano quando cambiano, quando vengono applicate le
impostazioni RetroDECK o con `-ResetConfig`. Le modifiche fatte dai menu degli
emulatori restano finché non cambi i file in `custom/`.

I percorsi (ROM, BIOS, salvataggi...) li gestisce lo script: non vanno messi negli override.

### Personalizzazioni attuali

- Master System: formato 4:3 a tutto schermo (RetroDECK usa "auto", pixel 8:7).
- RetroArch: driver joypad `sdl2`, perché i tasti di RetroDECK sono numerati per SDL
  (con `xinput` la croce direzionale non funziona e su/giù dell'analogico sono invertiti).
- Icona e splash screen RetroWin.
- Loghi RetroWin nel tema ES-DE (`custom/files/ES-DE/themes/RetroDECK-theme-main/core/images/`).

## Nuova versione

1. Modifica e prova in locale (`install_retro_windows.ps1`).
2. Fai commit e push su `main`.
3. Su GitHub crea una release con un tag nuovo (es. `v1.1.0`): `bootstrap.ps1` usa
   sempre l'ultima release, quindi le installazioni non prendono modifiche a metà.

ROM, BIOS e salvataggi non vanno nel repository.
