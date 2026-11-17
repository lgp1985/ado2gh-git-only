param(
    [string]$SourceOrg,
    [string]$SourceProject,
    [string]$SourceRepo,
    [string]$TargetOwner,
    [string]$TargetRepo,
    [string]$IncludeLfs = 'false',
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
Assert-NonEmptySingleLine -Name 'target_owner' -Value $TargetOwner
Assert-NonEmptySingleLine -Name 'target_repo' -Value $TargetRepo

if ($SourceOrg -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Input 'source_org' contains unsupported characters."
}
if ($SourceProject.Length -gt 256 -or $SourceRepo.Length -gt 256) {
    throw 'The Azure DevOps project or repository name exceeds the supported input length.'
}
if ($TargetOwner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$' -or $TargetOwner.Length -gt 39) {
    throw "Input 'target_owner' must be a valid GitHub personal-account login."
}
if ($TargetRepo -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $TargetRepo.Length -gt 100) {
    throw "Input 'target_repo' must be a valid GitHub repository name."
}
if ($IncludeLfs -notin @('true', 'false')) {
    throw "Input 'include_lfs' must be true or false."
}
if ($ExecuteTrial -notin @('true', 'false')) {
    throw "Input 'execute_trial' must be true or false."
}
if ($ExecuteTrial -eq 'true') {
    if ($TargetRepo -notmatch '(?i)(-trial|-sandbox)$') {
        throw "A trial destination repository name must end in '-trial' or '-sandbox'."
    }
    if ($TrialConfirmation -cne 'I_APPROVE_GIT_TRIAL') {
        throw "A real Git-only trial requires trial_confirmation=I_APPROVE_GIT_TRIAL."
    }
}

Write-Host 'Git-only migration inputs are valid.'
