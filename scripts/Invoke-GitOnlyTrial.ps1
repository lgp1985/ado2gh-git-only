param(
    [Parameter(Mandatory)]
    [string]$SourceOrg,
    [Parameter(Mandatory)]
    [string]$SourceProject,
    [Parameter(Mandatory)]
    [string]$SourceRepo,
    [Parameter(Mandatory)]
    [string]$TargetOwner,
    [Parameter(Mandatory)]
    [string]$TargetRepo,
    [string]$IncludeLfs = 'false',
    [Parameter(Mandatory)]
    [string]$TrialConfirmation
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot/Validate-GitOnlyInputs.ps1" `
    -SourceOrg $SourceOrg `
    -SourceProject $SourceProject `
    -SourceRepo $SourceRepo `
    -TargetOwner $TargetOwner `
    -TargetRepo $TargetRepo `
    -IncludeLfs $IncludeLfs `
    -ExecuteTrial 'true' `
    -TrialConfirmation $TrialConfirmation

if ([string]::IsNullOrWhiteSpace($env:ADO_PAT)) {
    throw 'The ADO_PAT secret is required for a real Git-only trial.'
}
if ([string]::IsNullOrWhiteSpace($env:GH_PAT) -or [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    throw 'The GH_PAT secret is required for the destination repository and GitHub CLI authentication.'
}

$escapedOrg = [uri]::EscapeDataString($SourceOrg)
$escapedProject = [uri]::EscapeDataString($SourceProject)
$escapedRepo = [uri]::EscapeDataString($SourceRepo)
$sourceUrl = [uri]"https://dev.azure.com/$escapedOrg/$escapedProject/_git/$escapedRepo"
$targetUrl = [uri]"https://github.com/$TargetOwner/$TargetRepo.git"
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ado2gh-git-only-$([guid]::NewGuid().ToString('N'))"
$mirrorPath = Join-Path $temporaryRoot 'source.git'
$originalConfigCount = $env:GIT_CONFIG_COUNT
$originalConfigValues = @{}
$credentialEnvironmentSet = $false
$credentialEntries = [System.Collections.Generic.List[object]]::new()

function Add-GitCredentialHeader {
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][string]$TokenVariable,
        [Parameter(Mandatory)][AllowEmptyString()][string]$UserName
    )

    $token = [Environment]::GetEnvironmentVariable($TokenVariable)
    if ([string]::IsNullOrWhiteSpace($token)) {
        return
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${UserName}:$token"))
    $credentialEntries.Add(@{
        Key = "http.https://$($Uri.Host)/.extraheader"
        Value = "AUTHORIZATION: Basic $encoded"
    })
}

function Set-GitCredentialEnvironment {
    $env:GIT_CONFIG_COUNT = [string]$credentialEntries.Count
    for ($index = 0; $index -lt $credentialEntries.Count; $index++) {
        foreach ($suffix in @('KEY', 'VALUE')) {
            $variableName = "GIT_CONFIG_${suffix}_$index"
            $originalConfigValues[$variableName] = [Environment]::GetEnvironmentVariable($variableName)
        }
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$index", $credentialEntries[$index].Key)
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$index", $credentialEntries[$index].Value)
    }
    $script:credentialEnvironmentSet = $true
}

function Restore-GitCredentialEnvironment {
    for ($index = 0; $index -lt $credentialEntries.Count; $index++) {
        foreach ($suffix in @('KEY', 'VALUE')) {
            $variableName = "GIT_CONFIG_${suffix}_$index"
            [Environment]::SetEnvironmentVariable($variableName, $originalConfigValues[$variableName])
        }
    }
    $env:GIT_CONFIG_COUNT = $originalConfigCount
}

function Invoke-Git {
    param(
        [string]$WorkingDirectory,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    if ($WorkingDirectory) {
        $output = @(& git -c safe.bareRepository=all -C $WorkingDirectory @Arguments 2>&1)
    }
    else {
        $output = @(& git -c safe.bareRepository=all @Arguments 2>&1)
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed (exit $LASTEXITCODE): $($output -join ' ')"
    }
    return @($output | ForEach-Object { $_.ToString() })
}

function Invoke-Gh {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& gh @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI command failed (exit $LASTEXITCODE): $($output -join ' ')"
    }
    return @($output | ForEach-Object { $_.ToString() })
}

function Restore-GitEnvironment {
    if ($script:credentialEnvironmentSet) {
        Restore-GitCredentialEnvironment
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

$escapedOwner = [uri]::EscapeDataString($TargetOwner)
$escapedTargetRepo = [uri]::EscapeDataString($TargetRepo)
try {
    $metadataLines = Invoke-Gh -Arguments @('api', "repos/$escapedOwner/$escapedTargetRepo")
}
catch {
    $errorMessage = $_.Exception.Message
    if ($errorMessage -match 'Not Found \(HTTP 404\)') {
        throw "Destination repository preflight returned HTTP 404. Verify that '$TargetOwner/$TargetRepo' exists and that GH_PAT can access it; GitHub can return 404 for private repositories the token cannot see. No Git refs were pushed. GitHub CLI details: $errorMessage"
    }
    throw
}
$destination = ($metadataLines -join "`n") | ConvertFrom-Json
if ($destination.owner.type -ne 'User' -or $destination.owner.login -ine $TargetOwner) {
    throw 'Destination must be a repository owned by the specified personal GitHub account.'
}
if (-not $destination.private) {
    throw 'Destination repository must be private; no Git refs were pushed.'
}

Add-GitCredentialHeader -Uri $sourceUrl -TokenVariable 'ADO_PAT' -UserName ''
Add-GitCredentialHeader -Uri $targetUrl -TokenVariable 'GH_PAT' -UserName 'x-access-token'

try {
    Set-GitCredentialEnvironment
    New-Item -ItemType Directory -Path $temporaryRoot -ErrorAction Stop | Out-Null
    $targetRefs = @(Invoke-Git -Arguments @('ls-remote', '--refs', $targetUrl.AbsoluteUri))
    if ($targetRefs.Count -gt 0) {
        throw 'Destination repository is not empty; refusing to alter any existing Git refs.'
    }

    Invoke-Git -Arguments @('clone', '--mirror', $sourceUrl.AbsoluteUri, $mirrorPath) | Out-Null
    $branches = @(Invoke-Git -WorkingDirectory $mirrorPath -Arguments @(
        'for-each-ref', '--format=%(refname)', 'refs/heads/'
    ))
    if ($branches.Count -eq 0) {
        throw 'No source branches were found; no destination refs were pushed.'
    }

    $defaultRef = @(& git -c safe.bareRepository=all -C $mirrorPath symbolic-ref --quiet HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $defaultRef.Count -ne 1 -or $defaultRef[0] -notmatch '^refs/heads/[^/].*$') {
        throw 'Could not resolve the source default branch; no destination refs were pushed.'
    }
    $defaultBranch = $defaultRef[0].Substring('refs/heads/'.Length)
    $branchSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($branch in $branches) { [void]$branchSet.Add($branch) }
    if (-not $branchSet.Contains($defaultRef[0])) {
        throw 'The source default branch does not exist in the mirror; no destination refs were pushed.'
    }

    $lfsPointers = @(Invoke-Git -WorkingDirectory $mirrorPath -Arguments @('lfs', 'ls-files', '--all', '--long') |
        Where-Object { $_.Trim() })
    if ($lfsPointers.Count -gt 0 -and $IncludeLfs -ne 'true') {
        throw "Source has $($lfsPointers.Count) Git LFS pointer entries. Re-run only after explicitly setting include_lfs=true."
    }

    Invoke-Git -WorkingDirectory $mirrorPath -Arguments @('remote', 'add', 'github', $targetUrl.AbsoluteUri) | Out-Null
    if ($lfsPointers.Count -gt 0) {
        Write-Host "Fetching and uploading $($lfsPointers.Count) Git LFS pointer entries before Git refs."
        Invoke-Git -WorkingDirectory $mirrorPath -Arguments @('lfs', 'fetch', '--all', 'origin') | Out-Null
        Invoke-Git -WorkingDirectory $mirrorPath -Arguments @('lfs', 'push', '--all', 'github') | Out-Null
    }

    Write-Host 'Destination is an existing private personal-account repository with no refs. Pushing branches and tags without force or mirror deletion.'
    Invoke-Git -WorkingDirectory $mirrorPath -Arguments @(
        'push', 'github', 'refs/heads/*:refs/heads/*'
    ) | Out-Null
    $tags = @(Invoke-Git -WorkingDirectory $mirrorPath -Arguments @(
        'for-each-ref', '--format=%(refname)', 'refs/tags/'
    ))
    if ($tags.Count -gt 0) {
        Invoke-Git -WorkingDirectory $mirrorPath -Arguments @(
            'push', 'github', 'refs/tags/*:refs/tags/*'
        ) | Out-Null
    }

    Invoke-Gh -Arguments @(
        'repo', 'edit', "$TargetOwner/$TargetRepo", '--default-branch', $defaultBranch
    ) | Out-Null
    $destinationDefault = Invoke-Gh -Arguments @(
        'api', "repos/$escapedOwner/$escapedTargetRepo", '--jq', '.default_branch'
    )
    if (($destinationDefault -join '').Trim() -ne $defaultBranch) {
        throw "Destination default branch verification failed after pushing refs. Expected '$defaultBranch'."
    }

    Write-Host 'Git-only trial refs were pushed. Comparing branch/tag refs, commit identities, LFS pointers, and default branch.'
    & "$PSScriptRoot/Compare-GitRepositories.ps1" -SourceUrl $sourceUrl -TargetUrl $targetUrl
}
finally {
    Restore-GitEnvironment
}
