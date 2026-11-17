# Génère le logo « Manga Reader » : icône Android (legacy + adaptive + monochrome),
# image de lancement (splash) et logo affiché dans l'application.
#
# Aucune dépendance externe : uniquement System.Drawing.
# Usage : powershell -ExecutionPolicy Bypass -File tool\make_icons.ps1
#
# Le dessin reproduit assets\logo\logo.svg (et logo_monochrome.svg) :
#   fond sombre arrondi, deux pages superposées, page avant découpée en cases
#   (1 bandeau + 2 cases), la case du bas à droite mise en avant en orange.
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$res = Join-Path $root 'android\app\src\main\res'

# --- palette (identique à assets\logo\logo.svg) ------------------------------
$BgStart = '#1B1E27'
$BgEnd = '#0B0C10'
$AccStart = '#FF9A5A'
$AccEnd = '#FF6B35'

function New-RoundedPath {
  param([single]$x, [single]$y, [single]$w, [single]$h, [single]$r)
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function New-Solid {
  param([int]$a, [int]$r, [int]$g, [int]$b)
  return [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($a, $r, $g, $b))
}

function New-GradientBrush {
  param([System.Drawing.RectangleF]$rect, [string]$from, [string]$to, [double]$angle)
  return [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $rect,
    [System.Drawing.ColorTranslator]::FromHtml($from),
    [System.Drawing.ColorTranslator]::FromHtml($to),
    $angle
  )
}

# Remplit un rectangle arrondi dans le repère courant.
function Add-RoundedRect {
  param($g, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r, $brush)
  $p = New-RoundedPath $x $y $w $h $r
  $g.FillPath($brush, $p)
  $p.Dispose()
}

# Dessine le mark (les deux pages) centré dans un carré de côté $S.
# $mono = true : tout en blanc, cases évidées (couche monochrome Android).
function Draw-Glyph {
  param($g, [int]$S, [double]$glyphScale, [bool]$mono)

  $cx = $S / 2.0
  $cy = $S / 2.0
  $u = $S * $glyphScale

  $pw = 0.60 * $u     # largeur d'une page
  $ph = 0.78 * $u     # hauteur d'une page
  $rad = 0.09 * $u    # rayon des coins de page

  # ---- page arrière (décalée, inclinée) ----
  $state = $g.Save()
  $g.TranslateTransform(($cx - 0.09 * $u), ($cy + 0.02 * $u))
  $g.RotateTransform(-9)
  if ($mono) {
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, [single](0.048 * $u))
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $path = New-RoundedPath (-$pw / 2) (-$ph / 2) $pw $ph $rad
    $g.DrawPath($pen, $path)
    $path.Dispose()
    $pen.Dispose()
  } else {
    $back = New-Solid 90 255 255 255
    Add-RoundedRect $g (-$pw / 2) (-$ph / 2) $pw $ph $rad $back
    $back.Dispose()
  }
  $g.Restore($state)

  # ---- page avant (blanche) ----
  $state = $g.Save()
  $g.TranslateTransform(($cx + 0.05 * $u), $cy)
  $g.RotateTransform(7)

  $white = New-Solid 255 255 255 255
  Add-RoundedRect $g (-$pw / 2) (-$ph / 2) $pw $ph $rad $white
  $white.Dispose()

  # découpage en cases (coordonnées locales à la page)
  $m = 0.11 * $pw            # marge intérieure
  $iw = $pw - 2 * $m         # largeur utile
  $gap = 0.07 * $pw          # gouttière entre les cases
  $pr = 0.03 * $u            # rayon des coins de case

  $topX = (-$pw / 2) + $m
  $topY = (-$ph / 2) + $m
  $topH = 0.40 * $ph
  $botY = $topY + $topH + $gap
  $botH = ($ph / 2) - $m - $botY
  $halfW = ($iw - $gap) / 2.0
  $rightX = $topX + $halfW + $gap

  if ($mono) {
    # Cases évidées : la teinte appliquée par le système les fera apparaître.
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $hole = New-Solid 0 0 0 0
    Add-RoundedRect $g $topX $topY $iw $topH $pr $hole
    Add-RoundedRect $g $topX $botY $halfW $botH $pr $hole
    Add-RoundedRect $g $rightX $botY $halfW $botH $pr $hole
    $hole.Dispose()
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
  } else {
    $dark = New-Solid 255 20 22 28
    Add-RoundedRect $g $topX $topY $iw $topH $pr $dark
    Add-RoundedRect $g $topX $botY $halfW $botH $pr $dark
    $dark.Dispose()

    # case mise en avant
    $rect = [System.Drawing.RectangleF]::new($rightX, $botY, $halfW, $botH)
    $accent = New-GradientBrush $rect $AccStart $AccEnd 45.0
    Add-RoundedRect $g $rightX $botY $halfW $botH $pr $accent
    $accent.Dispose()
  }

  $g.Restore($state)
}

function New-Graphics {
  param([System.Drawing.Bitmap]$bmp)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  return $g
}

# Icône complète : fond sombre arrondi + mark.
function New-IconBitmap {
  param([int]$S, [bool]$rounded)
  $bmp = [System.Drawing.Bitmap]::new($S, $S)
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)

  $rect = [System.Drawing.RectangleF]::new(0, 0, $S, $S)
  $brush = New-GradientBrush $rect $BgStart $BgEnd 315.0
  if ($rounded) {
    $path = New-RoundedPath 0 0 $S $S ($S * 0.22)
    $g.FillPath($brush, $path)
    $path.Dispose()
  } else {
    $g.FillRectangle($brush, $rect)
  }
  $brush.Dispose()

  Draw-Glyph -g $g -S $S -glyphScale 0.60 -mono $false
  $g.Dispose()
  return $bmp
}

# Mark seul, fond transparent (couche adaptive / logo du splash).
function New-GlyphBitmap {
  param([int]$S, [double]$glyphScale, [bool]$mono)
  $bmp = [System.Drawing.Bitmap]::new($S, $S)
  $g = New-Graphics $bmp
  $g.Clear([System.Drawing.Color]::Transparent)
  Draw-Glyph -g $g -S $S -glyphScale $glyphScale -mono $mono
  $g.Dispose()
  return $bmp
}

function Save-Png {
  param($bmp, [string]$path)
  $dir = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# --- icônes de lancement -----------------------------------------------------
$densities = [ordered]@{
  'mdpi'    = 48
  'hdpi'    = 72
  'xhdpi'   = 96
  'xxhdpi'  = 144
  'xxxhdpi' = 192
}

foreach ($name in $densities.Keys) {
  $size = $densities[$name]
  $folder = Join-Path $res "mipmap-$name"

  $legacy = New-IconBitmap -S $size -rounded $true
  Save-Png $legacy (Join-Path $folder 'ic_launcher.png')

  # couche adaptative : 108dp de large, mark dans la zone sûre de 66dp
  $layer = [int]($size * 108 / 48)
  $fg = New-GlyphBitmap -S $layer -glyphScale 0.60 -mono $false
  Save-Png $fg (Join-Path $folder 'ic_launcher_foreground.png')

  $mono = New-GlyphBitmap -S $layer -glyphScale 0.60 -mono $true
  Save-Png $mono (Join-Path $folder 'ic_launcher_monochrome.png')
}

# --- logo du splash (160dp, une image par densité) ---------------------------
$splashScales = [ordered]@{ 'mdpi' = 1.0; 'hdpi' = 1.5; 'xhdpi' = 2.0; 'xxhdpi' = 3.0; 'xxxhdpi' = 4.0 }
$splashBase = 160
foreach ($name in $splashScales.Keys) {
  $size = [int]($splashBase * $splashScales[$name])
  $splash = New-GlyphBitmap -S $size -glyphScale 0.80 -mono $false
  Save-Png $splash (Join-Path $res "drawable-$name\splash_logo.png")
}
# repli pour les très vieilles configurations
$splashFallback = New-GlyphBitmap -S $splashBase -glyphScale 0.80 -mono $false
Save-Png $splashFallback (Join-Path $res 'drawable\splash_logo.png')

# --- logo affiché dans l'application (« À propos ») --------------------------
$logo = New-IconBitmap -S 512 -rounded $true
Save-Png $logo (Join-Path $root 'assets\images\logo.png')

# --- masters 1024 px (sources de flutter_launcher_icons, cf. pubspec.yaml) ---
$master = New-IconBitmap -S 1024 -rounded $true
Save-Png $master (Join-Path $root 'assets\logo\logo_1024.png')

$masterFg = New-GlyphBitmap -S 1024 -glyphScale 0.60 -mono $false
Save-Png $masterFg (Join-Path $root 'assets\logo\logo_foreground_1024.png')

$masterMono = New-GlyphBitmap -S 1024 -glyphScale 0.60 -mono $true
Save-Png $masterMono (Join-Path $root 'assets\logo\logo_monochrome_1024.png')

Write-Output "Logo et icônes générés dans $res"
