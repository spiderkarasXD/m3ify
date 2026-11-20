$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$errorsFound = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'm3ify.ps1'), [ref]$null, [ref]$errorsFound)
if ($errorsFound) { throw ($errorsFound | Out-String) }
# Load definitions only: never run installation, patch Spotify or register a real task.
foreach ($fn in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
  Invoke-Expression $fn.Extent.Text
}
$fixture = Join-Path $PSScriptRoot ('fixture-' + [guid]::NewGuid().ToString('N'))
$HomeDir = Join-Path $fixture 'm3ify'
$BackupDir = Join-Path $HomeDir 'backup'
$StateFile = Join-Path $HomeDir 'state.json'
$Xpui = Join-Path $fixture 'Spotify\Apps\xpui'
$Spa = Join-Path $fixture 'Spotify\Apps\xpui.spa'
$Version = '1.4.0'
$Quiet = $true
$IsRussian = $false
$script:spotifyVersion = '1.2.99'
$script:calls = New-Object Collections.Generic.List[string]
$script:running = $false
$script:failApply = $false
function Assert-Spotify {}
function Stop-Spotify {}
function Get-SpotifyVersion { $script:spotifyVersion }
function Get-Process { param($Name, $ErrorAction) if ($script:running) { [pscustomobject]@{ Name = 'Spotify' } } }
function Start-Sleep {}
function Get-SpiceConfig { Join-Path $fixture 'spicetify\config-xpui.ini' }
function Invoke-Spice([string[]]$Arguments) {
  $script:calls.Add(($Arguments -join ' '))
  if ($script:failApply -and $Arguments -contains 'apply') { throw 'simulated incompatible Spotify' }
  if ($Arguments -contains 'apply') {
    Remove-Item $Spa -ErrorAction SilentlyContinue
    [void](New-Item -ItemType Directory -Force (Join-Path $Xpui 'extensions'))
    Copy-Item (Join-Path $HomeDir 'theme\m3.js') (Join-Path $Xpui 'extensions\theme.js') -Force
    Copy-Item (Join-Path $HomeDir 'theme\m3.css') (Join-Path $Xpui 'user.css') -Force
    Set-Content (Join-Path $Xpui 'index.html') '<script src="extensions/theme.js"></script>'
  }
  if ($Arguments -contains 'restore') { Set-Content $Spa 'original' }
}
$script:checks = 0
function Check($condition, $message) { if (-not $condition) { throw $message }; $script:checks++ }
try {
  [void](New-Item -ItemType Directory -Force (Join-Path $HomeDir 'theme'), $BackupDir, (Split-Path (Get-SpiceConfig)), $Xpui)
  Copy-Item (Join-Path $repo 'theme\*') (Join-Path $HomeDir 'theme')
  Set-Content (Get-SpiceConfig) "[Setting]`ncurrent_theme = Previous`ncolor_scheme = Old`ninject_css = 1`ninject_theme_js = 0`nreplace_colors = 1`noverwrite_assets = 0`n[AdditionalOptions]`nextensions = keep.js"
  Check (Test-NeedsRepair) 'Missing state must require repair'
  Set-Content $Spa 'new Spotify'
  Invoke-Repair
  Check ($calls -contains 'backup apply -n') 'Spotify update must refresh the backup before applying'
  Check (-not (Test-NeedsRepair)) 'Successful apply must be healthy'
  Set-Content $StateFile '{broken json'
  Check (Test-NeedsRepair) 'Damaged state must trigger repair'
  Invoke-Repair
  $calls.Clear(); Invoke-Repair
  Check ($calls.Count -eq 0) 'Healthy repair must do nothing'
  $script:spotifyVersion = '1.3.0'
  Check (Test-NeedsRepair) 'Executable version change must trigger repair'
  $script:spotifyVersion = '1.2.99'
  Set-Content (Join-Path $Xpui 'extensions\theme.js') 'corrupted'
  Check (Test-NeedsRepair) 'Corrupted theme JS must trigger repair'
  Invoke-Repair
  Check (-not (Test-NeedsRepair)) 'Missing SPA should use existing Spicetify backup'
  Set-Content (Join-Path $Xpui 'user.css') 'another theme'
  Check (Test-NeedsRepair) 'Replaced CSS must trigger repair'
  $calls.Clear(); $script:running = $true; Invoke-Repair
  Check ($calls.Count -eq 0) 'Background repair must not interrupt a running Spotify'
  $script:running = $false; Invoke-Repair
  Invoke-Restore
  Check (Test-Path (Join-Path $HomeDir 'suspended')) 'Restore must suspend repair'
  Check ($calls -contains 'config current_theme Previous') 'Restore must put back the previous theme setting'
  Check ((Get-Content (Get-SpiceConfig) -Raw) -match 'keep.js') 'Existing extensions must be preserved'
  $calls.Clear(); Invoke-Repair
  Check ($calls.Count -eq 0) 'Restore must stay restored'
  Invoke-Apply
  Check (-not (Test-Path (Join-Path $HomeDir 'suspended'))) 'Explicit apply must resume repair'
  Set-Content (Join-Path $Xpui 'user.css') 'broken'
  $script:failApply = $true; $calls.Clear()
  try { Invoke-Repair } catch {}
  Check ($calls -contains 'upgrade') 'First failed repair should attempt a Spicetify upgrade'
  $calls.Clear()
  try { Invoke-Repair } catch {}
  Check (-not ($calls -contains 'upgrade')) 'Upgrade attempts must be limited to one per Spotify version'
  Check (Test-NeedsRepair) 'Failed repair must not report a healthy theme'
  $script:failApply = $false
  Invoke-Repair
  [void](New-Item -ItemType Directory -Force (Join-Path $Xpui 'm3'))
  Copy-Item (Join-Path $repo 'theme\m3.css') (Join-Path $Xpui 'm3\m3.css')
  Set-Content (Join-Path $BackupDir 'xpui.spa') 'legacy backup'
  Save-State ([pscustomobject]@{version='1.3.0'; spotify='0.0.0'})
  try { Invoke-Apply; throw 'Expected rejection of old backup' } catch { Check ($_.Exception.Message -match 'Legacy backup') 'Migration must reject a backup for another Spotify version' }
  Save-State ([pscustomobject]@{version='1.3.0'; spotify=(Get-SpotifyVersion)})
  $calls.Clear(); Invoke-Apply
  Check ($calls -contains 'backup apply -n') 'Matching legacy backup must migrate through Spicetify'
  Check ((Quote-NativeArgument '') -eq '""') 'Empty config values must survive native quoting'
  Check ((Quote-NativeArgument 'a b\') -eq '"a b\\"') 'Trailing slashes must survive native quoting'
  Check ((Quote-NativeArgument 'a"b') -eq '"a\"b"') 'Quotes must survive native quoting'
  $Launcher = Join-Path $HomeDir 'm3launch.exe'
  & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build.ps1') -Destination $HomeDir
  Check ($LASTEXITCODE -eq 0) 'Launcher build process must succeed'
  Check ((Get-Item $Launcher).Length -gt 0) 'Launcher must compile with its generated icon'
  Write-Host "$checks repair checks passed"
} finally {
  $resolved = [IO.Path]::GetFullPath($fixture)
  if ((Split-Path $resolved) -eq [IO.Path]::GetFullPath($PSScriptRoot) -and (Split-Path $resolved -Leaf) -like 'fixture-*') {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
