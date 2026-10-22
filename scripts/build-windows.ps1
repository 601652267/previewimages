$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') {
    throw 'This script must run on Windows. Flutter cannot build Windows apps on macOS.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -eq $flutterCommand) {
    throw 'Install Flutter 3.29.3 and add its bin folder to PATH. See WINDOWS_BUILD.md.'
}
$flutterPath = $flutterCommand.Source

function Invoke-Flutter {
    param([string[]] $FlutterArguments)
    & $flutterPath @FlutterArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter command failed: flutter $($FlutterArguments -join ' ')"
    }
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'Install Visual Studio 2022 with the Desktop development with C++ workload. See WINDOWS_BUILD.md.'
}
$visualStudioPath = & $vswhere -latest -products '*' -version '[17.0,18.0)' `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ([string]::IsNullOrWhiteSpace($visualStudioPath)) {
    throw 'Visual Studio 2022 C++ tools are missing. Install the Desktop development with C++ workload.'
}

Push-Location $projectRoot
try {
    # On a fresh SDK, the first command also bootstraps the Flutter tool and
    # prints dependency resolution messages. Finish that before parsing JSON.
    Invoke-Flutter -FlutterArguments @('--version')
    $versionJson = & $flutterPath --version --machine
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read the installed Flutter version.'
    }
    $flutterVersion = (($versionJson -join "`n") | ConvertFrom-Json).frameworkVersion
    if ($flutterVersion -ne '3.29.3') {
        throw "Use Flutter 3.29.3 for this project. Installed version: $flutterVersion"
    }

    Invoke-Flutter -FlutterArguments @('pub', 'get')
    Invoke-Flutter -FlutterArguments @('analyze', '--no-pub')
    Invoke-Flutter -FlutterArguments @('test', '--no-pub')
    Invoke-Flutter -FlutterArguments @('build', 'windows', '--release', '--no-pub')

    $releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory 'previewimages.exe'))) {
        throw 'Expected x64 executable was not generated. Use a Windows x64 build environment.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory 'flutter_windows.dll'))) {
        throw 'The Flutter runtime DLL is missing from the build output.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory 'data\flutter_assets'))) {
        throw 'The Flutter assets are missing from the build output.'
    }

    $distributionDirectory = Join-Path $projectRoot 'dist'
    $packageDirectory = Join-Path $distributionDirectory 'previewimages-windows-x64'
    if (Test-Path -LiteralPath $packageDirectory) {
        Remove-Item -LiteralPath $packageDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
    Copy-Item -Path (Join-Path $releaseDirectory '*') -Destination $packageDirectory -Recurse -Force

    # Bundle the Visual C++ runtime for computers without Visual Studio installed.
    $redistRoot = Join-Path $visualStudioPath 'VC\Redist\MSVC'
    $crtDirectories = @(Get-ChildItem -LiteralPath $redistRoot -Directory |
        Sort-Object {
            # Recent Visual Studio installations also contain aliases like v143.
            if ($_.Name -match '^\d+(\.\d+){1,3}$') {
                [version]$_.Name
            } else {
                [version]'0.0'
            }
        } -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } |
        Where-Object { Test-Path -LiteralPath $_ })
    if ($crtDirectories.Count -eq 0) {
        throw 'Visual C++ x64 runtime files are missing. Repair the Visual Studio C++ installation.'
    }
    Write-Host "Bundling Visual C++ runtime from $($crtDirectories[0])"
    Copy-Item -Path (Join-Path $crtDirectories[0] '*.dll') -Destination $packageDirectory -Force
    foreach ($runtime in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageDirectory $runtime))) {
            throw "Missing runtime: $runtime"
        }
    }

    @'
Preview Images for Windows x64

Extract the entire ZIP, then double-click previewimages.exe.
Keep the DLL files and data folder beside the executable.

History automatically saves up to 10 preview arrangements, including
folder paths, region count, and browsing position. Use History to restore,
delete, or clear saved entries. Your image folders must remain accessible.
'@ | Set-Content -LiteralPath (Join-Path $packageDirectory 'README.txt') -Encoding UTF8

    $zipPath = Join-Path $distributionDirectory 'previewimages-windows-x64.zip'
    Compress-Archive -LiteralPath $packageDirectory -DestinationPath $zipPath -Force
    Write-Host "Build complete: $zipPath"
    Write-Host "Executable: $(Join-Path $packageDirectory 'previewimages.exe')"
} finally {
    Pop-Location
}
