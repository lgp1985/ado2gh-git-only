# Build an Azure DevOps-to-GitHub migration showcase

## Objective
Create a reusable, documented migration project that showcases and validates moving Git code from Azure DevOps to GitHub. Prefer GitHub Enterprise Importer (GEI) with the `gh ado2gh` extension, and provide a manually triggered GitHub Actions workflow for future use with other repositories.

- Source: https://dev.azure.com/lgp1985/_git/iTextSharp. Verify the Azure DevOps organization, project, repository, and actual clone URL; do not assume the supplied URL identifies the project unambiguously.
- Preferred destination: a repository under https://github.com/lgp1985/ (a personal account).
- Credentials for accessing source and destination will only be provided during workflow execution.
- Project directory: `D:\Users\Public\Public Source\ado2gh`. Initialize it as a Git repository if needed. Commit each meaningful completed stage locally; do not push.

## Research and feasibility
Start with the GitHub documentation on [migrating from Azure DevOps](https://docs.github.com/en/migrations/ado/migrate-your-repositories-from-azure-devops-to-github), [understanding the migration](https://docs.github.com/en/migrations/ado/understand-migrations-from-azure-devops-to-github), and [GEI](https://docs.github.com/en/migrations/using-github-enterprise-importer/understanding-github-enterprise-importer/about-github-enterprise-importer). Follow relevant prerequisite, authentication, limitations, trial, and follow-up documentation. Consult EngHub and other available authoritative sources where useful; distinguish verified guidance from unavailable or unconfirmed information, and cite sources.

Verify current GEI destination eligibility, licensing, permissions, source and destination requirements, and whether a personal account is supported. If GEI cannot target the preferred account, explain the constraint and compare an eligible organization with suitable Git-only alternatives, including their tradeoffs. Do not silently substitute a different migration method or target; request a decision before implementing a materially different approach. Continue with any independent GEI preparation that is feasible.

## GitHub Actions runner compatibility and tooling

When implementing or updating this project's GitHub Actions workflows:

- Target `runs-on: ubuntu-latest`. Never infer runner capabilities from tools installed on the developer's local machine.
- Inventory the commands, runtimes, shells, CLI extensions, and versions required by each job. Verify their availability against the current official GitHub-hosted runner image documentation and the documentation for any setup actions used. Cite the relevant sources and note that `ubuntu-latest` can change.
- Prefer trusted, maintained setup actions when they provide the required tooling. Otherwise, add an explicit installation step. Keep tooling setup separate from migration or validation execution. Do not assume a CLI extension is installed merely because its parent CLI is available.
- Before dependent steps run, check that required tools are callable and meet version requirements. Fail clearly when prerequisites are missing or incompatible; do not silently skip work or substitute another migration method.

### Implementation choices

- Do not use Python or introduce a Python dependency.
- For simple orchestration, prefer PowerShell steps with explicit `shell: pwsh`. Verify PowerShell availability on the selected runner image.
- For complex logic that warrants C#, use a file-based application invoked with `dotnet run app.cs`. Provision a compatible SDK explicitly with `actions/setup-dotnet` and verify that the chosen SDK supports file-based applications. Select a documented, supported action version and SDK version rather than assuming either is available.
- Keep multi-line PowerShell and Bash logic in tracked `.ps1` and `.sh` files, respectively, and invoke those files from workflow YAML. Keep C# application logic in tracked `.cs` files. Use Linux-compatible paths, casing, and executable invocation, and propagate native-command failures to a nonzero step exit.
- Prefer the simplest existing implementation that meets the requirements; do not rewrite working PowerShell in C# without a concrete need.

### Deliverables and verification

- Provide workflow and script changes plus a concise prerequisite matrix: required tool/capability, required version, verified runner-image source or setup action/installation step, and runtime verification command.
- Run focused local checks where possible, but distinguish them from validation on a GitHub-hosted Ubuntu runner. Do not claim hosted compatibility or end-to-end migration success without an actual verified run.
- Preserve the migration project's approval gates: do not push, trigger workflows, perform a migration, or make other remote writes without explicit approval. If hosted execution is unavailable, state what remains unverified and the exact next validation step.


## Deliverables
1. A high-level, staged migration plan and operator documentation covering prerequisites, access, source inventory, trial migration, validation, production cutover, follow-up, and recovery. Explain limitations, including lack of delta migrations, Git LFS handling, and relevant size limits. Identify source-freeze and remediation requirements; do not claim metadata parity is in scope.
2. A configurable, manually triggered GitHub Actions workflow and any necessary scripts for the supported GEI path. Parameterize source organization, project and repository, destination organization and repository, and any other required settings. Use documented CLI behavior; validate inputs, fail visibly, avoid hard-coded credentials, and document least-privilege secrets and setup. Do not assume a CLI dry-run flag exists. Guard against accidental duplicate or destructive migrations, and require explicit approval for actual trial execution.
   Design the workflow for composition and reuse. Keep unrelated operations, such as installing tooling and executing a migration, in separate steps or jobs as appropriate. Prefer verified, trusted existing GitHub Actions when they meet the requirement; otherwise use the CLI. Keep multi-line PowerShell and Bash scripts in tracked `.ps1` and `.sh` files, respectively, and invoke those files from the workflow YAML.

3. A practical Git-focused validation procedure or automation for source and destination: compare applicable branch and tag refs, commit identities/history, and default branch; address annotated tags, excluded or non-transferable refs, and Git LFS explicitly. Report discrepancies and limitations rather than claiming success for unverified data. Assess whether `gh-repo-stats` and other inventory tools add value, but avoid adding unnecessary dependencies.
4. Local checks and focused tests covering the workflow or scripts, including configuration errors and the Git comparison logic where automated. Explain how to run them and report results.

## Execution and safety
- This is preparation plus a possible trial, not authorization to migrate now. Ask for explicit approval immediately before any real trial or other remote write. Do not create, delete, overwrite, publish, or push remote resources without approval; never modify the Azure DevOps source as part of preparation.
- GitHub-hosted Actions cannot run until the project is pushed; validate locally as far as practical and clearly distinguish local checks from an actual hosted run or end-to-end migration.
- Do not request tokens in chat or commit credentials, private inventory, or sensitive migration logs. Document secure secret provisioning and artifact handling. Preserve unrelated existing files and changes.
- If access, destination eligibility, or missing information blocks a step, state the blocker and exact next action rather than inventing results. Request the minimum necessary input.

## Completion
Provide links to the project plan, workflow, and relevant documentation; list the local commits and checks performed, any unsupported assumptions or blockers, and the next approval or setup steps. Do not claim a migration or hosted workflow succeeded unless it actually ran and was verified.