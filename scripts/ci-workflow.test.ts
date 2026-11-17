import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const workflowPath = join(root, '.github', 'workflows', 'gei-migrate.yml');
const gitOnlyWorkflowPath = join(root, '.github', 'workflows', 'git-only-trial.yml');
const validatorPath = join(root, 'scripts', 'Validate-MigrationInputs.ps1');
const gitOnlyValidatorPath = join(root, 'scripts', 'Validate-GitOnlyInputs.ps1');
const comparerPath = join(root, 'scripts', 'Compare-GitRepositories.ps1');
const powershell = 'pwsh';
let fixtureRoot = '';
let sourceRepository = '';
let targetRepository = '';

function git(directory: string, ...args: string[]) {
  execFileSync('git', ['-c', 'safe.bareRepository=all', '-C', directory, ...args], {
    stdio: 'pipe',
    env: { ...process.env, GIT_LFS_SKIP_PUSH: '1' },
  });
}

function runPowerShell(script: string, args: string[], env = process.env) {
  return spawnSync(
    powershell,
    ['-NoLogo', '-NoProfile', '-File', script, ...args],
    { cwd: root, encoding: 'utf8', env },
  );
}

function makeGitFixtures() {
  fixtureRoot = mkdtempSync(join(tmpdir(), 'ado2gh-workflow-test-'));
  const workingRepository = join(fixtureRoot, 'working');
  sourceRepository = join(fixtureRoot, 'source.git');
  targetRepository = join(fixtureRoot, 'target.git');
  mkdirSync(workingRepository);
  execFileSync('git', ['-c', 'safe.bareRepository=all', 'init', '--bare', sourceRepository], { stdio: 'pipe' });
  execFileSync('git', ['init', '--initial-branch=main', workingRepository], { stdio: 'pipe' });

  git(workingRepository, 'config', 'user.name', 'Migration Test');
  git(workingRepository, 'config', 'user.email', 'migration-test@example.invalid');
  writeFileSync(join(workingRepository, 'first.txt'), 'first\n');
  git(workingRepository, 'add', 'first.txt');
  git(workingRepository, 'commit', '-m', 'first commit');
  git(workingRepository, 'branch', 'feature/test');
  git(workingRepository, 'tag', 'v1-lightweight');
  git(workingRepository, 'tag', '-a', 'v1-annotated', '-m', 'annotated test tag');
  writeFileSync(join(workingRepository, 'second.txt'), 'second\n');
  git(workingRepository, 'add', 'second.txt');
  git(workingRepository, 'commit', '-m', 'second commit');
  writeFileSync(join(workingRepository, '.gitattributes'), '*.bin filter=lfs diff=lfs merge=lfs -text\n');
  writeFileSync(
    join(workingRepository, 'sample.bin'),
    `version https://git-lfs.github.com/spec/v1\noid sha256:${'a'.repeat(64)}\nsize 12\n`,
  );
  git(workingRepository, 'add', '.gitattributes', 'sample.bin');
  git(workingRepository, 'commit', '-m', 'add a Git LFS pointer');
  git(workingRepository, 'remote', 'add', 'source', sourceRepository);
  git(workingRepository, 'push', 'source', '--all');
  git(workingRepository, 'push', 'source', '--tags');
  git(sourceRepository, 'symbolic-ref', 'HEAD', 'refs/heads/main');
  execFileSync('git', ['-c', 'safe.bareRepository=all', 'clone', '--mirror', sourceRepository, targetRepository], { stdio: 'pipe' });
  const mainCommit = execFileSync('git', ['-c', 'safe.bareRepository=all', '--git-dir', sourceRepository, 'rev-parse', 'refs/heads/main'], {
    encoding: 'utf8',
  }).trim();
  git(sourceRepository, 'update-ref', 'refs/pull/1/head', mainCommit);
}

describe('GEI workflow and Git validation', () => {
  beforeAll(() => {
    execFileSync(powershell, ['-NoLogo', '-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'], {
      stdio: 'pipe',
    });
    execFileSync('git', ['--version'], { stdio: 'pipe' });
    makeGitFixtures();
  });

  afterAll(() => {
    if (fixtureRoot) {
      rmSync(fixtureRoot, { recursive: true, force: true });
    }
  });

  it('is manually triggered, targets ubuntu-latest, and pins external actions', () => {
    const workflow = parse(readFileSync(workflowPath, 'utf8'));
    const gitOnlyWorkflow = parse(readFileSync(gitOnlyWorkflowPath, 'utf8'));
    expect(workflow.on.workflow_dispatch).toBeDefined();
    expect(gitOnlyWorkflow.on.workflow_dispatch).toBeDefined();
    expect(workflow.jobs.migrate['runs-on']).toBe('ubuntu-latest');
    expect(gitOnlyWorkflow.jobs.migrate['runs-on']).toBe('ubuntu-latest');
    expect(workflow.jobs.migrate.steps.some((step: { run?: string }) =>
      step.run?.includes('Install-Ado2Gh.ps1'))).toBe(true);
    expect(readFileSync(join(root, 'scripts', 'Install-Ado2Gh.ps1'), 'utf8'))
      .toContain('gh extension install github/gh-ado2gh --pin v1.35.0');
    expect(workflow.jobs.migrate.steps.some((step: { if?: string }) =>
      step.if?.includes('inputs.execute_trial'))).toBe(true);

    for (const path of [workflowPath, gitOnlyWorkflowPath]) {
      const actionReferences = [...readFileSync(path, 'utf8').matchAll(/^\s*uses:\s*(\S+)\s+#\s*v\S+\s*$/gm)];
      expect(actionReferences.length).toBeGreaterThan(0);
      for (const [, reference] of actionReferences) {
        expect(reference).toMatch(/^[^@]+@[0-9a-f]{40}$/i);
      }
    }
    expect(readFileSync(workflowPath, 'utf8')).toContain('secrets.ADO_PAT');
    expect(readFileSync(workflowPath, 'utf8')).toContain('secrets.GH_PAT');
  });

  it('keeps the personal-account workflow gated and avoids destructive mirror pushes', () => {
    const workflowText = readFileSync(gitOnlyWorkflowPath, 'utf8');
    const workflow = parse(workflowText);
    expect(workflow.on.workflow_dispatch).toBeDefined();
    expect(workflow.jobs.migrate['runs-on']).toBe('ubuntu-latest');
    expect(workflow.jobs.migrate.steps.some((step: { if?: string }) =>
      step.if?.includes('inputs.execute_trial'))).toBe(true);
    expect(workflowText).toContain('default: false');
    expect(workflowText).toContain('secrets.ADO_PAT');
    expect(workflowText).toContain('secrets.GH_PAT');

    const migrationScript = readFileSync(join(root, 'scripts', 'Invoke-GitOnlyTrial.ps1'), 'utf8');
    expect(migrationScript).toContain("'push', 'github', 'refs/heads/*:refs/heads/*'");
    expect(migrationScript).toContain("'push', 'github', 'refs/tags/*:refs/tags/*'");
    expect(migrationScript).not.toContain("'push', '--mirror'");
    expect(migrationScript).not.toContain("'push', '--force'");
  });

  it('rejects missing project configuration and missing trial approval', () => {
    const validConfig = runPowerShell(validatorPath, [
      '-SourceOrg', 'ado-example',
      '-SourceProject', 'project name',
      '-SourceRepo', 'source-repo',
      '-TargetOrg', 'github-example',
      '-TargetRepo', 'trial-repo',
      '-TargetApiUrl', 'https://api.example.ghe.com',
      '-ExecuteTrial', 'false',
    ]);
    expect(validConfig.status, `${validConfig.stdout}${validConfig.stderr}`).toBe(0);

    const missingProject = runPowerShell(validatorPath, [
      '-SourceOrg', 'ado-example',
      '-SourceProject', '',
      '-SourceRepo', 'source-repo',
      '-TargetOrg', 'github-example',
      '-TargetRepo', 'trial-repo',
    ]);
    expect(missingProject.status).not.toBe(0);
    expect(`${missingProject.stdout}${missingProject.stderr}`).toContain("Input 'source_project' is required.");

    const invalidTargetName = runPowerShell(validatorPath, [
      '-SourceOrg', 'ado-example',
      '-SourceProject', 'project',
      '-SourceRepo', 'source-repo',
      '-TargetOrg', 'github-example',
      '-TargetRepo', `r${'a'.repeat(100)}`,
    ]);
    expect(invalidTargetName.status).not.toBe(0);
    expect(`${invalidTargetName.stdout}${invalidTargetName.stderr}`).toContain("Input 'target_repo' exceeds");

    const invalidApiUrl = runPowerShell(validatorPath, [
      '-SourceOrg', 'ado-example',
      '-SourceProject', 'project',
      '-SourceRepo', 'source-repo',
      '-TargetOrg', 'github-example',
      '-TargetRepo', 'trial-repo',
      '-TargetApiUrl', 'https://api.example.ghe.com/path',
    ]);
    expect(invalidApiUrl.status).not.toBe(0);
    expect(`${invalidApiUrl.stdout}${invalidApiUrl.stderr}`).toContain("Input 'target_api_url'");

    const missingApproval = runPowerShell(validatorPath, [
      '-SourceOrg', 'ado-example',
      '-SourceProject', 'project',
      '-SourceRepo', 'source-repo',
      '-TargetOrg', 'github-example',
      '-TargetRepo', 'trial-repo',
      '-ExecuteTrial', 'true',
      '-TrialConfirmation', '',
    ]);
    expect(missingApproval.status).not.toBe(0);
    expect(`${missingApproval.stdout}${missingApproval.stderr}`).toContain('A real trial requires');
  });

  it('matches branches, lightweight/annotated tags, default branch, and history', () => {
    const result = runPowerShell(comparerPath, [
      '-SourceUrl', sourceRepository,
      '-TargetUrl', targetRepository,
    ]);
    expect(result.status, `${result.stdout}${result.stderr}`).toBe(0);
    expect(result.stdout).toContain('PASS: compared branch/tag refs');
    expect(result.stdout).toContain('Compared reachable commit identities: source=3, destination=3');
    expect(result.stdout).toContain('Compared LFS pointers: source=1, destination=1');
    expect(result.stdout).toContain("Default branch: source='refs/heads/main', destination='refs/heads/main'");
    expect(result.stdout).toContain('Excluded non-branch/tag refs: source=1, destination=0');
    expect(result.stdout).toContain('Source refs not compared: refs/pull/1/head');
    expect(result.stdout).toContain('LFS pointer listings include all local mirror refs');
  }, 30000);

  it('validates personal-account trial destinations and approval', () => {
    const valid = runPowerShell(gitOnlyValidatorPath, [
      '-SourceOrg', 'ado-example',
      '-SourceProject', 'project name',
      '-SourceRepo', 'source-repo',
      '-TargetOwner', 'personal-user',
      '-TargetRepo', 'source-repo-trial',
      '-IncludeLfs', 'false',
      '-ExecuteTrial', 'true',
      '-TrialConfirmation', 'I_APPROVE_GIT_TRIAL',
    ]);
    expect(valid.status, `${valid.stdout}${valid.stderr}`).toBe(0);

    const unsafeTarget = runPowerShell(gitOnlyValidatorPath, [
      '-SourceOrg', 'ado-example',
      '-SourceProject', 'project',
      '-SourceRepo', 'source-repo',
      '-TargetOwner', 'personal-user',
      '-TargetRepo', 'production-repo',
      '-ExecuteTrial', 'true',
      '-TrialConfirmation', 'I_APPROVE_GIT_TRIAL',
    ]);
    expect(unsafeTarget.status).not.toBe(0);
    expect(`${unsafeTarget.stdout}${unsafeTarget.stderr}`).toContain("must end in '-trial' or '-sandbox'");

    const missingApproval = runPowerShell(gitOnlyValidatorPath, [
      '-SourceOrg', 'ado-example',
      '-SourceProject', 'project',
      '-SourceRepo', 'source-repo',
      '-TargetOwner', 'personal-user',
      '-TargetRepo', 'source-repo-trial',
      '-ExecuteTrial', 'true',
      '-TrialConfirmation', '',
    ]);
    expect(missingApproval.status).not.toBe(0);
    expect(`${missingApproval.stdout}${missingApproval.stderr}`).toContain('I_APPROVE_GIT_TRIAL');
  });

  it('explains destination 404s before any Git write', () => {
    const fakeGhDirectory = join(fixtureRoot, 'fake-gh');
    mkdirSync(fakeGhDirectory);
    if (process.platform === 'win32') {
      writeFileSync(join(fakeGhDirectory, 'gh.cmd'), '@echo off\r\necho gh: Not Found (HTTP 404) 1>&2\r\necho {"message":"Not Found","status":"404"} 1>&2\r\nexit /b 1\r\n');
    } else {
      const fakeGh = join(fakeGhDirectory, 'gh');
      writeFileSync(fakeGh, '#!/bin/sh\necho "gh: Not Found (HTTP 404)" >&2\necho \'{"message":"Not Found","status":"404"}\' >&2\nexit 1\n');
      execFileSync('chmod', ['+x', fakeGh]);
    }

    const result = runPowerShell(
      join(root, 'scripts', 'Invoke-GitOnlyTrial.ps1'),
      [
        '-SourceOrg', 'ado-example',
        '-SourceProject', 'project',
        '-SourceRepo', 'source-repo',
        '-TargetOwner', 'personal-user',
        '-TargetRepo', 'source-repo-trial',
        '-IncludeLfs', 'false',
        '-TrialConfirmation', 'I_APPROVE_GIT_TRIAL',
      ],
      {
        ...process.env,
        PATH: `${fakeGhDirectory}${delimiter}${process.env.PATH ?? ''}`,
        ADO_PAT: 'test-only',
        GH_PAT: 'test-only',
        GH_TOKEN: 'test-only',
      },
    );
    const output = `${result.stdout}${result.stderr}`;
    const normalizedOutput = output.replace(/\r?\n/g, ' ').replace(/\s*\|\s*/g, ' ');
    expect(result.status).not.toBe(0);
    expect(normalizedOutput).toContain('Destination repository preflight returned HTTP 404.');
    expect(normalizedOutput).toContain('GitHub can return 404 for private repositories the token cannot see.');
    expect(normalizedOutput).toContain('No Git refs were');
  });

  it('reports annotated-tag, branch, and history discrepancies', () => {
    const targetWorktree = join(fixtureRoot, 'target-worktree');
    execFileSync('git', ['clone', targetRepository, targetWorktree], {
      stdio: 'pipe',
      env: { ...process.env, GIT_LFS_SKIP_SMUDGE: '1' },
    });
    git(targetWorktree, 'config', 'user.name', 'Migration Test');
    git(targetWorktree, 'config', 'user.email', 'migration-test@example.invalid');
    git(targetWorktree, 'tag', '--force', '--annotate', 'v1-annotated', '--message', 'changed annotation', 'v1-lightweight');
    git(targetWorktree, 'push', '--force', 'origin', 'refs/tags/v1-annotated');
    git(targetWorktree, 'switch', 'feature/test');
    writeFileSync(join(targetWorktree, 'changed.txt'), 'destination-only\n');
    git(targetWorktree, 'add', 'changed.txt');
    git(targetWorktree, 'commit', '-m', 'destination-only commit');
    git(targetWorktree, 'push', 'origin', 'feature/test');

    const result = runPowerShell(comparerPath, [
      '-SourceUrl', sourceRepository,
      '-TargetUrl', targetRepository,
    ]);
    expect(result.status).not.toBe(0);
    expect(`${result.stdout}${result.stderr}`).toContain('Ref object or peeled target differs: refs/heads/feature/test');
    expect(`${result.stdout}${result.stderr}`).toContain('Ref object or peeled target differs: refs/tags/v1-annotated');
    expect(`${result.stdout}${result.stderr}`).toContain('Reachable commit identity');
  }, 30000);
});
