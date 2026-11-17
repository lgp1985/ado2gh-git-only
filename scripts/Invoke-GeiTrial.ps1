param(
    [Parameter(Mandatory)]
    [string]$SourceOrg,
    [Parameter(Mandatory)]
    [string]$SourceProject,
    [Parameter(Mandatory)]
    [string]$SourceRepo,
    [Parameter(Mandatory)]
    [string]$TargetOrg,
    [Parameter(Mandatory)]
    [string]$TargetRepo,
    [string]$TargetApiUrl,
    [Parameter(Mandatory)]
    [string]$TrialConfirmation
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot/Validate-MigrationInputs.ps1" `
    -SourceOrg $SourceOrg `
    -SourceProject $SourceProject `
    -SourceRepo $SourceRepo `
    -TargetOrg $TargetOrg `
    -TargetRepo $TargetRepo `
    -TargetApiUrl $TargetApiUrl `
    -ExecuteTrial 'true' `
    -TrialConfirmation $TrialConfirmation

if ([string]::IsNullOrWhiteSpace($env:ADO_PAT)) {
    throw 'The ADO_PAT secret is required for a real migration.'
}
if ([string]::IsNullOrWhiteSpace($env:GH_PAT) -or [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    throw 'The GH_PAT secret is required for a real migration and GitHub CLI authentication.'
}

$apiBase = if ($TargetApiUrl) { $TargetApiUrl.TrimEnd('/') } else { 'https://api.github.com' }
$headers = @{
    Authorization = "Bearer $env:GH_PAT"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

function Get-ApiStatusCode {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        [Parameter(Mandatory)]
        [string]$Description
    )

    try {
        $response = Invoke-WebRequest -Method Get -Uri $Uri -Headers $headers -ErrorAction Stop
        return [int]$response.StatusCode
    }
    catch {
        $response = $_.Exception.Response
        if ($response -and $null -ne $response.StatusCode) {
            return [int]$response.StatusCode
        }

        throw "GitHub API preflight failed while checking $Description. $($_.Exception.Message)"
    }
}

$escapedOrg = [uri]::EscapeDataString($TargetOrg)
$escapedRepo = [uri]::EscapeDataString($TargetRepo)
$orgStatus = Get-ApiStatusCode -Uri "$apiBase/orgs/$escapedOrg" -Description 'the destination organization'
if ($orgStatus -ne 200) {
    throw "Destination organization could not be verified (HTTP $orgStatus); no migration was started."
}

$repoStatus = Get-ApiStatusCode -Uri "$apiBase/repos/$escapedOrg/$escapedRepo" -Description 'the destination repository'
if ($repoStatus -eq 200) {
    throw 'The destination repository already exists; refusing to run a duplicate or destructive migration.'
}
if ($repoStatus -ne 404) {
    throw "Destination repository absence could not be verified (HTTP $repoStatus); no migration was started."
}

Write-Host 'Destination organization verified and target repository not found. Starting the explicitly approved trial migration.'

$arguments = @(
    'ado2gh',
    'migrate-repo',
    '--ado-org', $SourceOrg,
    '--ado-team-project', $SourceProject,
    '--ado-repo', $SourceRepo,
    '--github-org', $TargetOrg,
    '--github-repo', $TargetRepo,
    '--target-repo-visibility', 'private'
)
if ($TargetApiUrl) {
    $arguments += @('--target-api-url', $TargetApiUrl)
}

& gh @arguments
if ($LASTEXITCODE -ne 0) {
    throw "gh ado2gh migrate-repo failed with exit code $LASTEXITCODE. Do not retry into the same target without inspecting migration status and logs."
}

Write-Host 'GEI trial command completed. This is not a Git or metadata validation result; perform the documented follow-up checks.'
