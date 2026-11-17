import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const workflowPath = join(root, '.github', 'workflows', 'gei-migrate.yml');
const validatorPath = join(root, 'scripts', 'Validate-MigrationInputs.ps1');
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

function runPowerShell(script: string, args: string[]) {
  return spawnSync(
    powershell,
    ['-NoLogo', '-NoProfile', '-File', script, ...args],
    { cwd: root, encoding: 'utf8' },
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
    expect(workflow.on.workflow_dispatch).toBeDefined();
    expect(workflow.jobs.migrate['runs-on']).toBe('ubuntu-latest');
    expect(workflow.jobs.migrate.steps.some((step: { run?: string }) =>
      step.run?.includes('Install-Ado2Gh.ps1'))).toBe(true);
    expect(readFileSync(join(root, 'scripts', 'Install-Ado2Gh.ps1'), 'utf8'))
      .toContain('gh extension install github/gh-ado2gh --pin v1.35.0');
    expect(workflow.jobs.migrate.steps.some((step: { if?: string }) =>
      step.if?.includes('inputs.execute_trial'))).toBe(true);

    const actionReferences = [...readFileSync(workflowPath, 'utf8').matchAll(/^\s*uses:\s*(\S+)\s+#\s*v\S+\s*$/gm)];
    expect(actionReferences.length).toBeGreaterThan(0);
    for (const [, reference] of actionReferences) {
      expect(reference).toMatch(/^[^@]+@[0-9a-f]{40}$/i);
    }
    expect(readFileSync(workflowPath, 'utf8')).toContain('secrets.ADO_PAT');
    expect(readFileSync(workflowPath, 'utf8')).toContain('secrets.GH_PAT');
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
