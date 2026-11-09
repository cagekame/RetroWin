# RetroWin

🇬🇧 [English version](README.md)

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
| `-CheckOnly` | mostra cosa farebbe un aggiornamento (versione RetroDECK, voci delle impostazioni che cambierebbero, versioni dei programmi) senza installare né modificare nulla |
| `-Pin <nomi>` | blocca dei componenti alla versione attuale: `RetroDECK`, `Theme`, `ES-DE`, `RetroArch`, `DuckStation`, `PCSX2` (separati da virgola). `RetroDECK:<commit o tag>` blocca RetroDECK su quella versione |
| `-Unpin <nomi>` | toglie quei blocchi: i componenti tornano ad aggiornarsi |
| `-Rollback <nomi>` | torna alla versione precedente di `ES-DE`, `RetroArch` (con i core), `DuckStation`, `PCSX2` o `Theme`, che poi resta bloccata. Le impostazioni non cambiano |
| `-AcceptRetroDECK` | adotta una nuova versione di RetroDECK anche se spariscono molte voci (di solito viene scartata, vedi [Aggiornamenti](#aggiornamenti)) |
| `-Ref <tag/ramo>` | solo `bootstrap.ps1`: versione del progetto da usare |

Lo script si può rilanciare quando si vuole: aggiorna ciò che serve, salta il resto e
non cancella file dell'utente.

## Aggiornamenti

Per aggiornare basta rilanciare il comando di installazione.

RetroWin avvisa anche quando c'è qualcosa di nuovo: una volta a settimana, quando
chiudi ES-DE, controlla se ci sono una release più nuova di RetroWin, un ES-DE più
nuovo, una build di RetroDECK stabile più nuova o un tema RetroDECK più nuovo (i
componenti bloccati si saltano). Se trova
qualcosa, un avviso di Windows lo elenca e chiede se aggiornare adesso. **Sì** aggiorna
subito (con le stesse opzioni dell'installazione), **No** te lo ricorda tra una
settimana. Lo fa `tools/aggiornamenti.ps1` (log in `Apps\RetroWin\aggiornamenti.log`)
e funziona solo con le installazioni fatte con il comando di installazione, che salva
la versione installata. DuckStation non fa scattare l'avviso, perché pubblica versioni
nuove di continuo: si aggiorna insieme a tutto il resto.

- **Programmi.** RetroArch (con i core) e PCSX2 usano la versione indicata da
  RetroDECK in `desired_versions.sh`, se c'è; altrimenti l'ultima. ES-DE usa l'ultima
  release, DuckStation l'ultima release ufficiale (RetroDECK ne usa una sua versione
  per Linux). La versione installata è scritta in `retrowin_version.txt` nella
  cartella del programma: si scarica solo ciò che è cambiato e non si torna mai a una
  versione più vecchia (salvo con `-Rollback`). Se la versione non si può controllare
  o scaricare (niente rete, o una versione chiesta da RetroDECK che non esiste), resta
  quella installata e nel riepilogo finale il passo risulta **ATTENZIONE** invece di
  OK. Gli archivi dei programmi non contengono impostazioni, quindi aggiornando
  restano. L'archivio della versione precedente resta in `Apps\_download`, pronto per
  `-Rollback`.
- **Impostazioni RetroDECK.** Vengono dall'ultima build pubblicata di RetroDECK
  stabile (il tag `main-AAAAMMGG-HHMM` più recente di
  [RetroDECK/components](https://github.com/RetroDECK/components)), che decide anche
  le versioni di RetroArch e PCSX2; i commit tra una build e l'altra sono lavori in
  corso e si saltano. Prima di adottare una build nuova RetroWin controlla di saperla
  ancora leggere: i file devono esserci, le versioni di RetroArch e PCSX2 devono
  essere numeri di versione (o `latest`), le voci da cui dipende RetroWin devono
  esserci e nessun file può perdere più del 10% delle voci rispetto alla build in uso
  (di solito vuol dire chiavi rinominate o formato cambiato, e l'aggiornamento voce
  per voce farebbe danni). Se un controllo non passa, RetroWin resta sulla versione
  già applicata e nel riepilogo finale dice perché. Se hai guardato le differenze e
  vanno bene, lancia l'installazione con `-AcceptRetroDECK`; un file che non si
  riesce più a leggere affatto (formato cambiato) viene scartato lo stesso, perché
  serve una nuova versione di RetroWin. Le tue personalizzazioni in `custom/overrides`
  su voci che RetroDECK ha tolto o rinominato vengono elencate nel riepilogo.
  `$RdCommit` in `install_retro_windows.ps1` serve solo per una prima installazione
  quando GitHub non risponde. La prima volta le impostazioni si applicano per intero.
  Quando RetroDECK cambia, lo script confronta voce per voce le impostazioni RetroDECK
  vecchie, quelle nuove e quelle attuali: se una voce non era stata modificata prende
  il nuovo valore, se era stata modificata resta com'è. Le voci nuove si aggiungono.
  Poi si riapplicano le personalizzazioni RetroWin. Prima di ogni modifica viene
  fatto un backup `.bak`. I file RetroDECK della versione applicata restano in
  `Apps\_preset\retrodeck`, così il prossimo aggiornamento non dipende dal fatto che
  GitHub li abbia ancora.
- **Copie delle impostazioni.** Oltre ai `.bak`, prima di toccare qualsiasi cosa ogni
  esecuzione copia tutti i file di impostazioni (ES-DE, RetroArch con la cartella
  `config`, DuckStation, PCSX2) in `backups\RetroWin\<data>`, con gli stessi percorsi
  che hanno sotto `<Root>`, se sono cambiati dall'ultima copia. Restano le ultime 5.
  Per tornare indietro basta ricopiare i file al loro posto, a programmi chiusi.
- **Bloccare e tornare indietro.** `-Pin` tiene fermo un componente finché non usi
  `-Unpin`; il riepilogo finale elenca sempre cosa è bloccato. Per esempio
  `-Pin RetroDECK` tiene le impostazioni e le versioni dei programmi RetroDECK in uso,
  e `-Pin RetroDECK:main-20261002-1750` torna a quella build. `-Rollback RetroArch`
  reinstalla il RetroArch precedente con i suoi core e lo blocca. Con `-CheckOnly`
  vedi cosa cambierebbe un aggiornamento prima di farlo.
- **Tema ES-DE.** L'ultimo commit del ramo `main` di RetroDECK-theme, come RetroDECK:
  si reinstalla quando cambia (salvo blocco con `-Pin Theme`).

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
  (con anche XInput lo stesso pad compariva due volte), immagine 4:3 con ritaglio
  dell'overscan, risoluzione interna 6x, ingrandimento a pixel netti (filmati sfumati),
  PGXP attivo e sprite con filtro nitido.
- Pad del Giocatore 1: all'avvio di RetroWin il primo pad che preme un pulsante
  qualsiasi diventa il Giocatore 1 di tutti i sistemi, l'altro il Giocatore 2
  (Windows numera i pad in base all'ordine di collegamento, che non si può
  scegliere). DuckStation e PCSX2 seguono quell'ordine, quindi lo script riscrive il
  numero del pad nelle loro impostazioni. RetroArch invece vede i pad in un altro
  ordine e senza il loro codice VID:PID: lo script imposta il "pad preferito" di ogni
  giocatore con il nome del pad (quello registrato in Windows, sistemato come fa SDL).
  Lo fa `tools/pad-giocatore1.ps1`, lanciato da ES-DE come script di evento "startup";
  l'esito dell'ultimo avvio è in `Apps\RetroWin\pad-giocatore1.log`. Con due pad dello
  stesso modello RetroArch non li distingue e resta il suo ordine.
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
tools/
  pad-giocatore1.ps1        all'avvio di ES-DE: il primo pad usato diventa il Giocatore 1
  aggiornamenti.ps1         alla chiusura di ES-DE: controllo settimanale degli aggiornamenti
custom/                     personalizzazioni RetroWin (vedi sopra)
```

`install_retro_windows.ps1` ha bisogno di `lib/` e `custom/` accanto: va lanciato dalla
copia completa del progetto (`bootstrap.ps1` la scarica da solo).

## Nuova versione

1. Modifica e prova in locale (`install_retro_windows.ps1`).
2. Fai commit e push su `main`.
3. Su GitHub crea una release con un tag nuovo (es. `v1.1.0`): `bootstrap.ps1` usa
   sempre l'ultima release, quindi le installazioni non prendono modifiche a metà.

ROM, BIOS e salvataggi non vanno nel repository.

## Licenza

Rilasciato con [licenza MIT](LICENSE). RetroWin è un progetto indipendente, non
collegato al team di RetroDECK; ES-DE, RetroArch, DuckStation e PCSX2 hanno le loro
licenze e vengono scaricati dai rispettivi siti ufficiali.
