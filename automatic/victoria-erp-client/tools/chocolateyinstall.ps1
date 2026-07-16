$ErrorActionPreference = 'Stop' # stop on all errors
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$fileLocation = Join-Path $toolsDir 'Victoria ERP Client Installer.exe'
$checksum = 'B4F08936F7C0FA0CA5B1A6234612014983872DCFABABBA287E2C8A56A390CE07'

#$chocoLogDir = Join-Path $env:ChocolateyInstall 'logs'
$innoLog = Join-Path $env:ChocolateyInstall "logs\$($env:ChocolateyPackageName)-install.log"

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  unzipLocation = $toolsDir
  fileType      = 'EXE'
  file          = $fileLocation
  softwareName  = 'Victoria ERP Client' #part or all of the Display Name as you see it in Programs and Features. It should be enough to be unique
  checksum      = $checksum
  checksumType  = 'sha256'
  silentArgs    = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=' + "$innoLog"
  validExitCodes= @(0)
}

Write-Host $packageArgs.silentArgs
Install-ChocolateyInstallPackage @packageArgs # https://docs.chocolatey.org/en-us/create/functions/install-chocolateyinstallpackage
