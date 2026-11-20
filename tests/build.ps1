param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$errorsFound = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'm3ify.ps1'), [ref]$null, [ref]$errorsFound)
if ($errorsFound) { throw ($errorsFound | Out-String) }
foreach ($fn in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$HomeDir = $Destination
$IconFile = Join-Path $HomeDir 'spotify-m3.ico'
$Launcher = Join-Path $HomeDir 'm3launch.exe'
Copy-Item (Join-Path $repo 'm3launch.cs') $HomeDir
New-M3Icon $IconFile
Build-Launcher
