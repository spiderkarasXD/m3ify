<#
  m3ify — тема Material 3 для Spotify Desktop на Spicetify.

  m3ify.ps1 install    скопировать в %LOCALAPPDATA%\m3ify, применить тему, иконки, ярлык
  m3ify.ps1 apply      (пере)применить тему (после обновления Spotify)
  m3ify.ps1 restore    вернуть оригинальный Spotify
  m3ify.ps1 uninstall  restore + убрать ярлыки/иконки + удалить %LOCALAPPDATA%\m3ify
  m3ify.ps1 launch     проверить обновление Spotify, при нужде переприменить, запустить
  m3ify.ps1 status     показать состояние
#>
param(
  [Parameter(Position = 0)]
  [ValidateSet('install', 'apply', 'repair', 'restore', 'uninstall', 'launch', 'status', 'icon')]
  [string]$Command = 'status',
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Version    = '1.4.0'
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

function Get-State { if (Test-Path $StateFile) { try { Get-Content $StateFile -Raw | ConvertFrom-Json } catch { return $null } } }
function Save-State($obj) { $obj | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8 }

function Get-SpotifyVersion { (Get-Item $SpotifyExe).VersionInfo.ProductVersion }

# Spicetify owns Spotify backups and patching; m3ify is a normal theme.
function Find-Spicetify {
  $cmd = Get-Command spicetify.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $path = Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
  if (Test-Path $path) { return $path }
}

function Install-Spicetify {
  if (Find-Spicetify) { return }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $arch = if ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' }
          elseif ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x32' }
  $release = Invoke-RestMethod 'https://api.github.com/repos/spicetify/cli/releases/latest'
  $asset = @($release.assets | Where-Object { $_.name -match "^spicetify-[\d.]+-windows-$arch\.zip$" })
  if ($asset.Count -ne 1) { Die 'Spicetify release archive not found' }
  $download = $asset[0].browser_download_url
  if ($download -notlike 'https://github.com/spicetify/cli/releases/download/*') { Die 'Unexpected Spicetify download URL' }
  $temp = Join-Path $HomeDir ('download-' + [guid]::NewGuid().ToString('N'))
  [void](New-Item -ItemType Directory $temp)
  try {
    $zip = Join-Path $temp 'spicetify.zip'
    Invoke-WebRequest $download -UseBasicParsing -OutFile $zip
    if ($asset[0].digest -match '^sha256:([a-fA-F0-9]{64})$') {
      if ((Get-FileHash $zip -Algorithm SHA256).Hash -ine $Matches[1]) { Die 'Spicetify checksum mismatch' }
    }
    $dest = Join-Path $env:LOCALAPPDATA 'spicetify'
    [void](New-Item -ItemType Directory -Force $dest)
    Expand-Spa $zip $dest
    if (-not (Find-Spicetify)) { Die 'Spicetify executable missing from archive' }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $dest) {
      [Environment]::SetEnvironmentVariable('Path', (([string]$userPath).TrimEnd(';') + ';' + $dest), 'User')
    }
    Ok (L 'Spicetify установлен' 'Spicetify installed')
  } finally {
    # Only remove the concrete download directory we just created under m3ify.
    if ((Split-Path ([IO.Path]::GetFullPath($temp))) -eq [IO.Path]::GetFullPath($HomeDir)) {
      Remove-Item -LiteralPath $temp -Recurse -Force
    }
  }
}

function Quote-NativeArgument([string]$Value) {
  '"' + ([regex]::Replace(([regex]::Replace($Value, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
}

function Invoke-Spice([string[]]$Arguments) {
  $exe = Find-Spicetify
  if (-not $exe) { Die (L 'Spicetify не найден — запусти install.cmd' 'Spicetify missing — run install.cmd') }
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = $exe
  $info.Arguments = ($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $process = [Diagnostics.Process]::Start($info)
  try {
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $output = $stdout.Result + $stderr.Result
    if ($process.ExitCode -ne 0) { Die "Spicetify $($Arguments -join ' '): $output" }
    if (-not $Quiet) { Write-Host $output }
  } finally { $process.Dispose() }
}

function Get-SpiceConfig {
  $exe = Find-Spicetify
  $path = & $exe -c
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path ($path | Select-Object -Last 1))) { Die 'Cannot locate Spicetify config' }
  ($path | Select-Object -Last 1).Trim()
}

function Set-SpiceTheme {
  $config = Get-SpiceConfig
  $saved = Join-Path $HomeDir 'spicetify-settings.json'
  if (-not (Test-Path $saved)) {
    $settings = @{}
    foreach ($line in Get-Content $config) {
      if ($line -match '^\s*(current_theme|color_scheme|inject_css|inject_theme_js|replace_colors|overwrite_assets)\s*=\s*(.*?)\s*$') {
        $settings[$Matches[1]] = $Matches[2]
      }
    }
    $settings | ConvertTo-Json | Set-Content $saved -Encoding UTF8
  }
  $theme = Join-Path (Split-Path $config) 'Themes\m3ify'
  [void](New-Item -ItemType Directory -Force $theme)
  Copy-Item (Join-Path $HomeDir 'theme\m3.css') (Join-Path $theme 'user.css') -Force
  Copy-Item (Join-Path $HomeDir 'theme\m3.js') (Join-Path $theme 'theme.js') -Force
  Copy-Item (Join-Path $HomeDir 'theme\color.ini') $theme -Force
  Invoke-Spice @('config', 'current_theme', 'm3ify', 'color_scheme', 'Base', 'inject_css', '1', 'inject_theme_js', '1', 'replace_colors', '1', 'overwrite_assets', '0')
}

function Test-NeedsRepair {
  if (Test-Path (Join-Path $HomeDir 'suspended')) { return $false }
  if (Test-Path $Spa) { return $true }
  $st = Get-State
  if (-not $st -or $st.version -ne $Version -or $st.spotify -ne (Get-SpotifyVersion)) { return $true }
  $css = Join-Path $Xpui 'user.css'
  $js = Join-Path $Xpui 'extensions\theme.js'
  $index = Join-Path $Xpui 'index.html'
  if (-not (Test-Path $css) -or -not (Test-Path $js) -or -not (Test-Path $index)) { return $true }
  if ([IO.File]::ReadAllText($index) -notmatch 'theme\.js') { return $true }
  if ((Get-FileHash $js).Hash -ne (Get-FileHash (Join-Path $HomeDir 'theme\m3.js')).Hash) { return $true }
  [IO.File]::ReadAllText($css) -notmatch 'm3ify-theme:1.4.0'
}

function Invoke-Apply([switch]$Background) {
  Assert-Spotify
  if (-not (Test-Path (Join-Path $HomeDir 'theme\m3.css'))) { Die 'Theme missing — run install.cmd' }
  if ($Background) {
    if (Get-Process -Name Spotify,SpotifySetup -ErrorAction SilentlyContinue) { return }
  } else { Stop-Spotify }
  # Migrate the old direct injection only with a backup from this Spotify version.
  $st = Get-State
  if (-not (Test-Path $Spa) -and $st -and $st.version -ne $Version -and
      (Test-Path (Join-Path $Xpui 'm3\m3.css'))) {
    $bak = Join-Path $BackupDir 'xpui.spa'
    if ($st.spotify -ne (Get-SpotifyVersion) -or -not (Test-Path $bak)) { Die 'Legacy backup does not match Spotify — reinstall Spotify, then run install.cmd' }
    Copy-Item $bak $Spa -Force
  }
  Set-SpiceTheme
  if (Test-Path $Spa) { Invoke-Spice @('backup', 'apply', '-n') }
  else { Invoke-Spice @('apply', '-n') }
  Save-State ([pscustomobject]@{ version = $Version; spotify = (Get-SpotifyVersion); applied = (Get-Date).ToString('s') })
  Remove-Item (Join-Path $HomeDir 'suspended') -ErrorAction SilentlyContinue
  Ok (L 'Material 3 и Spicetify применены' 'Material 3 and Spicetify applied')
}

function Invoke-Repair {
  Assert-Spotify
  if (-not (Test-NeedsRepair)) { return }
  # Never interrupt music or compete with Spotify's updater.
  if (Get-Process -Name Spotify,SpotifySetup -ErrorAction SilentlyContinue) { return }
  $before = Get-SpotifyVersion
  Start-Sleep -Seconds 2
  if ($before -ne (Get-SpotifyVersion) -or (Get-Process -Name Spotify,SpotifySetup -ErrorAction SilentlyContinue)) { return }
  try { Invoke-Apply -Background } catch {
    Add-Content (Join-Path $HomeDir 'repair.log') ("$(Get-Date -Format s) $($_.Exception.Message)")
    # A new Spotify build may need a newer Spicetify. Try once per Spotify version.
    $attempt = Join-Path $HomeDir 'upgrade-attempt.txt'
    if ((Test-Path $attempt) -and (Get-Content $attempt -Raw).Trim() -eq $before) { throw }
    Set-Content $attempt $before
    Invoke-Spice @('upgrade')
    if (Get-Process -Name Spotify,SpotifySetup -ErrorAction SilentlyContinue) { return }
    if (-not (Test-Path $Spa)) { Invoke-Spice @('restore', '-n') }
    Invoke-Apply -Background
  }
}

function Register-AutoRepair {
  $scriptPath = Join-Path $HomeDir 'm3ify.ps1'
  $action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" repair -Quiet"
  $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 2)
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
  $taskName = 'm3ify AutoRepair ' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -RunLevel Limited -Force | Out-Null
}

function Unregister-AutoRepair {
  $taskName = 'm3ify AutoRepair ' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Invoke-Restore {
  Assert-Spotify
  Stop-Spotify
  # Suppress automatic reapplication until an explicit apply/install.
  Set-Content (Join-Path $HomeDir 'suspended') ''
  if (Test-Path $Spa) { Invoke-Spice @('backup', 'restore', '-n') }
  else { Invoke-Spice @('restore', '-n') }
  $saved = Join-Path $HomeDir 'spicetify-settings.json'
  if (Test-Path $saved) {
    foreach ($setting in (Get-Content $saved -Raw | ConvertFrom-Json).PSObject.Properties) {
      Invoke-Spice @('config', $setting.Name, [string]$setting.Value)
    }
    Remove-Item $saved
  }
  Ok (L 'оригинальный Spotify восстановлен' 'original Spotify restored')
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
  Install-Spicetify
  Invoke-Apply
  Register-AutoRepair
  if (Test-Path $Launcher) {
    # лаунчер мог быть запущен — тогда exe занят; старый вариант тоже рабочий
    try { Build-Launcher } catch { Say (L '  [!] лаунчер занят, оставлен прежний' '  [!] launcher is in use, kept the previous one') 'Yellow' }
  } else { Build-Launcher }
  Set-Icons
  Say (L "`n  Готово! Запускай Spotify как обычно — ярлыки уже идут через m3ify." "`n  Done! Launch Spotify as usual — its shortcuts now go through m3ify.") 'Cyan'
  Say (L "  Иконка M3 на панели задач: запусти Spotify, ПКМ по его кнопке → «Закрепить на панели задач», потом запусти reapply.cmd.`n" "  M3 icon on the taskbar: start Spotify, right-click its button → Pin to taskbar, then run reapply.cmd.`n") 'Cyan'
}

$mutex = New-Object Threading.Mutex($false, 'Local\m3ify-patch')
$locked = $false
try {
  try { $locked = $mutex.WaitOne(120000) } catch [Threading.AbandonedMutexException] { $locked = $true }
  if (-not $locked) { Die 'Another m3ify operation is still running' }
switch ($Command) {
  'install'   { Invoke-Install }
  'apply'     { Invoke-Apply; if (Test-Path $Launcher) { Set-Icons }; Say (L '  Готово.' '  Done.') 'Cyan' }
  'repair'    { Invoke-Repair }
  'restore'   { Invoke-Restore }
  'uninstall' {
    Invoke-Restore; Unregister-AutoRepair; Reset-Icons
    Set-Location $env:TEMP
    $removePath = [IO.Path]::GetFullPath($HomeDir)
    $expectedPath = Join-Path ([IO.Path]::GetFullPath($env:LOCALAPPDATA)) 'm3ify'
    if ($removePath -ine $expectedPath) { Die 'Unexpected uninstall path' }
    Remove-Item -LiteralPath $removePath -Recurse -Force
    Ok (L 'm3ify удалён' 'm3ify removed')
  }
  'launch' {
    Invoke-Repair
    Start-Process $SpotifyExe
  }
  'icon'   { New-M3Icon (Join-Path $SrcDir 'assets\spotify-m3.ico'); Ok 'assets\spotify-m3.ico' }
  'status' {
    Assert-Spotify
    $st = Get-State
    $patched = -not (Test-Path $Spa) -and -not (Test-NeedsRepair) -and -not (Test-Path (Join-Path $HomeDir 'suspended'))
    Say "Spotify:  $(Get-SpotifyVersion)"
    Say "m3ify:    $(if ($patched) { L 'применён' 'applied' } elseif (Test-Path $Spa) { L 'не применён (или Spotify обновился — запусти apply)' 'not applied (or Spotify updated — run apply)' } else { L 'не применён' 'not applied' })"
    if ($st) { Say (L "Последний apply: $($st.applied) на Spotify $($st.spotify)" "Last apply: $($st.applied) on Spotify $($st.spotify)") }
  }
}
} catch {
  [void](New-Item -ItemType Directory -Force $HomeDir)
  Add-Content (Join-Path $HomeDir 'repair.log') ("$(Get-Date -Format s) $($_.Exception.Message)")
  if (-not $Quiet) { Write-Error $_ -ErrorAction Continue }
  exit 1
} finally {
  if ($locked) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
