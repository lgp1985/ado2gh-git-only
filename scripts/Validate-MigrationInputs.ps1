param(
    [string]$SourceOrg,
    [string]$SourceProject,
    [string]$SourceRepo,
    [string]$TargetOrg,
    [string]$TargetRepo,
    [string]$TargetApiUrl,
    [string]$ExecuteTrial = 'false',
    [string]$TrialConfirmation = ''
)

$ErrorActionPreference = 'Stop'

function Assert-NonEmptySingleLine {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Input '$Name' is required."
    }
    if ($Value -ne $Value.Trim() -or $Value -match '[\r\n]') {
        throw "Input '$Name' must not have leading/trailing whitespace or line breaks."
    }
}

Assert-NonEmptySingleLine -Name 'source_org' -Value $SourceOrg
Assert-NonEmptySingleLine -Name 'source_project' -Value $SourceProject
Assert-NonEmptySingleLine -Name 'source_repo' -Value $SourceRepo
Assert-NonEmptySingleLine -Name 'target_org' -Value $TargetOrg
Assert-NonEmptySingleLine -Name 'target_repo' -Value $TargetRepo

if ($SourceOrg -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Input 'source_org' contains unsupported characters."
}
if ($SourceProject.Length -gt 256) {
    throw "Input 'source_project' exceeds the supported input length."
}
if ($SourceRepo.Length -gt 256) {
    throw "Input 'source_repo' exceeds the supported input length."
}
if ($TargetOrg -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') {
    throw "Input 'target_org' must be a GitHub organization name."
}
if ($TargetOrg.Length -gt 39) {
    throw "Input 'target_org' exceeds the GitHub organization-name limit."
}
if ($TargetRepo -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Input 'target_repo' contains unsupported GitHub repository-name characters."
}
if ($TargetRepo.Length -gt 100) {
    throw "Input 'target_repo' exceeds the GitHub repository-name limit."
}

if ($TargetApiUrl) {
    $apiUri = $null
    if (-not [uri]::TryCreate($TargetApiUrl, [UriKind]::Absolute, [ref]$apiUri) -or
        $apiUri.Scheme -ne 'https' -or
        $apiUri.Query -or
        $apiUri.Fragment -or
        $apiUri.UserInfo -or
        $apiUri.AbsolutePath.TrimEnd('/')) {
        throw "Input 'target_api_url' must be an HTTPS API base URL without a path, query, or credentials."
    }
}

if ($ExecuteTrial -notin @('true', 'false')) {
    throw "Input 'execute_trial' must be true or false."
}
if ($ExecuteTrial -eq 'true' -and $TrialConfirmation -cne 'I_APPROVE_TRIAL') {
    throw "A real trial requires execute_trial=true and trial_confirmation=I_APPROVE_TRIAL."
}

Write-Host 'Migration inputs are valid.'
