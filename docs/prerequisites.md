# Workflow prerequisites

The workflow uses `runs-on: ubuntu-latest` as requested. The GitHub-hosted runner image changes over time: GitHub's runner-images repository currently documents the Ubuntu 26.04 image and the staged `ubuntu-latest` migration from Ubuntu 24.04 during November 2026. Treat `ubuntu-latest` as a moving label; the workflow checks its actual tools at runtime and fails rather than silently substituting tooling.

## Runtime matrix

| Tool/capability | Requirement | Availability source/setup | Runtime verification |
|---|---|---|---|
| PowerShell (`pwsh`) | 7.2 or newer | Included in the documented GitHub-hosted Ubuntu images (7.6.x listed in the image readmes); no setup action is used | `pwsh --version`; `scripts/Check-RunnerTools.ps1` |
| Git | 2.30 or newer | Included in the official [Ubuntu 26.04 runner image](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md) (2.56.1 listed) | `git --version`; `scripts/Check-RunnerTools.ps1` |
| Git LFS | 3.0 or newer | Included in the official Ubuntu runner image (3.8.1 listed) | `git lfs version`; `scripts/Check-RunnerTools.ps1` |
| GitHub CLI (`gh`) | 2.4.0 or newer | Included in the official Ubuntu runner image (2.103.3 listed); GEI's install guide requires 2.4.0+ | `gh --version`; `scripts/Check-RunnerTools.ps1` |
| ADO2GH extension | Install `github/gh-ado2gh` for each fresh job; no extension version assumed | Separate explicit step: `gh extension install github/gh-ado2gh`; GEI [install guide](https://docs.github.com/en/migrations/ado/install-and-configure-github-enterprise-importer) | `gh ado2gh --help` and `gh ado2gh migrate-repo --help` |
| Bash | Runner-provided shell for the one-line extension installation | Ubuntu runner image lists Bash 5.x | GitHub Actions `shell: bash` executes the command; any failure stops the step |
| `actions/checkout` | v4 | External action pinned to a full commit SHA with its release comment; no other Actions are used | Pin enforced locally with `pinact run --check --verify-comment`; checkout must complete before scripts run |

No Python, .NET SDK, or setup action is used in the migration job. Tool setup and migration execution are separate steps. The test-only Node/Vitest packages are not required by the migration workflow.

## Official runner sources

- [GitHub Actions runner-images repository and latest-label policy](https://github.com/actions/runner-images)
- [Ubuntu 24.04 runner image software list](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md)
- [Ubuntu 26.04 runner image software list](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md)
- [GitHub Docs: hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners)
- [GEI install and GitHub CLI version requirements](https://docs.github.com/en/migrations/ado/install-and-configure-github-enterprise-importer)
