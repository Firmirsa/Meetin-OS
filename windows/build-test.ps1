$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$version = ([xml](Get-Content windows/Meetin-OS.csproj)).Project.PropertyGroup.Version
$out = Join-Path (Get-Location) 'artifacts/windows'
$payload = Join-Path $PSScriptRoot '.build/payload'
New-Item -ItemType Directory -Force $out, $payload | Out-Null
# The checked-in lock was generated outside Windows; refresh its implicit win-x64 target.
dotnet restore windows/Meetin-OS.csproj --force-evaluate
if ($LASTEXITCODE -ne 0) { throw 'Restore failed' }
dotnet build windows/Meetin-OS.csproj -c Release --no-restore -o $payload
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
dotnet run --project windows/tests/GladiaSmoke.csproj -c Release
if ($LASTEXITCODE -ne 0) { throw 'Smoke tests failed' }
$source = [ordered]@{version="$version"; commit=(git rev-parse HEAD); builtAtUTC=[DateTime]::UtcNow.ToString('o'); platform='windows-x64'; channel='test'}
$source | ConvertTo-Json | Set-Content (Join-Path $payload 'BuildSource.json') -Encoding utf8
$installer = Join-Path $out "Meetin-OS-Windows-$version.exe"
$nsis = Get-Command makensis -ErrorAction SilentlyContinue
$compiler = if ($nsis) { $nsis.Source } else { Join-Path ${env:ProgramFiles(x86)} 'NSIS/makensis.exe' }
if (!(Test-Path $compiler)) { throw 'Install NSIS first: choco install nsis -y --no-progress' }
& $compiler "/DOUTPUT_FILE=$installer" windows/installer.nsi
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
if ((Get-Item $installer).VersionInfo.ProductVersion -ne $version) { throw 'Wrong installer version' }
$source['installerSHA256'] = (Get-FileHash $installer -Algorithm SHA256).Hash
$source | ConvertTo-Json | Set-Content (Join-Path $out 'build-manifest.json') -Encoding utf8
Copy-Item windows/packages.lock.json (Join-Path $out 'packages.lock.json')
Copy-Item windows/TEST-WINDOWS.md (Join-Path $out 'LIRE-AVANT-TEST.md')
Write-Host "Test installer prepared: $installer"
