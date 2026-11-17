param(
    [switch]$RequireAdo2Gh
)

$ErrorActionPreference = 'Stop'

function Get-ToolVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Required command '$Name' is not available on PATH."
    }

    $output = @(& $Name @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Required command '$Name' failed its version check: $($output -join ' ')"
    }

    $match = [regex]::Match(($output -join "`n"), $Pattern)
    if (-not $match.Success) {
        throw "Could not read the version of required command '$Name'. Output: $($output -join ' ')"
    }

    return [version]$match.Groups[1].Value
}

function Assert-MinimumVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [version]$Actual,
        [Parameter(Mandatory)]
        [version]$Minimum
    )

    if ($Actual -lt $Minimum) {
        throw "$Name $Minimum or newer is required; found $Actual."
    }

    Write-Host "$Name $Actual"
}

Assert-MinimumVersion -Name 'PowerShell' -Actual $PSVersionTable.PSVersion -Minimum ([version]'7.2')

$gitVersion = Get-ToolVersion -Name 'git' -Arguments @('--version') -Pattern 'git version (\d+\.\d+\.\d+)'
Assert-MinimumVersion -Name 'Git' -Actual $gitVersion -Minimum ([version]'2.31')

$lfsVersion = Get-ToolVersion -Name 'git' -Arguments @('lfs', 'version') -Pattern 'git-lfs/(\d+\.\d+\.\d+)'
Assert-MinimumVersion -Name 'Git LFS' -Actual $lfsVersion -Minimum ([version]'3.0')

$ghVersion = Get-ToolVersion -Name 'gh' -Arguments @('--version') -Pattern 'gh version (\d+\.\d+\.\d+)'
Assert-MinimumVersion -Name 'GitHub CLI' -Actual $ghVersion -Minimum ([version]'2.4.0')

function Assert-Ado2GhCommand {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& gh @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $commandText = "gh $($Arguments -join ' ')"
        throw "Required ADO2GH command '$commandText' failed. Install github/gh-ado2gh before running migration steps. $($output -join ' ')"
    }
}

if ($RequireAdo2Gh) {
    Assert-Ado2GhCommand -Arguments @('ado2gh', '--help')
    Assert-Ado2GhCommand -Arguments @('ado2gh', 'migrate-repo', '--help')
    Write-Host 'ADO2GH extension and migrate-repo command are callable.'
}
