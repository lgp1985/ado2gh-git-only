# Workflow prerequisites

The workflow uses `runs-on: ubuntu-latest` as requested. At the time checked (November 17, 2026), the runner-images table maps `ubuntu-latest` to Ubuntu 24.04, while a staged migration to Ubuntu 26.04 is announced for November 2026. Treat `ubuntu-latest` as a moving label; the workflow checks actual tool versions at runtime and fails rather than silently substituting tooling.

## Runtime matrix

| Tool/capability | Requirement | Availability source/setup | Runtime verification |
|---|---|---|---|
| PowerShell (`pwsh`) | 7.2 or newer | Included in the documented Ubuntu 24.04/26.04 GitHub-hosted images (7.6.x listed); no setup action is used | `pwsh --version`; `scripts/Check-RunnerTools.ps1` |
| Git | 2.31 or newer | Included in the official [Ubuntu 24.04 runner image](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md) and 26.04 image (2.56.1 listed) | `git --version`; `scripts/Check-RunnerTools.ps1` |
| Git LFS | 3.0 or newer | Included in the official Ubuntu 24.04/26.04 runner images (3.8.1 listed) | `git lfs version`; `scripts/Check-RunnerTools.ps1` |
| GitHub CLI (`gh`) | 2.4.0 or newer | Included in the official Ubuntu 24.04/26.04 runner images (2.103.3 listed); GEI's install guide requires 2.4.0+ | `gh --version`; `scripts/Check-RunnerTools.ps1` |
| ADO2GH extension | `v1.35.0` | Separate explicit step installs the pinned [ADO2GH release](https://github.com/github/gh-ado2gh/releases/tag/v1.35.0) with documented `gh extension install --pin` behavior | `gh ado2gh --help` and `gh ado2gh migrate-repo --help` |
| Checkout action runtime | Node.js 20 | `actions/checkout@v4.2.2` declares `using: node20`; its SHA-pinned action runtime is provided by GitHub Actions | Checkout step must complete; see [`action.yml`](https://github.com/actions/checkout/blob/v4.2.2/action.yml) |
| `actions/checkout` | v4.2.2 | External action pinned to a full commit SHA with its release comment; the action metadata declares Node.js 20 | Pin enforced locally with `pinact run --check --verify-comment`; checkout must complete before scripts run |

No Bash step, Python, .NET SDK, or setup action is used in the migration job. Tool setup and migration execution are separate steps. The test-only Node/Vitest packages are not required by the migration workflow.

## Official runner sources

- [GitHub Actions runner-images repository and latest-label policy](https://github.com/actions/runner-images)
- [Ubuntu 24.04 runner image software list](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md)
- [Ubuntu 26.04 runner image software list](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md)
- [GitHub Docs: hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners)
- [GEI install and GitHub CLI version requirements](https://docs.github.com/en/migrations/ado/install-and-configure-github-enterprise-importer)
- [GitHub CLI extension install and `--pin`](https://cli.github.com/manual/gh_extension_install)
