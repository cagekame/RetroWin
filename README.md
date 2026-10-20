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
| `-Force` | riscarica e reinstalla i programmi anche se sono aggiornati |
| `-ResetConfig` | riapplica le impostazioni RetroDECK e poi le personalizzazioni (con backup `.bak`) |
| `-NoDesktopShortcut` | non crea il collegamento sul Desktop |
| `-Ref <tag/ramo>` | solo `bootstrap.ps1`: versione del progetto da usare |

Lo script si può rilanciare quando si vuole: aggiorna ciò che serve, salta il resto e
non cancella file dell'utente.

## Aggiornamenti

Per aggiornare basta rilanciare il comando di installazione.

- **Programmi.** RetroArch (con i core) e PCSX2 usano la versione indicata da
  RetroDECK in `desired_versions.sh`, se c'è; altrimenti l'ultima. ES-DE usa l'ultima
  release, DuckStation l'ultima release ufficiale (RetroDECK ne usa una sua versione
  per Linux). La versione installata è scritta in `retrowin_version.txt` nella
  cartella del programma: si scarica solo ciò che è cambiato, non si torna mai a una
  versione più vecchia e, senza rete, resta quella installata. Gli archivi dei
  programmi non contengono impostazioni, quindi aggiornando restano.
- **Impostazioni RetroDECK.** Sono fissate al commit `$RdCommit` di
  [RetroDECK/components](https://github.com/RetroDECK/components) (in
  `install_retro_windows.ps1`). La prima volta si applicano per intero. Quando
  `$RdCommit` cambia, lo script confronta voce per voce le impostazioni RetroDECK
  vecchie, quelle nuove e quelle attuali: se una voce non era stata modificata prende
  il nuovo valore, se era stata modificata resta com'è. Le voci nuove si aggiungono.
  Poi si riapplicano le personalizzazioni RetroWin. Prima di ogni modifica viene
  fatto un backup `.bak`.
- **Tema ES-DE.** Fissato a un commit di RetroDECK-theme (`$RdThemeUrl`): si
  reinstalla quando cambia.

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
- DuckStation: niente finestra console accanto al gioco, pad letti solo tramite SDL
  (con anche XInput lo stesso pad compariva due volte), immagine 4:3 con i bordi neri
  ritagliati mantenendo le proporzioni originali.
- Icona e splash screen RetroWin.
- Loghi RetroWin nel tema ES-DE (`custom/files/ES-DE/themes/RetroDECK-theme-main/core/images/`).

## Struttura del progetto

```
bootstrap.ps1               scarica il progetto da GitHub e lancia l'installazione
install_retro_windows.ps1   configurazione e passi dell'installazione
lib/
  common.ps1                messaggi, cartelle, download, archivi, collegamenti, backup
  config.ps1                file di impostazioni e aggiornamento delle impostazioni RetroDECK
  programs.ps1              installazione e aggiornamento dei programmi
  branding.ps1              icona e splash screen
custom/                     personalizzazioni RetroWin (vedi sopra)
```

`install_retro_windows.ps1` ha bisogno di `lib/` e `custom/` accanto: va lanciato dalla
copia completa del progetto (`bootstrap.ps1` la scarica da solo).

## Nuova versione

1. Modifica e prova in locale (`install_retro_windows.ps1`). Per seguire una
   RetroDECK più recente cambia `$RdCommit` (ed eventualmente `$RdThemeUrl`) con il
   commit voluto.
2. Fai commit e push su `main`.
3. Su GitHub crea una release con un tag nuovo (es. `v1.1.0`): `bootstrap.ps1` usa
   sempre l'ultima release, quindi le installazioni non prendono modifiche a metà.

ROM, BIOS e salvataggi non vanno nel repository.
