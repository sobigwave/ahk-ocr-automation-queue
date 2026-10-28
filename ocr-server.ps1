param(
    [Parameter(Mandatory = $true)][string]$Dir,
    [Parameter(Mandatory = $true)][int]$ParentPid,
    [string]$Language = 'zh-Hans-CN'
)
$ErrorActionPreference = 'Stop'
$us = [char]31
$utf8 = New-Object System.Text.UTF8Encoding($false)
$stopPath = Join-Path $Dir 'stop.flag'
$readyPath = Join-Path $Dir 'ready.flag'
$fatalPath = Join-Path $Dir 'fatal.flag'

function Write-TextFile([string]$Path, [string]$Text) {
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    [System.IO.File]::Move($tmp, $Path)
}

function Test-ParentAlive {
    try {
        $p = Get-Process -Id $ParentPid -ErrorAction Stop
        return ($null -ne $p)
    } catch {
        return $false
    }
}

try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DpiUtil {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
    try {
        [DpiUtil]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
    } catch {}

    [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
    [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
    [Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]

    function Await($WinRtTask, $ResultType) {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
        $netTask.Result
    }

    $script:engines = @{}
    $script:defaultEngine = $null
    try {
        $lang = New-Object Windows.Globalization.Language $Language
        $script:defaultEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
    } catch {}
    if ($null -eq $script:defaultEngine) {
        $script:defaultEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    }
    if ($null -eq $script:defaultEngine) { throw 'No Windows OCR recognizer is available.' }
    $script:engines[$Language] = $script:defaultEngine

    function Get-OcrEngine([string]$LangKey) {
        switch ($LangKey) {
            'zh'    { $tag = 'zh-Hans-CN' }
            'mixed' { $tag = 'zh-Hans-CN' }
            'en'    { $tag = 'en-US' }
            default { $tag = $Language }
        }
        if ($null -eq $tag -or $tag -eq '') { $tag = $Language }
        if ($script:engines.ContainsKey($tag)) { return $script:engines[$tag] }

        $newEngine = $null
        try {
            $newLang = New-Object Windows.Globalization.Language $tag
            $newEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($newLang)
        } catch {}
        if ($null -eq $newEngine) { $newEngine = $script:defaultEngine }
        $script:engines[$tag] = $newEngine
        return $newEngine
    }

    function Resize-Bitmap($Source, [int]$Width, [int]$Height) {
        $target = New-Object System.Drawing.Bitmap $Width, $Height
        $g = [System.Drawing.Graphics]::FromImage($target)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($Source, 0, 0, $Width, $Height)
        $g.Dispose()
        $Source.Dispose()
        return $target
    }

    function Enhance-Bitmap($Source, [string]$Mode) {
        if ($Mode -ne 'gray' -and $Mode -ne 'contrast') { return $Source }

        $target = New-Object System.Drawing.Bitmap $Source.Width, $Source.Height
        $g = [System.Drawing.Graphics]::FromImage($target)
        $matrix = New-Object System.Drawing.Imaging.ColorMatrix
        if ($Mode -eq 'gray') {
            $matrix.Matrix00 = 0.299; $matrix.Matrix01 = 0.299; $matrix.Matrix02 = 0.299
            $matrix.Matrix10 = 0.587; $matrix.Matrix11 = 0.587; $matrix.Matrix12 = 0.587
            $matrix.Matrix20 = 0.114; $matrix.Matrix21 = 0.114; $matrix.Matrix22 = 0.114
            $matrix.Matrix33 = 1; $matrix.Matrix44 = 1
        } else {
            $c = 1.35; $t = (1 - $c) / 2
            $matrix.Matrix00 = $c; $matrix.Matrix11 = $c; $matrix.Matrix22 = $c
            $matrix.Matrix33 = 1; $matrix.Matrix44 = 1
            $matrix.Matrix40 = $t; $matrix.Matrix41 = $t; $matrix.Matrix42 = $t
        }
        $attr = New-Object System.Drawing.Imaging.ImageAttributes
        $attr.SetColorMatrix($matrix, [System.Drawing.Imaging.ColorMatrixFlag]::Default, [System.Drawing.Imaging.ColorAdjustType]::Bitmap)
        $rect = New-Object System.Drawing.Rectangle 0, 0, $Source.Width, $Source.Height
        $g.DrawImage($Source, $rect, 0, 0, $Source.Width, $Source.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
        $attr.Dispose()
        $g.Dispose()
        $Source.Dispose()
        return $target
    }

    Write-TextFile $readyPath ("OK" + $us + $script:defaultEngine.RecognizerLanguage.LanguageTag)
} catch {
    Write-TextFile $fatalPath $_.Exception.Message
    exit 1
}

$png = Join-Path $Dir 'capture.png'
$maxDim = 2600
$lastParentCheck = [DateTime]::MinValue
try {
    while (-not (Test-Path -LiteralPath $stopPath)) {
        if (([DateTime]::Now - $lastParentCheck).TotalSeconds -ge 2) {
            $lastParentCheck = [DateTime]::Now
            if (-not (Test-ParentAlive)) { break }
        }

        $reqs = @(Get-ChildItem -LiteralPath $Dir -Filter '*.req' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
        foreach ($req in $reqs) {
            $id = [System.IO.Path]::GetFileNameWithoutExtension($req.Name)
            $started = [DateTime]::Now
            try {
                $raw = [System.IO.File]::ReadAllText($req.FullName, $utf8)
                $p = $raw.Split('|')
                if ($p.Count -lt 4) { throw 'Bad request.' }
                $x = [int]$p[0]; $y = [int]$p[1]; $w = [int]$p[2]; $h = [int]$p[3]
                if ($w -lt 2 -or $h -lt 2) { throw 'Region is too small.' }
                if ($w -gt 10000 -or $h -gt 10000) { throw 'Region is too large.' }

                $langKey = if ($p.Count -ge 5 -and $p[4]) { $p[4] } else { 'auto' }
                $factor = if ($p.Count -ge 6) { [int]$p[5] } else { 1 }
                if ($factor -lt 1 -or $factor -gt 4) { $factor = 1 }
                $enhMode = if ($p.Count -ge 7) { $p[6] } else { 'none' }
                if ($enhMode -ne 'gray' -and $enhMode -ne 'contrast') { $enhMode = 'none' }

                $engine = Get-OcrEngine $langKey

                $bmp = New-Object System.Drawing.Bitmap $w, $h
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $w, $h), [System.Drawing.CopyPixelOperation]::SourceCopy)
                $g.Dispose()

                # Optional upscale for small text, then respect the OCR max dimension.
                if ($factor -gt 1) {
                    $tw = $w * $factor
                    $th = $h * $factor
                    $fit = [Math]::Min(1.0, [Math]::Min($maxDim / $tw, $maxDim / $th))
                    $tw = [Math]::Max(2, [int]($tw * $fit))
                    $th = [Math]::Max(2, [int]($th * $fit))
                    $bmp = Resize-Bitmap $bmp $tw $th
                }
                if ($bmp.Width -gt $maxDim -or $bmp.Height -gt $maxDim) {
                    $fit = [Math]::Min($maxDim / $bmp.Width, $maxDim / $bmp.Height)
                    $nw = [Math]::Max(2, [int]($bmp.Width * $fit))
                    $nh = [Math]::Max(2, [int]($bmp.Height * $fit))
                    $bmp = Resize-Bitmap $bmp $nw $nh
                }
                $bmp = Enhance-Bitmap $bmp $enhMode

                $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()

                $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($png)) ([Windows.Storage.StorageFile])
                $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
                $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
                $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
                $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
                $text = $result.Text
                $bitmap.Dispose()
                $stream.Dispose()

                $elapsed = [int]([DateTime]::Now - $started).TotalMilliseconds
                Write-TextFile (Join-Path $Dir ($id + '.res')) ("OK" + $us + $elapsed + $us + $text)
            } catch {
                $elapsed = [int]([DateTime]::Now - $started).TotalMilliseconds
                $msg = $_.Exception.Message.Replace("`r", ' ').Replace("`n", ' ')
                Write-TextFile (Join-Path $Dir ($id + '.res')) ("ERR" + $us + $elapsed + $us + $msg)
            } finally {
                Remove-Item -LiteralPath $req.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Milliseconds 25
    }
} finally {
    Remove-Item -LiteralPath $png -Force -ErrorAction SilentlyContinue
}
