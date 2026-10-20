# Icona e splash screen RetroWin.
# Caricato da install_retro_windows.ps1: usa le sue variabili ($Root, $Dl, $Force...).

# Crea un .ico da un'immagine, con tutte le dimensioni usate da Windows.
# Fino a 128 px formato BMP classico (letto ovunque, anche dalle vecchie API),
# 256 px in PNG. L'immagine viene centrata in un quadrato trasparente.
function New-IcoFromPng($src, $dst) {
    Add-Type -AssemblyName System.Drawing
    $img = [Drawing.Image]::FromFile($src)
    $sizes = 16, 20, 24, 32, 40, 48, 64, 96, 128, 256
    $data = @()
    try {
        foreach ($s in $sizes) {
            $bmp = New-Object Drawing.Bitmap $s, $s, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
            $g.Clear([Drawing.Color]::Transparent)
            $k = [Math]::Min($s / $img.Width, $s / $img.Height)
            $w = [int]($img.Width * $k); $h = [int]($img.Height * $k)
            $g.DrawImage($img, [int](($s - $w) / 2), [int](($s - $h) / 2), $w, $h)
            $g.Dispose()
            $ms = New-Object IO.MemoryStream
            if ($s -ge 256) { $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png) }
            else {
                # BITMAPINFOHEADER (altezza doppia: colori + maschera), righe dal basso
                $bw = New-Object IO.BinaryWriter $ms
                $bw.Write([UInt32]40); $bw.Write([Int32]$s); $bw.Write([Int32]($s * 2)); $bw.Write([UInt16]1); $bw.Write([UInt16]32)
                $bw.Write([UInt32]0); $bw.Write([UInt32]0); $bw.Write([Int32]0); $bw.Write([Int32]0); $bw.Write([UInt32]0); $bw.Write([UInt32]0)
                for ($y = $s - 1; $y -ge 0; $y--) {
                    for ($x = 0; $x -lt $s; $x++) { $c = $bmp.GetPixel($x, $y); $bw.Write([byte]$c.B); $bw.Write([byte]$c.G); $bw.Write([byte]$c.R); $bw.Write([byte]$c.A) }
                }
                $stride = [int]([Math]::Ceiling($s / 32.0) * 4)
                for ($y = $s - 1; $y -ge 0; $y--) {
                    $row = New-Object byte[] $stride
                    for ($x = 0; $x -lt $s; $x++) { if ($bmp.GetPixel($x, $y).A -eq 0) { $row[[Math]::Floor($x / 8)] = $row[[Math]::Floor($x / 8)] -bor (0x80 -shr ($x % 8)) } }
                    $bw.Write($row)
                }
                $bw.Flush()
            }
            $data += , $ms.ToArray()
            $bmp.Dispose()
        }
    } finally { $img.Dispose() }
    $out = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter $out
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
    $off = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
        $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([UInt16]1); $bw.Write([UInt16]32)
        $bw.Write([UInt32]$data[$i].Length); $bw.Write([UInt32]$off)
        $off += $data[$i].Length
    }
    foreach ($p in $data) { $bw.Write($p) }
    $bw.Flush()
    [IO.File]::WriteAllBytes($dst, $out.ToArray())
}

# SVG che contiene l'immagine .png/.jpg cosi' com'e' (senza ricompressione),
# per ES-DE che come splash accetta solo graphics\splash.svg.
function New-SvgFromImage($src, $dst) {
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($src)
    try { $w = $img.Width; $h = $img.Height } finally { $img.Dispose() }
    $mime = if ($src -match '\.png$') { "image/png" } else { "image/jpeg" }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($src))
    $svg = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" ' +
           "width=`"$w`" height=`"$h`" viewBox=`"0 0 $w $h`">" +
           "<image x=`"0`" y=`"0`" width=`"$w`" height=`"$h`" xlink:href=`"data:$mime;base64,$b64`"/></svg>"
    [IO.File]::WriteAllText($dst, $svg)
}
