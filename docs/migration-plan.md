# Migration plan and operator guide

## Scope and verified feasibility

This showcase is for Git source migration using GitHub Enterprise Importer (GEI) and its `gh ado2gh` extension. GEI is documented for Azure DevOps **Cloud** to GitHub **Enterprise Cloud** (GitHub.com or GHE.com); it does not support Azure DevOps Server as a source. The destination must be an organization, not a personal account's repository. A personal account can own or administer an organization, but that does not make the personal repository itself a supported GEI destination.

The requested destination, `https://github.com/lgp1985/`, is a personal account URL. It is not eligible as a GEI destination. The GitHub migration documentation identifies GitHub Enterprise Cloud as the destination, but the reviewed migration pages do not establish whether GEI has a separate migration charge or this account's subscription/trial entitlement. An Enterprise owner must verify the intended organization's plan and migration entitlement before a trial. Do not treat GEI as a free personal-account migration feature.

The supplied Azure DevOps URL is `https://dev.azure.com/lgp1985/_git/iTextSharp`. An unauthenticated request redirected to Microsoft sign-in; the link contains no project component. It does not prove that `lgp1985` is the organization, that `iTextSharp` is the repository's exact name, or which project contains it. Microsoft documents the standard clone URL shape as:

```text
https://dev.azure.com/{organization}/{project}/_git/{repository}
```

Before any migration, an Azure DevOps project/repository owner must provide or verify the organization, project, repository, and actual clone URL in the authenticated Azure DevOps UI/API. The reusable workflow consequently requires all three source values and does not infer a project.

### Destination decision required

Choose one before any actual trial:

1. **Stay on GEI:** provide the name of an existing GitHub Enterprise Cloud organization approved for a sandbox trial, and confirm its Enterprise owner has verified the applicable licensing/entitlement. This is the path implemented here.
2. **Target the personal account:** explicitly approve a separate Git-only migration design. GitHub's browser-based Importer can import Git source/history where source authentication and product support permit, but Microsoft documents that it does not migrate pull requests, work-item links, or branch policies. A carefully staged `git clone --mirror` / `git push --mirror` gives more control over the Git refs sent to a newly created personal repository, but it also does not provide GEI metadata migration. Mirror pushes can delete remote refs that are absent locally, so they must target a verified, empty, dedicated repository and require separate review and explicit remote-write approval. Neither alternative is implemented here.

No destination has been substituted and no remote repository has been created.

## Supported scope and limits

GEI for Azure DevOps can migrate Git source and commit history, pull requests, pull-request user history, work-item links and attachments on pull requests, and some repository branch policies. It does not migrate all Azure DevOps assets: pipelines, work items, artifacts, test plans, releases, dashboards, and repository permissions are not in scope. Repository permission models do not map automatically, and metadata parity is not claimed or tested by this Git-focused showcase.

Other important constraints documented by GitHub:

- **No delta migrations.** Changes made while or after a migration runs are not brought over by a later delta pass. Freeze writes for production cutover and manually account for any changes made after the migration snapshot.
- **Git LFS payloads are not migrated by GEI.** Git LFS pointer files may be present in Git history, but the LFS objects must be transferred and verified separately after migration.
- **Per-commit size:** no Git commit may exceed 2 GiB.
- **Per-push size:** a push over 2 GiB fails.
- **Ref names:** a Git ref name may not exceed 255 bytes.
- **File sizes:** the normal post-migration limit is 100 MiB per file; the migration allowance is 400 MiB. GEI itself also limits any single file to 400 MiB.
- **Repository size:** the documented 40 GiB GEI limit is marked public preview and applies to source code. GitHub recommends `git-sizer` to examine repository object sizes.
- GitHub code search can take hours to re-index after migration. Organization rulesets may block migration unless the documented “Repository migrations” bypass is configured.

Consult the current GitHub documentation before scheduling: limits and product behavior can change.

## Staged execution plan

### Stage 1 — Resolve source and destination

1. Have the ADO project owner confirm Azure DevOps Cloud (not Server), organization, project, repository, default branch, canonical HTTPS clone URL, visibility, and read access.
2. Inventory source refs, LFS usage, largest files/commits, repository size, and relevant consumers (builds, deploys, package feeds, links, service connections). The ADO2GH `inventory-report` can help inventory repository and pull-request counts; its CSV output is private operational data.
3. Have a GitHub Enterprise owner confirm an eligible, existing sandbox organization, plan/entitlement, organization policies, allowed PAT policies, rulesets, IP allowlists, and the operator's owner or migrator role.
4. Decide a new, unique, private trial repository name. This workflow deliberately rejects an existing destination repository; it never reuses or overwrites one.

### Stage 2 — Prepare access and controls

GEI's documented ADO2GH flow uses classic personal access tokens (PATs), not fine-grained GitHub PATs:

- **Azure DevOps `ADO_PAT`:** `Code (Read)`, `Identity (Read)`, and `Work Items (Read)`. These are the documented read scopes; do not grant write scopes for this workflow.
- **GitHub `GH_PAT`:** for an organization owner, the documented migration scopes are `repo`, `workflow`, and `admin:org`; for a migrator, `repo`, `workflow`, and `read:org`. Use the applicable role, allow access to the destination organization, and do not broaden scopes beyond the documented task. The classic-PAT requirement is incompatible with an organization policy that blocks classic PAT access.

Create these only in the approved workflow's Actions secrets (`ADO_PAT`, `GH_PAT`), not in source files, workflow inputs, command arguments, chat, or logs. Keep them out of job summaries and artifacts. Configure the `gei-trial` GitHub Environment with required reviewers before enabling trial execution. The workflow also requires an explicit dispatch input confirmation; it is not run as part of this preparation.

The optional `inventory-report` is not part of the migration job. GitHub's access guide recommends a full-access ADO PAT to use that command; do not widen the workflow's read-only ADO PAT for inventory. If that optional report is needed, obtain separate approval for its access, generate it in an access-controlled environment, and keep the resulting CSV private.

Review network restrictions and temporarily handle identity-provider restrictions as directed by GitHub's [access guide](https://docs.github.com/en/migrations/ado/manage-access). Where applicable, permit the documented GitHub migration traffic and add `Repository migrations` to relevant ruleset bypass lists for the duration of migration.

### Stage 3 — Trial migration

1. Push this prepared project to an approved GitHub repository only after a separate approval. This task has not pushed it; GitHub-hosted Actions cannot run until then.
2. In **Actions → GEI trial migration → Run workflow**, enter verified source organization/project/repository and a destination **organization** plus a new private trial repository name.
3. Leave `execute_trial` false for configuration/tool checks. For an approved trial only, set it true and enter the exact `I_APPROVE_TRIAL` confirmation. The workflow checks the destination organization's existence and the target repository's absence using read-only API requests immediately before invoking GEI. A permission failure or unexpected API status fails closed.
4. The destination check relies on the token being authorized to see the organization's repositories; GitHub may return 404 for an inaccessible private repository. Ensure the operator token has the documented organization access. Never infer absence from an unauthenticated check.
5. Review the migration result/log through the documented GEI process. Do not automatically retry, delete a partially created repository, or use the same target name for another attempt. Preserve any migration logs only in access-controlled storage; do not publish them as artifacts or commit them.
6. Ask repository stakeholders to validate Git refs/history and the GEI-supported metadata they need. The automated comparator in this project checks Git data only.

### Stage 4 — Production cutover

Production execution is intentionally not exposed in the workflow. After a successful trial and explicit approval for production:

1. Schedule and announce a source write freeze. Stop pushes, merges, branch/tag creation, and automation that writes to the source repository.
2. Capture a final inventory and baseline (default branch, branch/tag refs, HEADs, LFS objects, size checks). Keep a recoverable source-side backup.
3. Migrate to a separately approved new production repository. The Importer has no delta migration; any changes after the frozen baseline must be manually reconciled.
4. Run Git comparison and application-specific smoke checks. Recreate permissions, policies, webhooks, CI/CD, secrets, integrations, and repository settings as separate follow-up work.
5. Redirect developers and automation only after owners sign off. Keep the Azure DevOps source read-only and available for the agreed retention period.

### Stage 5 — Follow-up and recovery

- Transfer and verify Git LFS objects separately; the comparison script reports pointer differences/counts, not payload availability.
- Recreate branch protection/rulesets, access, CI/CD, webhooks, service connections, build/release workflows, and links. Review GitHub migration logs and resolve supported-data warnings.
- If trial validation fails, leave the source unchanged, keep the target isolated, inspect logs privately, fix the cause, and use a **new** approved trial target. Do not repeatedly invoke the migration into the same or a partially populated target.
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

Run `pnpm exec vitest run scripts/ci-workflow.test.ts` after installing the package dependencies. The tests parse the workflow, check the approval and runner settings, verify invalid configuration fails, and compare branch/tag/history results on local Git fixtures.

The tests do not require tokens, access either remote, run `gh ado2gh migrate-repo`, trigger Actions, or make remote writes. No hosted-runner validation, source access validation, GEI trial, or end-to-end migration has occurred. After the project is pushed with approval and a destination decision, the next hosted validation is a manual workflow run with `execute_trial: false`; a real trial still needs a separate explicit approval and the confirmation input.

## Source references

- [GitHub: Azure DevOps migration guide](https://docs.github.com/en/migrations/ado/migrate-your-repositories-from-azure-devops-to-github)
- [GitHub: Understand ADO migrations and limits](https://docs.github.com/en/migrations/ado/understand-migrations-from-azure-devops-to-github)
- [GitHub: Prepare for migration and inventory](https://docs.github.com/en/migrations/ado/prepare-for-your-migration-from-azure-devops-to-github)
- [GitHub: Manage migration access](https://docs.github.com/en/migrations/ado/manage-access)
- [GitHub: Install and configure GEI](https://docs.github.com/en/migrations/ado/install-and-configure-github-enterprise-importer)
- [GitHub: Upstream ADO2GH `migrate-repo` options](https://github.com/github/gh-gei/blob/main/src/ado2gh/Commands/MigrateRepo/MigrateRepoCommand.cs)
- [GitHub: GEI overview and supported paths](https://docs.github.com/en/migrations/using-github-enterprise-importer/understanding-github-enterprise-importer/about-github-enterprise-importer)
- [Microsoft Learn: Azure Repos clone URL and cloning](https://learn.microsoft.com/en-us/azure/devops/repos/git/clone?view=azure-devops)
- [Microsoft Learn: Migration options and ADO2GH command example](https://learn.microsoft.com/en-us/azure/devops/organizations/projects/migrate-public-project?view=azure-devops)
- [GitHub CLI: Installing an extension at a pinned release](https://cli.github.com/manual/gh_extension_install)
- [GitHub: ADO2GH release used by the workflow](https://github.com/github/gh-ado2gh/releases/tag/v1.35.0)
