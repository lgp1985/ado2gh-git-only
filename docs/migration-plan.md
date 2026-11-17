# Migration plan and operator guide

## Scope and verified feasibility

This showcase prepares two Git-only migration paths: a selected personal-account transfer and an optional GitHub Enterprise Importer (GEI) path using its `gh ado2gh` extension. GEI is documented for Azure DevOps **Cloud** to GitHub **Enterprise Cloud** (GitHub.com or GHE.com); it does not support Azure DevOps Server as a source. The destination must be an organization, not a personal account's repository. A personal account can own or administer an organization, but that does not make the personal repository itself a supported GEI destination.

The requested destination, `https://github.com/lgp1985/`, is a personal account URL. It is not eligible as a GEI destination. The GitHub migration documentation identifies GitHub Enterprise Cloud as the destination, but the reviewed migration pages do not establish whether GEI has a separate migration charge or this account's subscription/trial entitlement. An Enterprise owner must verify the intended organization's plan and migration entitlement before a trial. Do not treat GEI as a free personal-account migration feature.

The supplied Azure DevOps URL is `https://dev.azure.com/lgp1985/_git/iTextSharp`. An unauthenticated request redirected to Microsoft sign-in; the link contains no project component. The operator identifies the organization as `lgp1985` and the project as `iTextSharp`, but the actual repository name and canonical clone URL remain unverified. Microsoft documents the standard clone URL shape as:

```text
https://dev.azure.com/{organization}/{project}/_git/{repository}
```

Before any migration, an Azure DevOps project/repository owner must verify the organization, project, repository, and actual clone URL in the authenticated Azure DevOps UI/API. The workflows require all three source values and do not infer a clone URL from the incomplete link.

### Destination route selected

The operator selected **Git-only migration to the personal account**. The personal account is not a GEI destination; the selected path is implemented separately in [`git-only-trial.yml`](../.github/workflows/git-only-trial.yml). It creates no repository and performs no remote writes during preparation.

The GEI workflow remains a reusable alternative for an existing GitHub Enterprise Cloud organization. GitHub's reviewed documentation does not establish a separate GEI migration charge or this account's subscription/trial entitlement; an Enterprise owner must verify those before choosing that path.

### Git-only path and tradeoffs

The selected workflow uses Git, Git LFS when explicitly enabled, and GitHub CLI to migrate only Git refs to an **already-created, empty, private personal-account repository**. It pushes heads and tags with ordinary non-force refspecs, not `git push --mirror`; this avoids deleting destination refs. The script sets the destination default branch to match the source, then runs the Git comparator. It does not migrate pull requests, work items, branch policies, or any other Azure DevOps metadata. The browser-based GitHub Importer is a simpler alternative where source authentication/product support permit it; Microsoft documents that it imports Git source/history but not pull requests, work-item links, or branch policies. Neither route provides GEI's supported metadata migration.

The target repository must end in `-trial` or `-sandbox` for this workflow, be private, and contain no refs. An operator must create it manually before a trial; repository creation is a separate remote write and is not authorized by the route selection. The workflow checks the owner type, privacy, and emptiness immediately before transfer. It never uses force-push or deletes refs. If a push partially succeeds, stop and inspect the target rather than retrying or cleaning it automatically.

## Supported scope and limits

GEI for Azure DevOps can migrate Git source and commit history, pull requests, pull-request user history, work-item links and attachments on pull requests, and some repository branch policies. The selected Git-only workflow migrates only branches, tags, their reachable Git history, and optionally LFS objects. It does not migrate pull requests, work items, policies, or any other Azure DevOps metadata. Pipelines, work items, artifacts, test plans, releases, dashboards, and repository permissions are not in scope; repository permission models do not map automatically, and metadata parity is not claimed or tested.

Other important constraints documented by GitHub:

- **No delta migrations for GEI.** Changes made while or after a migration runs are not brought over by a later delta pass. The Git-only workflow also has no incremental mode; repeat a full transfer to a fresh empty target and manually reconcile any changes after the snapshot.
- **Git LFS:** GEI does not migrate LFS payloads. The Git-only workflow can fetch and upload LFS objects only when the operator explicitly enables `include_lfs`; separately verify payload availability after transfer.
- **Per-commit size:** no Git commit may exceed 2 GiB.
- **Per-push size:** a push over 2 GiB fails.
- **Ref names:** a Git ref name may not exceed 255 bytes.
- **File sizes:** the normal GitHub limit is 100 MiB per file; GEI documents a 400 MiB migration allowance and also limits any single file to 400 MiB.
- **Repository size:** the documented 40 GiB GEI limit is marked public preview and applies to source code. GitHub recommends `git-sizer` to examine repository object sizes.
- GitHub code search can take hours to re-index after migration. Organization rulesets may block migration unless the documented “Repository migrations” bypass is configured.

Consult the current GitHub documentation before scheduling: limits and product behavior can change.

## Staged execution plan

### Stage 1 — Resolve source and destination

1. Have the ADO project owner confirm Azure DevOps Cloud (not Server), organization, project, repository, default branch, canonical HTTPS clone URL, visibility, and read access.
2. Inventory source refs, LFS usage, largest files/commits, repository size, and relevant consumers (builds, deploys, package feeds, links, service connections). The ADO2GH `inventory-report` can help inventory repository and pull-request counts; its CSV output is private operational data.
3. For a GEI migration only, have a GitHub Enterprise owner confirm an eligible, existing sandbox organization, plan/entitlement, organization policies, allowed PAT policies, rulesets, IP allowlists, and the operator's owner or migrator role.
4. Decide a unique private trial repository name ending in `-trial` or `-sandbox`. Create an empty personal-account repository only after separate approval; this project never creates it.

### Stage 2 — Prepare access and controls

For the selected Git-only workflow:

- **Azure DevOps `ADO_PAT`:** `Code (Read)` for Git clone and, if enabled, LFS fetch.
- **GitHub `GH_PAT`:** prefer a fine-grained token restricted to the single private trial repository, with `Contents: Read and write` and `Administration: Read and write` (the latter is used to set/verify the default branch; repository metadata read is implicit). The token owner must have access to the target account/repository.

For the separate GEI workflow, ADO2GH requires classic PATs, not fine-grained GitHub PATs:

- **Azure DevOps `ADO_PAT`:** `Code (Read)`, `Identity (Read)`, and `Work Items (Read)`. These are the documented read scopes; do not grant write scopes for this workflow.
- **GitHub `GH_PAT`:** for an organization owner, the documented migration scopes are `repo`, `workflow`, and `admin:org`; for a migrator, `repo`, `workflow`, and `read:org`. Use the applicable role, allow access to the destination organization, and do not broaden scopes beyond the documented task. The classic-PAT requirement is incompatible with an organization policy that blocks classic PAT access.

Create the applicable tokens only in the approved workflow's Actions secrets (`ADO_PAT`, `GH_PAT`), not in source files, workflow inputs, command arguments, chat, or logs. Keep them out of job summaries and artifacts. Configure `git-only-trial` and/or `gei-trial` GitHub Environments with required reviewers before enabling execution. Each workflow also requires an exact dispatch confirmation; neither is run as part of this preparation.

The optional `inventory-report` is not part of the migration job. GitHub's access guide recommends a full-access ADO PAT to use that command; do not widen the workflow's read-only ADO PAT for inventory. If that optional report is needed, obtain separate approval for its access, generate it in an access-controlled environment, and keep the resulting CSV private.

Review network restrictions and temporarily handle identity-provider restrictions as directed by GitHub's [access guide](https://docs.github.com/en/migrations/ado/manage-access). Where applicable, permit the documented GitHub migration traffic and add `Repository migrations` to relevant ruleset bypass lists for the duration of migration.

### Stage 3 — Trial migration

1. Push this prepared project to an approved GitHub repository only after separate approval. This task has not pushed it; GitHub-hosted Actions cannot run until then.
3. Confirm the full Azure DevOps organization/project/repository and clone URL. Create a new, empty, private personal-account trial repository ending in `-trial` or `-sandbox` only after separate approval.
4. In **Actions → Git-only personal-account trial → Run workflow**, leave `execute_trial` false for input/tool checks. For an approved trial only, set it true and enter the exact `I_APPROVE_GIT_TRIAL` confirmation. Set `include_lfs` true only if LFS objects are required and the source/destination PATs can transfer them. If pointers are present but this input is false, execution stops before remote Git writes.
5. If the initial GitHub repository API preflight returns **404**, confirm the repository exists under the specified personal-account owner and that `GH_PAT` is authorized to access that repository. GitHub can report 404 for a private repository the token cannot see. This preflight occurs before any Git refs are pushed; fix the target or token access before another run.
6. The script validates the repository owner is a personal account, the destination is private and empty, and source default branch exists. It clones the source mirror locally, optionally fetches/pushes LFS objects, pushes branches and tags without force/deletion, sets the default branch, and compares Git refs/history. The target must remain otherwise unwritten during the run.
7. Review the action output privately. It can contain private branch/tag names and LFS paths. No logs or inventories are uploaded as artifacts. If any Git refs were pushed and a later step fails, do not rerun or delete anything until the partial target is inspected.
8. Ask repository stakeholders to validate Git refs/history and application behavior. No PR/ADO metadata parity is claimed.

If a later decision switches back to GEI, use **Actions → GEI trial migration** with an approved Enterprise Cloud organization, classic PATs, and the separate `I_APPROVE_TRIAL` confirmation.

### Stage 4 — Production cutover

Production execution is intentionally not exposed as a separate workflow mode. After a successful trial and explicit approval for production:

1. Schedule and announce a source write freeze. Stop pushes, merges, branch/tag creation, and automation that writes to the source repository.
2. Capture a final inventory and baseline (default branch, branch/tag refs, HEADs, LFS objects, size checks). Keep a recoverable source-side backup.
3. Migrate to a separately approved new production repository. For GEI, there is no delta migration; for Git-only transfers, use a fresh empty target and repeat the complete transfer from the frozen source. Reconcile any changes made after the baseline manually.
4. Run Git comparison and application-specific smoke checks. Recreate permissions, policies, webhooks, CI/CD, secrets, integrations, and repository settings as separate follow-up work.
5. Redirect developers and automation only after owners sign off. Keep the Azure DevOps source read-only and available for the agreed retention period.

### Stage 5 — Follow-up and recovery

- Transfer and verify Git LFS objects separately; the comparison script reports pointer differences/counts, not payload availability.
- Recreate branch protection/rulesets, access, CI/CD, webhooks, service connections, build/release workflows, and links. Review GitHub migration logs and resolve supported-data warnings.
- If trial validation fails, leave the source unchanged, keep the target isolated, inspect logs privately, and fix the cause. For GEI, use a new approved trial target; for a Git-only partial push, inspect and compare the current target before deciding on a new target. Do not automatically delete, overwrite, or retry into a partially populated target.
- For production recovery, keep the source frozen/read-only until acceptance. If cutover is rejected, redirect consumers to the source using the pre-agreed rollback procedure; reconcile any post-snapshot commits manually. GEI does not offer a reverse or delta migration. Deleting a target or changing source state requires separate explicit approval.

## Git validation

The tracked [`Compare-GitRepositories.ps1`](../scripts/Compare-GitRepositories.ps1) script clones both remotes as mirrors into a temporary directory, compares:

- branch and tag ref names and exact object IDs;
- annotated tag object IDs and peeled target IDs;
- all commits reachable from branches/tags (commit identity/history);
- the default branch (`HEAD`);
- Git LFS pointer listings; and
- refs outside `refs/heads/*` and `refs/tags/*`, which it reports as excluded from the comparison rather than treating as transferable.

The LFS pointer inventory covers all refs in each mirror, including refs excluded from branch/tag comparison; interpret LFS differences alongside the excluded-ref report. The script does not claim that LFS payloads are present, that excluded refs can be migrated, or that PR/ADO metadata matches. It does not save a report file. Keep its terminal output private for private repositories.

With approved credentials already provisioned as environment variables (never paste PAT values into a command or source file), run:

```powershell
$sourceUrl = 'https://dev.azure.com/<organization>/<project>/_git/<repository>'
$targetUrl = 'https://github.com/<organization>/<repository>.git'
pwsh -NoLogo -NoProfile -File .\scripts\Compare-GitRepositories.ps1 `
  -SourceUrl $sourceUrl -TargetUrl $targetUrl
```

The script uses `ADO_PAT` for Azure DevOps and `GH_PAT` for GitHub when set. It removes its temporary mirror clones on exit. Resolve every reported branch/tag/history/default-branch discrepancy before declaring Git validation complete.

### Inventory-tool assessment

- **`gh ado2gh inventory-report`:** useful before migration for repository and pull-request counts/timing. It is broader than this single-repository Git comparison and produces CSV inventory that should remain private.
- **`git-sizer`:** useful for identifying size risks against GEI limits; use it on an authorized local mirror if the repository may be large.
- **`git lfs`:** required to enumerate LFS pointers and separately transfer objects. GEI does not migrate the object payloads.
- **`gh-repo-stats`:** not needed here. GitHub repository statistics do not establish ADO source completeness or branch/tag/history parity, so adding it would add dependency without meeting a required validation.

## Local checks and boundaries

Run `pnpm exec vitest run scripts/ci-workflow.test.ts` after installing the package dependencies. The tests parse both workflows, check approval and runner settings, verify invalid configuration fails, ensure the Git-only script avoids destructive mirror pushes, and compare branch/tag/history results on local Git fixtures.

The tests do not require tokens, access either remote, run `gh ado2gh migrate-repo`, trigger Actions, or make remote writes. No hosted-runner validation, source access validation, Git-only trial, GEI trial, or end-to-end migration has occurred. After the project is pushed with approval and the source details are verified, the next hosted validation is a manual workflow run with `execute_trial: false`; a real trial still needs a separate explicit approval and confirmation input.

## Source references

- [GitHub: Azure DevOps migration guide](https://docs.github.com/en/migrations/ado/migrate-your-repositories-from-azure-devops-to-github)
- [GitHub: Understand ADO migrations and limits](https://docs.github.com/en/migrations/ado/understand-migrations-from-azure-devops-to-github)
- [GitHub: Prepare for migration and inventory](https://docs.github.com/en/migrations/ado/prepare-for-your-migration-from-azure-devops-to-github)
- [GitHub: Manage migration access](https://docs.github.com/en/migrations/ado/manage-access)
- [GitHub: Install and configure GEI](https://docs.github.com/en/migrations/ado/install-and-configure-github-enterprise-importer)
- [GitHub: Import a repository from Azure DevOps](https://docs.github.com/en/migrations/importing-source-code/using-github-importer/importing-a-repository-from-azure-devops)
- [GitHub CLI: `gh repo edit`](https://cli.github.com/manual/gh_repo_edit)
- [GitHub REST: Update a repository](https://docs.github.com/en/rest/repos/repos#update-a-repository)
- [GitHub: Fine-grained personal access token permissions for repositories](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens#repository-permissions-for-update-a-repository)
- [GitHub: Upstream ADO2GH `migrate-repo` options](https://github.com/github/gh-gei/blob/main/src/ado2gh/Commands/MigrateRepo/MigrateRepoCommand.cs)
- [GitHub: GEI overview and supported paths](https://docs.github.com/en/migrations/using-github-enterprise-importer/understanding-github-enterprise-importer/about-github-enterprise-importer)
- [Microsoft Learn: Azure Repos clone URL and cloning](https://learn.microsoft.com/en-us/azure/devops/repos/git/clone?view=azure-devops)
- [Microsoft Learn: Migration options and ADO2GH command example](https://learn.microsoft.com/en-us/azure/devops/organizations/projects/migrate-public-project?view=azure-devops)
- [GitHub CLI: Installing an extension at a pinned release](https://cli.github.com/manual/gh_extension_install)
- [GitHub: ADO2GH release used by the workflow](https://github.com/github/gh-ado2gh/releases/tag/v1.35.0)
