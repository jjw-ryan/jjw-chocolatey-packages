$ErrorActionPreference = 'Stop' # stop on all errors
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$fileLocation = Join-Path $toolsDir 'Victoria ERP Client Installer.exe'
$checksum = '6417E4E6CF8AA75746ECCF4EDDCCB22D93DC8AB05C1BED4DCC928A35FA5F9C1E'

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
