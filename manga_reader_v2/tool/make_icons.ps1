# Génère l'icône de l'application (legacy + adaptive + monochrome) sans dépendance externe.
# Usage : powershell -ExecutionPolicy Bypass -File tool\make_icons.ps1
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$res = Join-Path $root 'android\app\src\main\res'

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

function New-Brush {
  param([int]$a, [int]$r, [int]$g, [int]$b)
  return [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($a, $r, $g, $b))
}

function Draw-Glyph {
  param($g, [int]$S, [double]$glyphScale, [bool]$mono)

  $cx = $S / 2.0
  $cy = $S / 2.0
  $u = $S * $glyphScale

  $pw = 0.60 * $u
  $ph = 0.78 * $u
  $radius = 0.09 * $u

  # page arrière (décalée, semi-transparente)
  $state = $g.Save()
  $g.TranslateTransform(($cx - 0.09 * $u), ($cy + 0.02 * $u))
  $g.RotateTransform(-9)
  $back = if ($mono) { New-Brush 255 255 255 255 } else { New-Brush 90 255 255 255 }
  $path = New-RoundedPath (-$pw / 2) (-$ph / 2) $pw $ph $radius
  $g.FillPath($back, $path)
  $path.Dispose()
  $back.Dispose()
  $g.Restore($state)

  # page avant (blanche)
  $state = $g.Save()
  $g.TranslateTransform(($cx + 0.05 * $u), $cy)
  $g.RotateTransform(7)
  $white = New-Brush 255 255 255 255
  $path = New-RoundedPath (-$pw / 2) (-$ph / 2) $pw $ph $radius
  $g.FillPath($white, $path)
  $path.Dispose()
  $white.Dispose()

  if (-not $mono) {
    # lignes de texte stylisées
    $lineBrush = New-Brush 210 91 76 232
    $lineW = $pw * 0.56
    $lineH = [Math]::Max(1.2, 0.045 * $u)
    $lineX = (-$pw / 2) + (0.12 * $pw)
    foreach ($oy in @(-0.14, 0.0, 0.14)) {
      $p2 = New-RoundedPath $lineX (($oy * $u) - $lineH / 2) $lineW $lineH ($lineH / 2)
      $g.FillPath($lineBrush, $p2)
      $p2.Dispose()
    }
    $lineBrush.Dispose()
  }
  $g.Restore($state)

  if (-not $mono) {
    # badge "lecture"
    $bx = $cx + 0.30 * $u
    $by = $cy + 0.33 * $u
    $br = 0.175 * $u
    $badge = New-Brush 255 255 176 32
    $g.FillEllipse($badge, ($bx - $br), ($by - $br), ($br * 2), ($br * 2))
    $badge.Dispose()

    $tri = New-Object System.Drawing.Drawing2D.GraphicsPath
    $t = $br * 0.62
    $tri.AddPolygon(@(
        [System.Drawing.PointF]::new(($bx - $t * 0.55), ($by - $t)),
        [System.Drawing.PointF]::new(($bx - $t * 0.55), ($by + $t)),
        [System.Drawing.PointF]::new(($bx + $t * 0.95), $by)
      ))
    $triangle = New-Brush 255 255 255 255
    $g.FillPath($triangle, $tri)
    $triangle.Dispose()
    $tri.Dispose()
  }
}

function New-IconBitmap {
  param([int]$S, [bool]$rounded)
  $bmp = [System.Drawing.Bitmap]::new($S, $S)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)

  $rect = [System.Drawing.RectangleF]::new(0, 0, $S, $S)
  $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $rect,
    [System.Drawing.ColorTranslator]::FromHtml('#4F46E5'),
    [System.Drawing.ColorTranslator]::FromHtml('#8B5CF6'),
    45.0
  )
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

function New-ForegroundBitmap {
  param([int]$S, [bool]$mono)
  $bmp = [System.Drawing.Bitmap]::new($S, $S)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  Draw-Glyph -g $g -S $S -glyphScale 0.60 -mono $mono
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

  # couche adaptative : 108dp de large, glyphe dans la zone sûre de 66dp
  $layer = [int]($size * 108 / 48)
  $fg = New-ForegroundBitmap -S $layer -mono $false
  Save-Png $fg (Join-Path $folder 'ic_launcher_foreground.png')

  $mono = New-ForegroundBitmap -S $layer -mono $true
  Save-Png $mono (Join-Path $folder 'ic_launcher_monochrome.png')
}

# Logo affiché dans l'application (« À propos »)
$logo = New-IconBitmap -S 512 -rounded $true
Save-Png $logo (Join-Path $root 'assets\images\logo.png')

Write-Output "Icônes générées dans $res"
