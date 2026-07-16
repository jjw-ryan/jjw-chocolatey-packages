import-module chocolatey-au;

function global:au_GetLatest {
    $version = (Get-Item '.\tools\Victoria ERP Client Installer.exe').VersionInfo.FileVersion
    return @{ Version = $version.Trim(); }
}

function global:au_SearchReplace {
    $sha256 = Get-FileHash '.\tools\Victoria ERP Client Installer.exe' -Algorithm SHA256
    @{
        ".\tools\chocolateyinstall.ps1" = @{
             "(^[$]checksum\s*=\s*)('.*')" = "`$1'$($sha256.Hash)'"
        }
    }
}

update -ChecksumFor none