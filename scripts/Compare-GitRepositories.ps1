param(
    [Parameter(Mandatory)]
    [uri]$SourceUrl,
    [Parameter(Mandatory)]
    [uri]$TargetUrl
)

$ErrorActionPreference = 'Stop'
$comparisonErrors = [System.Collections.Generic.List[string]]::new()
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ado2gh-compare-$([guid]::NewGuid().ToString('N'))"
$sourceMirror = Join-Path $temporaryRoot 'source.git'
$targetMirror = Join-Path $temporaryRoot 'target.git'
$originalConfigCount = $env:GIT_CONFIG_COUNT
$originalConfigValues = @{}
$credentialEnvironmentSet = $false

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

function Set-TemporaryCredentialHeaders {
    param(
        [Parameter(Mandatory)]
        [uri]$Uri,
        [Parameter(Mandatory)]
        [string]$TokenVariable,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$UserName
    )

    $token = [Environment]::GetEnvironmentVariable($TokenVariable)
    if ([string]::IsNullOrWhiteSpace($token) -or $Uri.Scheme -ne 'https') {
        return
    }

    $credential = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${UserName}:$token"))
    $entry = @{
        Key = "http.https://$($Uri.Host)/.extraheader"
        Value = "AUTHORIZATION: Basic $credential"
    }
    $script:credentialEntries.Add($entry)
}

function Set-GitCredentialEnvironment {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Entries
    )

    $env:GIT_CONFIG_COUNT = [string]$Entries.Count
    for ($index = 0; $index -lt $Entries.Count; $index++) {
        foreach ($suffix in @('KEY', 'VALUE')) {
            $variableName = "GIT_CONFIG_${suffix}_$index"
            if (-not $script:originalConfigValues.ContainsKey($variableName)) {
                $script:originalConfigValues[$variableName] = [Environment]::GetEnvironmentVariable($variableName)
            }
        }
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$index", $Entries[$index].Key)
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$index", $Entries[$index].Value)
    }
}

function Restore-GitCredentialEnvironment {
    param([int]$Count)

    for ($index = 0; $index -lt $Count; $index++) {
        foreach ($suffix in @('KEY', 'VALUE')) {
            $variableName = "GIT_CONFIG_${suffix}_$index"
            [Environment]::SetEnvironmentVariable($variableName, $script:originalConfigValues[$variableName])
        }
    }
    $env:GIT_CONFIG_COUNT = $script:originalConfigCount
}

function Get-ComparableRefs {
    param([Parameter(Mandatory)][string]$RepositoryPath)

    $refs = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $excluded = [System.Collections.Generic.List[string]]::new()
    $lines = Invoke-Git -WorkingDirectory $RepositoryPath -Arguments @(
        'for-each-ref',
        '--format=%(refname)%09%(objectname)%09%(objecttype)'
    )

    foreach ($line in $lines) {
        $parts = $line -split "`t"
        if ($parts.Count -ne 3) {
            throw "Could not parse a ref record from '$RepositoryPath'."
        }
        $refName = $parts[0]
        if (-not ($refName.StartsWith('refs/heads/', [StringComparison]::Ordinal) -or
            $refName.StartsWith('refs/tags/', [StringComparison]::Ordinal))) {
            $excluded.Add($refName)
            continue
        }

        $peelSpec = "${refName}^{}"
        $peeledObject = Invoke-Git -WorkingDirectory $RepositoryPath -Arguments @('rev-parse', '--verify', $peelSpec)
        $refs[$refName] = [pscustomobject]@{
            ObjectId = $parts[1]
            ObjectType = $parts[2]
            PeeledObjectId = $peeledObject[0]
        }
    }

    return [pscustomobject]@{
        Refs = $refs
        Excluded = @($excluded | Sort-Object -Unique)
    }
}

function Get-DefaultBranch {
    param([Parameter(Mandatory)][string]$RepositoryPath)

    $output = @(& git -c safe.bareRepository=all -C $RepositoryPath symbolic-ref --quiet HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return ''
    }
    return ($output -join '').Trim()
}

function Get-ReachableCommitSet {
    param([Parameter(Mandatory)][string]$RepositoryPath)

    $commits = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($commit in (Invoke-Git -WorkingDirectory $RepositoryPath -Arguments @('rev-list', '--branches', '--tags'))) {
        [void]$commits.Add($commit.Trim())
    }
    return ,$commits
}

function Get-LfsPointerSet {
    param([Parameter(Mandatory)][string]$RepositoryPath)

    $pointers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $lines = Invoke-Git -WorkingDirectory $RepositoryPath -Arguments @('lfs', 'ls-files', '--all', '--long')
    foreach ($line in $lines) {
        if ($line -match '^([0-9a-fA-F]{64})\s+[*-]\s+(.*)$') {
            [void]$pointers.Add("$($Matches[1].ToLowerInvariant()) $($Matches[2])")
        }
        elseif ($line.Trim()) {
            [void]$pointers.Add($line.Trim())
        }
    }
    return ,$pointers
}

function Add-SetDifferences {
    param(
        [Parameter(Mandatory)][string]$Label,
        [AllowEmptyCollection()]
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$SourceSet,
        [AllowEmptyCollection()]
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$TargetSet
    )

    foreach ($item in $SourceSet) {
        if (-not $TargetSet.Contains($item)) {
            $comparisonErrors.Add("$Label is missing at destination: $item")
        }
    }
    foreach ($item in $TargetSet) {
        if (-not $SourceSet.Contains($item)) {
            $comparisonErrors.Add("$Label exists only at destination: $item")
        }
    }
}

$credentialEntries = [System.Collections.Generic.List[object]]::new()
Set-TemporaryCredentialHeaders -Uri $SourceUrl -TokenVariable 'ADO_PAT' -UserName ''
Set-TemporaryCredentialHeaders -Uri $TargetUrl -TokenVariable 'GH_PAT' -UserName 'x-access-token'
$credentialEntryCount = $credentialEntries.Count

try {
    if ($SourceUrl.Scheme -ne 'https' -and $SourceUrl.Scheme -ne 'file') {
        throw 'SourceUrl must use HTTPS or a local file URL.'
    }
    if ($TargetUrl.Scheme -ne 'https' -and $TargetUrl.Scheme -ne 'file') {
        throw 'TargetUrl must use HTTPS or a local file URL.'
    }
    if ($SourceUrl.Scheme -eq 'https' -and [string]::IsNullOrWhiteSpace($env:ADO_PAT)) {
        throw 'ADO_PAT must be securely provisioned in the environment to compare an HTTPS Azure DevOps source.'
    }
    if ($TargetUrl.Scheme -eq 'https' -and [string]::IsNullOrWhiteSpace($env:GH_PAT)) {
        throw 'GH_PAT must be securely provisioned in the environment to compare an HTTPS GitHub destination.'
    }

    Set-GitCredentialEnvironment -Entries $credentialEntries
    $credentialEnvironmentSet = $true
    New-Item -ItemType Directory -Path $temporaryRoot -ErrorAction Stop | Out-Null
    Invoke-Git -Arguments @('clone', '--mirror', $SourceUrl.AbsoluteUri, $sourceMirror) | Out-Null
    Invoke-Git -Arguments @('clone', '--mirror', $TargetUrl.AbsoluteUri, $targetMirror) | Out-Null

    $sourceData = Get-ComparableRefs -RepositoryPath $sourceMirror
    $targetData = Get-ComparableRefs -RepositoryPath $targetMirror

    $allRefNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($refName in $sourceData.Refs.Keys) { [void]$allRefNames.Add($refName) }
    foreach ($refName in $targetData.Refs.Keys) { [void]$allRefNames.Add($refName) }

    foreach ($refName in $allRefNames) {
        if (-not $sourceData.Refs.ContainsKey($refName)) {
            $comparisonErrors.Add("Ref exists only at destination: $refName")
            continue
        }
        if (-not $targetData.Refs.ContainsKey($refName)) {
            $comparisonErrors.Add("Ref missing at destination: $refName")
            continue
        }

        $sourceRef = $sourceData.Refs[$refName]
        $targetRef = $targetData.Refs[$refName]
        if ($sourceRef.ObjectId -ne $targetRef.ObjectId -or
            $sourceRef.ObjectType -ne $targetRef.ObjectType -or
            $sourceRef.PeeledObjectId -ne $targetRef.PeeledObjectId) {
            $comparisonErrors.Add("Ref object or peeled target differs: $refName")
        }
    }

    $sourceDefault = Get-DefaultBranch -RepositoryPath $sourceMirror
    $targetDefault = Get-DefaultBranch -RepositoryPath $targetMirror
    Write-Host "Default branch: source='$sourceDefault', destination='$targetDefault'"
    if (-not $sourceDefault -or -not $targetDefault) {
        $comparisonErrors.Add('Could not resolve the default branch for both repositories.')
    }
    elseif ($sourceDefault -ne $targetDefault) {
        $comparisonErrors.Add("Default branch differs: source='$sourceDefault', target='$targetDefault'")
    }

    $sourceCommits = Get-ReachableCommitSet -RepositoryPath $sourceMirror
    $targetCommits = Get-ReachableCommitSet -RepositoryPath $targetMirror
    Add-SetDifferences -Label 'Reachable commit identity' -SourceSet $sourceCommits -TargetSet $targetCommits

    $sourceLfs = Get-LfsPointerSet -RepositoryPath $sourceMirror
    $targetLfs = Get-LfsPointerSet -RepositoryPath $targetMirror
    Add-SetDifferences -Label 'Git LFS pointer' -SourceSet $sourceLfs -TargetSet $targetLfs

    Write-Host "Compared branches/tags: source=$($sourceData.Refs.Count), destination=$($targetData.Refs.Count)"
    Write-Host "Compared reachable commit identities: source=$($sourceCommits.Count), destination=$($targetCommits.Count)"
    Write-Host "Compared LFS pointers: source=$($sourceLfs.Count), destination=$($targetLfs.Count)"
    Write-Host "Excluded non-branch/tag refs: source=$($sourceData.Excluded.Count), destination=$($targetData.Excluded.Count)"
    if ($sourceData.Excluded.Count -gt 0) {
        Write-Host "Source refs not compared: $($sourceData.Excluded -join ', ')"
    }
    if ($targetData.Excluded.Count -gt 0) {
        Write-Host "Destination refs not compared: $($targetData.Excluded -join ', ')"
    }
    Write-Host 'LFS pointer listings include all local mirror refs (including excluded refs) and do not prove that payloads are available at either endpoint.'

    if ($comparisonErrors.Count -gt 0) {
        foreach ($comparisonError in $comparisonErrors) {
            Write-Host "DISCREPANCY: $comparisonError"
        }
        exit 1
    }

    Write-Host 'PASS: compared branch/tag refs, annotated-tag targets, reachable commit identities, and default branch match.'
}
finally {
    if ($credentialEnvironmentSet) {
        Restore-GitCredentialEnvironment -Count $credentialEntryCount
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
