# Azure DevOps to GitHub migration showcase

This repository prepares two repeatable, manually approved migration paths: GEI to a GitHub Enterprise Cloud organization and a Git-only transfer to a GitHub personal account. Following the operator's destination choice, the Git-only path is the selected route. Neither workflow is run automatically.

## Current status and blockers

- No migration, remote write, workflow run, or push has been performed.
- The operator identifies the ADO organization as `lgp1985` and project as `iTextSharp`; the supplied link redirected to Microsoft sign-in without credentials. The URL omits the project segment required in the standard clone URL, so the exact repository and canonical URL still need verification. See the [migration plan](docs/migration-plan.md).
- GEI targets GitHub Enterprise Cloud organizations, not a personal account's repository. The GEI workflow remains available only if an eligible Enterprise Cloud organization is selected later.
- The selected personal-account workflow requires a new, empty, private repository created by an operator. This project will not create it or push to it without a separate explicit approval.
- The project has not been pushed, so GitHub-hosted Actions and end-to-end migration compatibility remain unverified.

## Project contents

- [Staged plan, feasibility, access, limits, and operator procedure](docs/migration-plan.md)
- [Runner/tool prerequisite matrix](docs/prerequisites.md)
- [Manually dispatched Git-only personal-account trial workflow](.github/workflows/git-only-trial.yml)
- [Manually dispatched GEI organization trial workflow](.github/workflows/gei-migrate.yml)
- [Scripts](scripts/)
- [Local checks and Git comparison procedure](docs/migration-plan.md#git-validation)

Both workflows default to validation-only. The selected Git-only workflow also requires `execute_trial: true`, a repository ending in `-trial` or `-sandbox`, and the exact `trial_confirmation: I_APPROVE_GIT_TRIAL`. It refuses an existing non-empty repository and pushes branches/tags without force or mirror deletion. Validation-only runs create no remote resources; neither workflow creates or deletes a repository.

## Local test

Run the focused tests with the repository-pinned pnpm version:

```powershell
npx --yes pnpm@12.19.0 exec vitest run scripts/ci-workflow.test.ts
```

The local tests exercise both workflow structures, invalid configuration, and Git ref/history comparison with local fixtures. They do not authenticate to Azure DevOps or GitHub and do not validate a hosted runner.

## Authoritative references

- [GitHub: Migrating from Azure DevOps](https://docs.github.com/en/migrations/ado)
- [GitHub: Understand migrations from Azure DevOps](https://docs.github.com/en/migrations/ado/understand-migrations-from-azure-devops-to-github)
- [GitHub: GEI overview](https://docs.github.com/en/migrations/using-github-enterprise-importer/understanding-github-enterprise-importer/about-github-enterprise-importer)
- [Microsoft Learn: Clone an existing Azure Repos Git repository](https://learn.microsoft.com/en-us/azure/devops/repos/git/clone?view=azure-devops)
- [GitHub Actions runner images](https://github.com/actions/runner-images)
