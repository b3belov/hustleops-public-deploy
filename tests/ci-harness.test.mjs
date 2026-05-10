import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const projectRoot = path.resolve(import.meta.dirname, "..");
const verifyTagScript = path.join(projectRoot, "scripts", "ci", "verify-release-tag-from-main.sh");
const checkPinningScript = path.join(projectRoot, "scripts", "ci", "check-actions-pinning.sh");

async function git(repoRoot, args) {
  return execFileAsync("git", ["-C", repoRoot, ...args]);
}

async function commitFile(repoRoot, fileName, content, message) {
  await writeFile(path.join(repoRoot, fileName), content);
  await git(repoRoot, ["add", fileName]);
  await git(repoRoot, ["commit", "-m", message]);
}

async function createOriginWithReleaseTags() {
  const tmpRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-release-tag-"));
  const originRoot = path.join(tmpRoot, "origin.git");
  const sourceRoot = path.join(tmpRoot, "source");
  const cloneRoot = path.join(tmpRoot, "clone");

  await execFileAsync("git", ["init", "--bare", originRoot]);
  await execFileAsync("git", ["clone", originRoot, sourceRoot]);
  await git(sourceRoot, ["config", "user.email", "ci@example.test"]);
  await git(sourceRoot, ["config", "user.name", "CI Test"]);
  await git(sourceRoot, ["checkout", "-b", "main"]);
  await commitFile(sourceRoot, "README.md", "# Release Fixture\n", "chore: initial main");
  await git(sourceRoot, ["tag", "-a", "v1.2.3", "-m", "Release v1.2.3"]);
  await git(sourceRoot, ["push", "origin", "main", "v1.2.3"]);

  await git(sourceRoot, ["checkout", "-b", "unchecked-feature"]);
  await commitFile(sourceRoot, "feature.txt", "unchecked\n", "feat: unchecked branch");
  await git(sourceRoot, ["tag", "-a", "v9.9.9", "-m", "Release v9.9.9"]);
  await git(sourceRoot, ["push", "origin", "unchecked-feature", "v9.9.9"]);

  await execFileAsync("git", ["clone", originRoot, cloneRoot]);

  return cloneRoot;
}

async function runVerifyTag(repoRoot, tagName) {
  return execFileAsync("bash", [verifyTagScript], {
    cwd: repoRoot,
    env: {
      ...process.env,
      GITHUB_REF_NAME: tagName,
    },
  });
}

async function writeWorkflow(repoRoot, fileName, workflow) {
  const workflowDir = path.join(repoRoot, ".github", "workflows");

  await mkdir(workflowDir, { recursive: true });
  await writeFile(path.join(workflowDir, fileName), workflow);
}

async function runPinningCheck(repoRoot) {
  return execFileAsync("bash", [checkPinningScript], { cwd: repoRoot });
}

test("verify-release-tag-from-main allows tags reachable from origin/main", async () => {
  const repoRoot = await createOriginWithReleaseTags();
  const { stdout, stderr } = await runVerifyTag(repoRoot, "v1.2.3");

  assert.match(stdout, /Release tag v1\.2\.3 is reachable from origin\/main\./);
  assert.equal(stderr, "");
});

test("verify-release-tag-from-main blocks tags outside origin/main history", async () => {
  const repoRoot = await createOriginWithReleaseTags();

  await assert.rejects(
    runVerifyTag(repoRoot, "v9.9.9"),
    (error) => {
      assert.equal(error.code, 1);
      assert.match(error.stderr, /Release tag v9\.9\.9 is not reachable from origin\/main\./);
      return true;
    },
  );
});

test("check-actions-pinning passes full commit SHA action references", async () => {
  const repoRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-pinned-actions-"));

  await writeWorkflow(repoRoot, "pinned.yml", `name: pinned
on: workflow_dispatch
jobs:
  pinned:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      - uses: ./.github/actions/local
`);

  const { stdout, stderr } = await runPinningCheck(repoRoot);

  assert.match(stdout, /All external GitHub Actions are pinned to full commit SHAs\./);
  assert.equal(stderr, "");
});

test("check-actions-pinning fails unpinned action references", async () => {
  const repoRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-unpinned-actions-"));

  await writeWorkflow(repoRoot, "unpinned.yml", `name: unpinned
on: workflow_dispatch
jobs:
  unpinned:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`);

  await assert.rejects(
    runPinningCheck(repoRoot),
    (error) => {
      assert.equal(error.code, 1);
      assert.match(error.stderr, /Unpinned GitHub Actions references found:/);
      assert.match(error.stderr, /unpinned\.yml:7: actions\/checkout@v4/);
      return true;
    },
  );
});

test("repository workflow action references are pinned", async () => {
  const { stdout, stderr } = await runPinningCheck(projectRoot);

  assert.match(stdout, /All external GitHub Actions are pinned to full commit SHAs\./);
  assert.equal(stderr, "");
});

test("create-release-tag workflow uses trusted tag token when configured", async () => {
  const workflow = await readFile(path.join(projectRoot, ".github", "workflows", "create-release-tag.yml"), "utf8");

  assert.match(workflow, /RELEASE_TAG_TOKEN/);
  assert.match(workflow, /token:\s+\$\{\{\s+secrets\.RELEASE_TAG_TOKEN\s+\|\|\s+github\.token\s+\}\}/);
});
