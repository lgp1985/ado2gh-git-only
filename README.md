# Azure DevOps to GitHub migration showcase

This repository prepares a repeatable, manually approved GitHub Enterprise Importer (GEI) path for moving an Azure DevOps Git repository to a **new repository in a GitHub Enterprise Cloud organization**. It does not run migrations automatically.

## Current status and blockers

- No migration, remote write, workflow run, or push has been performed.
- The supplied source link, `https://dev.azure.com/lgp1985/_git/iTextSharp`, redirected to Microsoft sign-in when checked without credentials. It does not identify a team project in its path. The likely organization/repository labels are not independently verified, and the canonical clone URL remains unknown. See the [migration plan](docs/migration-plan.md).
- GEI targets GitHub Enterprise Cloud organizations, not a personal account's repository. An eligible destination organization has not been supplied. The workflow below is organization-targeted; it does not silently substitute another destination.
- The project has not been pushed, so GitHub-hosted Actions and end-to-end migration compatibility remain unverified.

## Project contents

- [Staged plan, feasibility, access, limits, and operator procedure](docs/migration-plan.md)
- [Runner/tool prerequisite matrix](docs/prerequisites.md)
- [Manually dispatched GEI trial workflow](.github/workflows/gei-migrate.yml)
- [Scripts](scripts/)
- [Local checks and Git comparison procedure](docs/migration-plan.md#git-validation)

The workflow defaults to validation-only. A real trial requires both `execute_trial: true` and the exact `trial_confirmation: I_APPROVE_TRIAL`; it checks the destination organization and refuses to migrate into an existing repository. Validation-only runs create no remote resources. An approved GEI run creates the new destination; the workflow never deletes or overwrites an existing repository. Production cutover is deliberately not exposed by this trial workflow.

## Local test

After installing the project test dependencies, run:

```powershell
pnpm exec vitest run scripts/ci-workflow.test.ts
```

The local tests exercise workflow structure, invalid configuration, and Git ref/history comparison with local fixtures. They do not authenticate to Azure DevOps or GitHub and do not validate a hosted runner.

## Authoritative references

- [GitHub: Migrating from Azure DevOps](https://docs.github.com/en/migrations/ado)
- [GitHub: Understand migrations from Azure DevOps](https://docs.github.com/en/migrations/ado/understand-migrations-from-azure-devops-to-github)
- [GitHub: GEI overview](https://docs.github.com/en/migrations/using-github-enterprise-importer/understanding-github-enterprise-importer/about-github-enterprise-importer)
- [Microsoft Learn: Clone an existing Azure Repos Git repository](https://learn.microsoft.com/en-us/azure/devops/repos/git/clone?view=azure-devops)
- [GitHub Actions runner images](https://github.com/actions/runner-images)
