# Author: Secondary push handler for unpushed packages
# Checks repository for existing versions before attempting to push

<#
.SYNOPSIS
    Secondary push handler to push unpushed packages if they don't exist in the repository

.DESCRIPTION
    This plugin attempts to push any .nupkg files that exist locally but weren't pushed
    during the main update cycle. It queries the repository to avoid attempting redeployment
    of packages that already exist.

    Configuration options:
    - Enabled: Set to $true to enable (default: $true if Push is enabled)
    - SkipIfExists: Set to $true to skip pushing if version exists in repo (default: $true)
#>

param(
    $Info,
    
    # Enable secondary push pass
    [bool]$Enabled = $true,
    
    # Skip pushing if version already exists in repository
    [bool]$SkipIfExists = $true
)

if (!$Enabled) { return }

$pushUrl = if ($env:au_PushUrl) { $env:au_PushUrl } else { 'https://push.chocolatey.org' }

Write-Verbose "[SecondaryPush] Info type: $($Info.GetType().Name)"
Write-Verbose "[SecondaryPush] Info.result type: $(if ($Info.result) { $Info.result.GetType().Name } else { 'null' })"

# Get packages
$packages = @()
if (!$Info) { 
    Write-Host "  Info is null"
    return 
}

if (!$Info.result) { 
    Write-Host "  Info.result is null"
    return 
}

try {
    # Check if Info.result has a PSObject
    if (!$Info.result.PSObject) {
        Write-Host "  Info.result.PSObject is null"
        return
    }
    
    Write-Verbose "[SecondaryPush] Info.result.PSObject type: $($Info.result.PSObject.GetType().Name)"
    
    # Extract AUPackage objects from the result PSCustomObject properties
    $propCount = 0
    foreach ($prop in $Info.result.PSObject.Properties) {
        $propCount++
        $value = $prop.Value
        $valueType = if ($value) { $value.GetType().Name } else { 'null' }
        
        Write-Verbose "[SecondaryPush]   Property name: '$($prop.Name)' | Type: '$valueType'"
        
        # Check if it's an AUPackage object (has Path and Name properties)
        if ($value -and ($value.PSObject.Properties.Name -contains 'Path') -and ($value.PSObject.Properties.Name -contains 'Name')) {
            $pkgName = $value.Name
            $pkgPath = $value.Path
            Write-Verbose "[SecondaryPush]     Found AUPackage: Name='$pkgName' | Path='$pkgPath'"
            
            # Show if this exact package already in collection
            $isDuplicate = $packages | Where-Object { $_.Name -eq $pkgName -and $_.Path -eq $pkgPath }
            if ($isDuplicate) {
                Write-Verbose "[SecondaryPush]     DUPLICATE: This package is already in collection"
            }
            
            $packages += $value
        } else {
            if ($value) {
                $hasPath = $value.PSObject.Properties.Name -contains 'Path'
                $hasName = $value.PSObject.Properties.Name -contains 'Name'
                Write-Verbose "[SecondaryPush]     Not an AUPackage (has Path: $hasPath, has Name: $hasName)"
            } else {
                Write-Verbose "[SecondaryPush]     Null value"
            }
        }
    }
    Write-Verbose "[SecondaryPush] Processed $propCount properties"
} catch {
    Write-Warning "[SecondaryPush] Error processing Info.result: $_ `n$($_.InvocationInfo.PositionMessage)"
    return
}

Write-Verbose "[SecondaryPush] Total packages extracted: $($packages.Count)"

# Deduplicate packages by Name+Path combination
$uniquePackages = @()
$seenKeys = @{}
foreach ($pkg in $packages) {
    $key = "$($pkg.Name)|$($pkg.Path)"
    if (!$seenKeys[$key]) {
        $seenKeys[$key] = $true
        $uniquePackages += $pkg
    }
}

$packages = $uniquePackages
Write-Verbose "[SecondaryPush] After deduplication: $($packages.Count) unique package(s)"

# Show package collection details
if ($packages.Count -gt 0) {
    Write-Verbose "[SecondaryPush] Package collection details:"
    for ($i = 0; $i -lt $packages.Count; $i++) {
        Write-Verbose "[SecondaryPush]   [$($i+1)] Name='$($packages[$i].Name)' | Path='$($packages[$i].Path)' | Pushed=$($packages[$i].Pushed)"
    }
}

if (!$packages -or $packages.Count -eq 0) { 
    Write-Host "  No packages found to process"
    return 
}

Write-Host "  Checking for unpushed packages ($($packages.Count) total)..."

$secondaryPushed = 0
$secondarySkipped = 0

foreach ($pkg in $packages) {
    # Skip null or empty packages
    if (!$pkg) { continue }
    
    # Skip if already pushed in this run
    if ($pkg.Pushed) { 
        Write-Verbose "[SecondaryPush] $($pkg.Name): already pushed this run"
        continue 
    }
    
    Write-Verbose "[SecondaryPush] Processing: $($pkg.Name) | Path: $($pkg.Path)"
    
    $nupkgFiles = @(Get-ChildItem $pkg.Path -Filter '*.nupkg' -ErrorAction SilentlyContinue)
    
    Write-Verbose "[SecondaryPush]   Found $($nupkgFiles.Count) .nupkg file(s)"
    
    if ($nupkgFiles.Count -eq 0) {
        Write-Verbose "[SecondaryPush] $($pkg.Name): no .nupkg file found"
        continue 
    }
    
    # Sort by creation time, get newest
    $nupkg = $nupkgFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
    
    Write-Verbose "[SecondaryPush]   Using .nupkg: $($nupkg.FullName)"
    Write-Verbose "[SecondaryPush]   BaseName: $($nupkg.BaseName)"
    
    # Extract version from filename - use non-greedy match for package name
    $match = $nupkg.BaseName -match "(?<name>.+?)\.(?<version>[0-9.]+)$"
    if (!$match) { 
        Write-Host "      [ERROR] Could not parse version from filename using regex"
        Write-Verbose "[SecondaryPush] $($pkg.Name): could not parse version from filename"
        continue 
    }
    
    $packageName = $Matches['name']
    $packageVersion = $Matches['version']
    
    Write-Host "    $packageName ($packageVersion)..."
    
    # Check if version exists in repository
    if ($SkipIfExists) {
        Write-Host "      Checking repository for existing version..."
        Write-Verbose "[SecondaryPush] Checking if $packageName $packageVersion exists in repository..."
        
        # Search without --exact flag (--exact causes 0 results on Nexus)
        $searchCmd = "choco search $packageName --source `"$pushUrl`" --no-cache"
        Write-Verbose "[SecondaryPush]   Running: $searchCmd"
        
        $searchOutput = & choco search $packageName --source "$pushUrl" --no-cache 2>&1
        Write-Verbose "[SecondaryPush]   Search output lines: $($searchOutput.Count)"
        foreach ($line in $searchOutput) {
            Write-Verbose "[SecondaryPush]     > $line"
        }
        
        # Check if the exact version is in the output
        $escapedVersion = [regex]::Escape($packageVersion)
        $searchPattern = "$packageName\s+$escapedVersion"
        Write-Verbose "[SecondaryPush]   Looking for pattern: '$searchPattern'"
        
        $versionExists = $searchOutput | Select-String $searchPattern
        
        if ($versionExists) {
            Write-Host "      [EXISTS] Version exists in repository - skipping push"
            Write-Verbose "[SecondaryPush] Found existing version: $versionExists"
            $secondarySkipped++
            continue
        }
        Write-Verbose "[SecondaryPush] Version not found in repository - proceeding with push"
    }
    
    # Attempt to push
    Write-Host "      Pushing $($nupkg.Name)..."
    Push-Location $pkg.Path
    try {
        $pushOutput = & choco push $nupkg.Name --source "$pushUrl" --api-key $env:api_key 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "      [OK] Successfully pushed"
            $pkg.Pushed = $true
            $secondaryPushed++
        } else {
            Write-Verbose "[SecondaryPush]   Push output ($($pushOutput.Count) lines):"
            foreach ($line in $pushOutput) {
                Write-Verbose "[SecondaryPush]     > $line"
            }
            Write-Warning "      [FAIL] Push failed: $pushOutput"
        }
    } catch {
        Write-Warning "      [ERROR] Exception during push: $_"
    }
    finally {
        Pop-Location
    }
}

Write-Host "  Secondary push complete: $secondaryPushed pushed, $secondarySkipped skipped"
$Info.pushed += $secondaryPushed
