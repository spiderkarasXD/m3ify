<#
  m3ify — Material 3 поверх Spotify Desktop (как spicetify, но без маркета и лишнего).

  m3ify.ps1 install    скопировать в %LOCALAPPDATA%\m3ify, применить тему, иконки, ярлык
  m3ify.ps1 apply      (пере)применить тему (после обновления Spotify)
  m3ify.ps1 restore    вернуть оригинальный Spotify
  m3ify.ps1 uninstall  restore + убрать ярлыки/иконки + удалить %LOCALAPPDATA%\m3ify
  m3ify.ps1 launch     проверить обновление Spotify, при нужде переприменить, запустить
  m3ify.ps1 status     показать состояние
#>
param(
  [Parameter(Position = 0)]
  [ValidateSet('install', 'apply', 'restore', 'uninstall', 'launch', 'status', 'icon')]
  [string]$Command = 'status',
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Version    = '1.3.0'
$SrcDir     = $PSScriptRoot
$HomeDir    = Join-Path $env:LOCALAPPDATA 'm3ify'
$BackupDir  = Join-Path $HomeDir 'backup'
$StateFile  = Join-Path $HomeDir 'state.json'
$IconFile   = Join-Path $HomeDir 'spotify-m3.ico'
$SpotifyDir = Join-Path $env:APPDATA 'Spotify'
$SpotifyExe = Join-Path $SpotifyDir 'Spotify.exe'
$AppsDir    = Join-Path $SpotifyDir 'Apps'
$Spa        = Join-Path $AppsDir 'xpui.spa'
$Xpui       = Join-Path $AppsDir 'xpui'
$Marker     = '<!--m3ify-->'

function Say($msg, $color = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }
function Ok($msg)  { Say "  [ok] $msg" 'Green' }
function Die($msg) { throw "m3ify: $msg" }

# язык сообщений: русский, если Windows на русском, иначе английский
$IsRussian = (Get-UICulture).TwoLetterISOLanguageName -eq 'ru'
function L($ruText, $enText) { if ($IsRussian) { $ruText } else { $enText } }

function Assert-Spotify {
  if (-not (Test-Path $SpotifyExe)) {
    if (Get-AppxPackage -Name '*Spotify*' -ErrorAction SilentlyContinue) {
      Die (L 'Spotify из Microsoft Store не поддерживается (папка защищена). Поставь версию с spotify.com/download.' 'The Microsoft Store version of Spotify is not supported (its folder is protected). Install Spotify from spotify.com/download.')
    }
    Die (L "Spotify не найден в $SpotifyDir" "Spotify not found in $SpotifyDir")
  }
}

function Stop-Spotify {
  $p = Get-Process -Name Spotify -ErrorAction SilentlyContinue
  if ($p) {
    $p | Stop-Process -Force
    $p | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
    Ok (L 'Spotify закрыт' 'Spotify closed')
  }
}

# ZipFile.ExtractToDirectory падает на записи "/" внутри xpui.spa — распаковываем сами, с защитой от путей вне папки
function Expand-Spa($zipPath, $dest) {
  $rootFull = [IO.Path]::GetFullPath($dest).TrimEnd('\') + '\'
  $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    foreach ($e in $zip.Entries) {
      $name = $e.FullName.TrimStart('/', '\')
      if (-not $name -or $name.EndsWith('/')) { continue }
      $target = [IO.Path]::GetFullPath((Join-Path $dest $name))
      if (-not $target.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { continue }
      [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
      [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
    }
  } finally { $zip.Dispose() }
}

function Get-State { if (Test-Path $StateFile) { Get-Content $StateFile -Raw | ConvertFrom-Json } }
function Save-State($obj) { $obj | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8 }

function Get-SpotifyVersion { (Get-Item $SpotifyExe).VersionInfo.ProductVersion }

function Invoke-Apply {
  Assert-Spotify
  if (-not (Test-Path (Join-Path $HomeDir 'theme\m3.css'))) { Die (L 'не установлен — запусти install.cmd' 'not installed — run install.cmd') }
  Stop-Spotify
  [void](New-Item -ItemType Directory -Force $BackupDir)

  if (Test-Path $Spa) {
    # свежий/обновлённый Spotify: бэкапим оригинал и распаковываем начисто
    Copy-Item $Spa (Join-Path $BackupDir 'xpui.spa') -Force
    Ok (L "бэкап xpui.spa (Spotify $(Get-SpotifyVersion))" "backed up xpui.spa (Spotify $(Get-SpotifyVersion))")
    if (Test-Path $Xpui) { Remove-Item $Xpui -Recurse -Force }
    Expand-Spa $Spa $Xpui
    Remove-Item $Spa -Force
    Ok (L 'xpui распакован' 'xpui extracted')
  } elseif (-not (Test-Path (Join-Path $Xpui 'index.html'))) {
    Die (L 'нет ни xpui.spa, ни xpui\index.html — переустанови Spotify' 'neither xpui.spa nor xpui\index.html found — reinstall Spotify')
  }

  $index = Join-Path $Xpui 'index.html'
  $html = [IO.File]::ReadAllText($index)
  if ($html -match 'spicetify' -and $html -notmatch [regex]::Escape($Marker)) {
    Die (L 'Spotify сейчас пропатчен spicetify. Сначала выполни: spicetify restore' 'Spotify is currently patched by spicetify. Run first: spicetify restore')
  }

  $dst = Join-Path $Xpui 'm3'
  [void](New-Item -ItemType Directory -Force $dst)
  Copy-Item (Join-Path $HomeDir 'theme\*') $dst -Force

  $v = [DateTime]::Now.Ticks
  $tag = "$Marker<link rel=""stylesheet"" href=""/m3/m3.css?v=$v""><script defer src=""/m3/m3.js?v=$v""></script><!--/m3ify-->"
  $html = [regex]::Replace($html, '<!--m3ify-->.*?<!--/m3ify-->', '', 'Singleline')
  # CSS — после стилей Spotify (в конце head), чтобы перебивать их без гонки за специфичностью
  $html = $html.Replace('</head>', "$tag</head>")
  [IO.File]::WriteAllText($index, $html, (New-Object Text.UTF8Encoding $false))
  Ok (L 'Material 3 внедрён' 'Material 3 injected')

  Save-State ([pscustomobject]@{ version = $Version; spotify = (Get-SpotifyVersion); applied = (Get-Date).ToString('s') })
}

function Invoke-Restore {
  Assert-Spotify
  Stop-Spotify
  $bak = Join-Path $BackupDir 'xpui.spa'
  if (Test-Path $Spa) {
    if (Test-Path $Xpui) { Remove-Item $Xpui -Recurse -Force }
    Ok (L 'Spotify уже оригинальный (xpui.spa на месте)' 'Spotify is already original (xpui.spa is in place)')
  } elseif (Test-Path $bak) {
    Copy-Item $bak $Spa -Force
    if (Test-Path $Xpui) { Remove-Item $Xpui -Recurse -Force }
    Ok (L 'оригинальный Spotify восстановлен' 'original Spotify restored')
  } else {
    Die (L 'нет бэкапа — переустанови Spotify поверх, это безопасно' 'no backup found — reinstall Spotify over itself, it is safe')
  }
}

# ── Иконка: Spotify-логотип в стиле Material 3 (squircle + тональные цвета) ──
function New-M3IconPng([int]$s) {
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object Drawing.Bitmap $s, $s, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
  $g.Clear([Drawing.Color]::Transparent)

  # M3 adaptive-icon «скруглённый квадрат»
  $pad = [single]($s * 0.04); $w = [single]($s - 2 * $pad); $r = [single]($w * 0.30)
  $path = New-Object Drawing.Drawing2D.GraphicsPath
  $path.AddArc($pad, $pad, 2 * $r, 2 * $r, 180, 90)
  $path.AddArc($pad + $w - 2 * $r, $pad, 2 * $r, 2 * $r, 270, 90)
  $path.AddArc($pad + $w - 2 * $r, $pad + $w - 2 * $r, 2 * $r, 2 * $r, 0, 90)
  $path.AddArc($pad, $pad + $w - 2 * $r, 2 * $r, 2 * $r, 90, 90)
  $path.CloseFigure()
  $bg = New-Object Drawing.Drawing2D.LinearGradientBrush ([Drawing.PointF]::new(0, 0)), ([Drawing.PointF]::new($s, $s)),
    ([Drawing.Color]::FromArgb(255, 0xB8, 0xF5, 0xC4)), ([Drawing.Color]::FromArgb(255, 0x7F, 0xDB, 0x95))
  $g.FillPath($bg, $path)

  # три дуги «звуковых волн» — тон on-primary-container
  $ink = [Drawing.Color]::FromArgb(255, 0x00, 0x2A, 0x12)
  $arcs = @(
    @{ w = 0.64; h = 0.42; y = 0.310; t = 0.086 },
    @{ w = 0.52; h = 0.34; y = 0.465; t = 0.072 },
    @{ w = 0.40; h = 0.26; y = 0.610; t = 0.060 }
  )
  foreach ($a in $arcs) {
    $pen = New-Object Drawing.Pen $ink, ([single]($s * $a.t))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $aw = [single]($s * $a.w); $ah = [single]($s * $a.h)
    $g.DrawArc($pen, [single](($s - $aw) / 2 + $s * 0.01), [single]($s * $a.y), $aw, $ah, 208, 124)
    $pen.Dispose()
  }
  $g.Dispose()
  $ms = New-Object IO.MemoryStream
  $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  , $ms.ToArray()
}

function New-M3Icon($outIco) {
  $sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
  $pngs = foreach ($s in $sizes) { , (New-M3IconPng $s) }
  $fs = [IO.File]::Create($outIco); $bw = New-Object IO.BinaryWriter $fs
  $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
  $offset = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = $sizes[$i] % 256
    $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$pngs[$i].Length); $bw.Write([UInt32]$offset)
    $offset += $pngs[$i].Length
  }
  foreach ($p in $pngs) { $bw.Write($p) }
  $bw.Dispose()
}

# ── Лаунчер с M3-иконкой: собираем из m3launch.cs встроенным компилятором .NET ──
$Launcher = Join-Path $HomeDir 'm3launch.exe'
$RunKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Build-Launcher {
  $cp = New-Object System.CodeDom.Compiler.CompilerParameters
  $cp.GenerateExecutable = $true
  $cp.OutputAssembly = $Launcher
  $cp.CompilerOptions = "/target:winexe /optimize /win32icon:`"$IconFile`""
  [void]$cp.ReferencedAssemblies.AddRange(@('System.dll', 'System.Core.dll'))
  Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $HomeDir 'm3launch.cs'))) -CompilerParameters $cp -WarningAction SilentlyContinue
  Ok (L 'лаунчер m3launch.exe собран' 'launcher m3launch.exe built')
}

# убирает AppUserModelID, который прошлые версии m3ify ставили в ярлыки
function Clear-LinkAumid($path) {
  if (-not (Test-Path $Launcher)) { return }
  $p = Start-Process $Launcher -ArgumentList @('--clear-lnk-aumid', "`"$path`"") -Wait -PassThru -WindowStyle Hidden
  $p.ExitCode -eq 0
}

# ── Ярлыки Spotify: «Пуск» и рабочий стол → лаунчер (он возвращает тему после обновлений), ──
# ── закрепы на панели задач → прямо Spotify.exe, чтобы закреп и окно были одной кнопкой.   ──
function Get-SpotifyShortcuts {
  $dirs = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
  )
  $sh = New-Object -ComObject WScript.Shell
  foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { continue }
    Get-ChildItem $d -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
      $l = $sh.CreateShortcut($_.FullName)
      # любой m3launch.exe, в т.ч. оставшийся по старому/песочному пути от прошлых установок
      if ($l.TargetPath -ieq $SpotifyExe -or $l.TargetPath -like '*\m3ify\m3launch.exe') { $l }
    }
  }
}

function Set-Icons {
  # что было до нас — чтобы uninstall вернул всё как было
  $saved = Join-Path $HomeDir 'shortcuts.json'
  $map = @{}
  if (Test-Path $saved) { (Get-Content $saved -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $map[$_.Name] = $_.Value } }

  foreach ($l in Get-SpotifyShortcuts) {
    if (-not $map.ContainsKey($l.FullName)) {
      $orig = $(if ($l.TargetPath -like '*\m3ify\m3launch.exe') { $SpotifyExe } else { $l.TargetPath })   # для отката — сам Spotify
      $map[$l.FullName] = [pscustomobject]@{ target = $orig; args = $l.Arguments; icon = $(if ($orig -eq $SpotifyExe -and $l.IconLocation -like '*m3ify*') { "$SpotifyExe,0" } else { $l.IconLocation }); dir = $l.WorkingDirectory }
    }
    $pinned = $l.FullName -like '*\User Pinned\TaskBar\*'
    $l.TargetPath = $(if ($pinned) { $SpotifyExe } else { $Launcher })
    $l.IconLocation = "$Launcher,0"; $l.WorkingDirectory = $SpotifyDir
    $l.Save()
    [void](Clear-LinkAumid $l.FullName)
    Ok "$(L 'ярлык' 'shortcut'): $([IO.Path]::GetFileName($l.FullName)) ($(Split-Path (Split-Path $l.FullName) -Leaf))"
  }

  # автозапуск Spotify при входе в Windows → тоже через лаунчер
  $run = (Get-ItemProperty $RunKey -Name Spotify -ErrorAction SilentlyContinue).Spotify
  if ($run -and $run -like "*$SpotifyExe*") {
    if (-not $map.ContainsKey('__run')) { $map['__run'] = $run }
    Set-ItemProperty $RunKey -Name Spotify -Value ($run.Replace($SpotifyExe, $Launcher))
    Ok (L 'автозапуск Spotify идёт через лаунчер' 'Spotify autostart now goes through the launcher')
  }
  # ярлык в «Пуске» один и называется просто «Spotify»; «Spotify M3» от прошлых версий убираем
  Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Spotify M3.lnk') -ErrorAction SilentlyContinue
  $path = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Spotify.lnk'
  if (-not (Test-Path $path)) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($path)
    $lnk.TargetPath = $Launcher; $lnk.IconLocation = "$Launcher,0"; $lnk.WorkingDirectory = $SpotifyDir
    $lnk.Save()
    $map['__created'] = $path
    Ok (L 'ярлык «Spotify» в меню Пуск' '"Spotify" shortcut added to the Start menu')
  }
  $map | ConvertTo-Json | Set-Content $saved -Encoding UTF8
  Start-Process -FilePath "$env:WINDIR\System32\ie4uinit.exe" -ArgumentList '-show' -WindowStyle Hidden -ErrorAction SilentlyContinue
}

function Reset-Icons {
  $saved = Join-Path $HomeDir 'shortcuts.json'
  if (Test-Path $saved) {
    $sh = New-Object -ComObject WScript.Shell
    (Get-Content $saved -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
      if ($_.Name -eq '__created') {
        Remove-Item $_.Value -ErrorAction SilentlyContinue
      } elseif ($_.Name -eq '__run') {
        Set-ItemProperty $RunKey -Name Spotify -Value $_.Value -ErrorAction SilentlyContinue
      } elseif (Test-Path $_.Name) {
        [void](Clear-LinkAumid $_.Name)
        $l = $sh.CreateShortcut($_.Name)
        $l.TargetPath = $_.Value.target; $l.Arguments = $_.Value.args
        $l.IconLocation = $_.Value.icon; $l.WorkingDirectory = $_.Value.dir
        $l.Save()
      }
    }
    Ok (L 'ярлыки и автозапуск Spotify возвращены' 'Spotify shortcuts and autostart restored')
  }
  # ярлыки от версии 1.0 (меняли только иконку)
  $old = Join-Path $HomeDir 'icons.json'
  if (Test-Path $old) {
    $sh = New-Object -ComObject WScript.Shell
    (Get-Content $old -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
      if (Test-Path $_.Name) { $l = $sh.CreateShortcut($_.Name); if ($l.TargetPath -ieq $SpotifyExe) { $l.IconLocation = $_.Value; $l.Save() } }
    }
  }
  Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Spotify M3.lnk') -ErrorAction SilentlyContinue
}

function Invoke-Install {
  Assert-Spotify
  Say "`n  m3ify $Version — Material 3 $(L 'для' 'for') Spotify $(Get-SpotifyVersion)`n" 'Cyan'
  [void](New-Item -ItemType Directory -Force (Join-Path $HomeDir 'theme'))
  if ([IO.Path]::GetFullPath($SrcDir) -ne [IO.Path]::GetFullPath($HomeDir)) {
    Copy-Item (Join-Path $SrcDir 'theme\*') (Join-Path $HomeDir 'theme') -Force
    Copy-Item (Join-Path $SrcDir 'm3ify.ps1'), (Join-Path $SrcDir 'm3launch.cs') $HomeDir -Force
  }
  Remove-Item (Join-Path $HomeDir 'launch.vbs') -ErrorAction SilentlyContinue   # от версии 1.0
  $srcIco = Join-Path $SrcDir 'assets\spotify-m3.ico'
  if ((Test-Path $srcIco) -and ([IO.Path]::GetFullPath($srcIco) -ne [IO.Path]::GetFullPath($IconFile))) {
    Copy-Item $srcIco $IconFile -Force; Ok (L 'иконка приложения установлена' 'app icon installed')
  } elseif (-not (Test-Path $IconFile)) {
    New-M3Icon $IconFile; Ok (L 'иконка Material 3 сгенерирована' 'Material 3 icon generated')
  }
  Invoke-Apply
  if (Test-Path $Launcher) {
    # лаунчер мог быть запущен — тогда exe занят; старый вариант тоже рабочий
    try { Build-Launcher } catch { Say (L '  [!] лаунчер занят, оставлен прежний' '  [!] launcher is in use, kept the previous one') 'Yellow' }
  } else { Build-Launcher }
  Set-Icons
  Say (L "`n  Готово! Запускай Spotify как обычно — ярлыки уже идут через m3ify." "`n  Done! Launch Spotify as usual — its shortcuts now go through m3ify.") 'Cyan'
  Say (L "  Иконка M3 на панели задач: запусти Spotify, ПКМ по его кнопке → «Закрепить на панели задач», потом запусти reapply.cmd.`n" "  M3 icon on the taskbar: start Spotify, right-click its button → Pin to taskbar, then run reapply.cmd.`n") 'Cyan'
}

switch ($Command) {
  'install'   { Invoke-Install }
  'apply'     { Invoke-Apply; if (Test-Path $Launcher) { Set-Icons }; Say (L '  Готово.' '  Done.') 'Cyan' }
  'restore'   { Invoke-Restore }
  'uninstall' {
    Invoke-Restore; Reset-Icons
    Set-Location $env:TEMP
    Remove-Item $HomeDir -Recurse -Force -ErrorAction SilentlyContinue
    Ok (L 'm3ify удалён' 'm3ify removed')
  }
  'launch' {
    # Spotify при обновлении кладёт новый xpui.spa — значит тему надо переприменить
    if (Test-Path $Launcher) { Start-Process $Launcher }
    else {
      if (Test-Path $Spa) { try { $script:Quiet = $true; Invoke-Apply } catch { } }
      Start-Process $SpotifyExe
    }
  }
  'icon'   { New-M3Icon (Join-Path $SrcDir 'assets\spotify-m3.ico'); Ok 'assets\spotify-m3.ico' }
  'status' {
    Assert-Spotify
    $st = Get-State
    $patched = (Test-Path (Join-Path $Xpui 'm3\m3.css')) -and -not (Test-Path $Spa)
    Say "Spotify:  $(Get-SpotifyVersion)"
    Say "m3ify:    $(if ($patched) { L 'применён' 'applied' } elseif (Test-Path $Spa) { L 'не применён (или Spotify обновился — запусти apply)' 'not applied (or Spotify updated — run apply)' } else { L 'не применён' 'not applied' })"
    if ($st) { Say (L "Последний apply: $($st.applied) на Spotify $($st.spotify)" "Last apply: $($st.applied) on Spotify $($st.spotify)") }
  }
}
