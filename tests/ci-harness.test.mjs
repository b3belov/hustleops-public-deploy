import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { chmod, mkdtemp, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const projectRoot = path.resolve(import.meta.dirname, "..");
const verifyTagScript = path.join(projectRoot, "scripts", "ci", "verify-release-tag-from-main.sh");
const checkPinningScript = path.join(projectRoot, "scripts", "ci", "check-actions-pinning.sh");
const verifyApproverScript = path.join(projectRoot, "scripts", "ci", "verify-production-approver.sh");
const deployScript = path.join(projectRoot, "scripts", "deploy.sh");

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

async function runVerifyTag(repoRoot, tagName, extraEnv = {}) {
  return execFileAsync("bash", [verifyTagScript], {
    cwd: repoRoot,
    env: {
      ...process.env,
      RELEASE_TAG: "",
      GITHUB_REF_NAME: tagName,
      ...extraEnv,
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

async function runApproverCheck(expectedApprover, actor) {
  return execFileAsync("bash", [verifyApproverScript, expectedApprover], {
    cwd: projectRoot,
    env: {
      ...process.env,
      GITHUB_ACTOR: actor,
    },
  });
}

async function runApproverCheckWithEnv(expectedApprover, env = {}) {
  return execFileAsync("bash", [verifyApproverScript, expectedApprover], {
    cwd: projectRoot,
    env: {
      ...process.env,
      ...env,
    },
  });
}

async function createFakeDockerBin() {
  const binDir = await mkdtemp(path.join(os.tmpdir(), "hustleops-fake-docker-"));
  const dockerPath = path.join(binDir, "docker");

  await writeFile(dockerPath, "#!/bin/sh\nexit 0\n");
  await chmod(dockerPath, 0o755);

  return binDir;
}

async function createRecordingPreflightHelper() {
  const helperDir = await mkdtemp(path.join(os.tmpdir(), "hustleops-helper-"));
  const preflightPath = path.join(helperDir, "preflight.sh");

  await writeFile(
    preflightPath,
    "#!/bin/sh\nprintf '%s\\n' \"$@\"\n",
  );
  await chmod(preflightPath, 0o755);

  return helperDir;
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

test("verify-release-tag-from-main prefers RELEASE_TAG over GITHUB_REF_NAME", async () => {
  const repoRoot = await createOriginWithReleaseTags();
  const { stdout, stderr } = await runVerifyTag(repoRoot, "main", { RELEASE_TAG: "v1.2.3" });

  assert.match(stdout, /Release tag v1\.2\.3 is reachable from origin\/main\./);
  assert.equal(stderr, "");
});

test("verify-release-tag-from-main rejects main as a release tag", async () => {
  const repoRoot = await createOriginWithReleaseTags();

  await assert.rejects(
    runVerifyTag(repoRoot, "main"),
    (error) => {
      assert.equal(error.code, 2);
      assert.match(error.stderr, /Release tag name must not be main\./);
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

test("check-actions-pinning fails external action references without a ref", async () => {
  const repoRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-missing-action-ref-"));

  await writeWorkflow(repoRoot, "missing-ref.yml", `name: missing-ref
on: workflow_dispatch
jobs:
  missing-ref:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout
      - uses: docker://alpine:3.20
`);

  await assert.rejects(
    runPinningCheck(repoRoot),
    (error) => {
      assert.equal(error.code, 1);
      assert.match(error.stderr, /actions\/checkout \(missing @<sha>\)/);
      assert.doesNotMatch(error.stderr, /docker:\/\/alpine/);
      return true;
    },
  );
});

test("repository workflow action references are pinned", async () => {
  const { stdout, stderr } = await runPinningCheck(projectRoot);

  assert.match(stdout, /All external GitHub Actions are pinned to full commit SHAs\./);
  assert.equal(stderr, "");
});

test("verify-production-approver allows only the expected actor", async () => {
  const { stdout, stderr } = await runApproverCheck("release-admin", "release-admin");

  assert.match(stdout, /Verified production approver release-admin\./);
  assert.equal(stderr, "");

  await assert.rejects(
    runApproverCheck("release-admin", "other-user"),
    (error) => {
      assert.equal(error.code, 1);
      assert.match(error.stderr, /does not match expected approver release-admin\./);
      return true;
    },
  );
});

test("verify-production-approver fails closed when approver context is missing", async () => {
  await assert.rejects(
    runApproverCheck("", "release-admin"),
    (error) => {
      assert.equal(error.code, 2);
      assert.match(error.stderr, /Expected production approver argument is required\./);
      return true;
    },
  );

  await assert.rejects(
    runApproverCheckWithEnv("release-admin", { GITHUB_ACTOR: "" }),
    (error) => {
      assert.equal(error.code, 2);
      assert.match(error.stderr, /GITHUB_ACTOR is required\./);
      return true;
    },
  );
});

test("deploy start dry-run prepares Redis data directories before Compose starts services", async () => {
  const tmpRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-deploy-start-"));
  const envFile = path.join(tmpRoot, ".env");
  const fakeDockerBin = await createFakeDockerBin();

  await writeFile(envFile, "HUSTLEOPS_TEST_ENV=1\n");

  const { stdout, stderr } = await execFileAsync(
    "bash",
    [deployScript, "start", "--env-file", envFile, "--dry-run", "--yes"],
    {
      cwd: projectRoot,
      env: {
        ...process.env,
        PATH: `${fakeDockerBin}:${process.env.PATH}`,
      },
    },
  );

  assert.equal(stderr, "");
  assert.match(stdout, /DRY RUN: mkdir -p .*data\/redis/);
  assert.match(stdout, /DRY RUN: rm -f .*data\/redis\/\.gitkeep/);
  assert.match(stdout, /DRY RUN: mkdir -p .*data\/redis\/appendonlydir/);
  assert.ok(
    stdout.indexOf("data/redis/.gitkeep") < stdout.indexOf("docker compose"),
    "Redis data directory cleanup should run before docker compose starts services",
  );
});

test("deploy start dry-run starts ancillary proxy by default", async () => {
  const tmpRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-deploy-ancillary-"));
  const envFile = path.join(tmpRoot, ".env");
  const fakeDockerBin = await createFakeDockerBin();

  await writeFile(envFile, "HUSTLEOPS_TEST_ENV=1\n");

  const { stdout, stderr } = await execFileAsync(
    "bash",
    [deployScript, "start", "--env-file", envFile, "--dry-run", "--yes"],
    {
      cwd: projectRoot,
      env: {
        ...process.env,
        PATH: `${fakeDockerBin}:${process.env.PATH}`,
      },
    },
  );

  assert.equal(stderr, "");
  assert.match(stdout, /DRY RUN: mkdir -p .*data\/n8n\/redis/);
  assert.match(stdout, /docker compose [\s\S]*--profile ancillary-public[\s\S]* up [\s\S]* nginx-ancillary/);
  assert.doesNotMatch(stdout, /Skipping ancillary services/);
});

test("deploy start dry-run can skip ancillary proxy explicitly", async () => {
  const tmpRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-deploy-skip-ancillary-"));
  const envFile = path.join(tmpRoot, ".env");
  const fakeDockerBin = await createFakeDockerBin();

  await writeFile(envFile, "HUSTLEOPS_TEST_ENV=1\n");

  const { stdout, stderr } = await execFileAsync(
    "bash",
    [deployScript, "start", "--env-file", envFile, "--dry-run", "--yes", "--skip-ancillary"],
    {
      cwd: projectRoot,
      env: {
        ...process.env,
        PATH: `${fakeDockerBin}:${process.env.PATH}`,
      },
    },
  );

  assert.equal(stderr, "");
  assert.match(stdout, /Skipping ancillary services \(\-\-skip-ancillary\)/);
  assert.doesNotMatch(stdout, /--profile ancillary-public[\s\S]* nginx-ancillary/);
});

test("deploy start dry-run skip-n8n also skips ancillary proxy", async () => {
  const tmpRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-deploy-skip-n8n-"));
  const envFile = path.join(tmpRoot, ".env");
  const fakeDockerBin = await createFakeDockerBin();

  await writeFile(envFile, "HUSTLEOPS_TEST_ENV=1\n");

  const { stdout, stderr } = await execFileAsync(
    "bash",
    [deployScript, "start", "--env-file", envFile, "--dry-run", "--yes", "--skip-n8n"],
    {
      cwd: projectRoot,
      env: {
        ...process.env,
        PATH: `${fakeDockerBin}:${process.env.PATH}`,
      },
    },
  );

  assert.equal(stderr, "");
  assert.match(stdout, /Skipping n8n services \(\-\-skip-n8n\)/);
  assert.match(stdout, /Skipping ancillary services because n8n was skipped/);
  assert.doesNotMatch(stdout, /--profile ancillary-public[\s\S]* nginx-ancillary/);
});

test("ancillary ports default to external binds", async () => {
  const envExample = await readFile(path.join(projectRoot, ".env.example"), "utf8");
  const compose = await readFile(path.join(projectRoot, "docker-compose.prod.yml"), "utf8");

  assert.match(envExample, /^ANCILLARY_N8N_BIND=0\.0\.0\.0$/m);
  assert.match(envExample, /^ANCILLARY_DASHBOARDS_BIND=0\.0\.0\.0$/m);
  assert.match(compose, /\$\{ANCILLARY_N8N_BIND:-0\.0\.0\.0\}:5678:5678/);
  assert.match(compose, /\$\{ANCILLARY_DASHBOARDS_BIND:-0\.0\.0\.0\}:5601:5601/);
});

test("deploy debug forwards debug verbosity into preflight", async () => {
  const tmpRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-deploy-debug-"));
  const envFile = path.join(tmpRoot, ".env");
  const fakeDockerBin = await createFakeDockerBin();
  const helperDir = await createRecordingPreflightHelper();

  await writeFile(envFile, "HUSTLEOPS_TEST_ENV=1\n");

  const { stdout, stderr } = await execFileAsync(
    "bash",
    [
      deployScript,
      "preflight",
      "--env-file",
      envFile,
      "--skip-pull",
      "--skip-signature-verify",
      "--debug",
    ],
    {
      cwd: projectRoot,
      env: {
        ...process.env,
        HUSTLEOPS_DEPLOY_SCRIPT_DIR: helperDir,
        PATH: `${fakeDockerBin}:${process.env.PATH}`,
      },
    },
  );

  assert.match(stderr, /\+ /);
  assert.match(stdout, /--debug/);
});

test("preflight debug leaves docker pull progress visible", async () => {
  const preflight = await readFile(path.join(projectRoot, "scripts", "preflight.sh"), "utf8");

  assert.match(preflight, /PREFLIGHT_VERBOSITY=1/);
  assert.match(preflight, /--debug\)/);
  assert.match(preflight, /pull_image "\$HUSTLEOPS_BACKEND_IMAGE"/);
  assert.match(preflight, /docker pull --platform linux\/amd64 "\$image_ref"\n/);
  assert.match(preflight, /docker pull --platform linux\/amd64 "\$image_ref" >\/dev\/null/);
});

test("pr checks workflow exposes stable required check names", async () => {
  const workflow = await readFile(path.join(projectRoot, ".github", "workflows", "pr-checks.yml"), "utf8");

  assert.match(workflow, /\n  validate:\n\s+name: validate\n/);
  assert.match(workflow, /\n  action-security:\n\s+name: action-security\n/);
  assert.match(workflow, /bash scripts\/ci\/check-actions-pinning\.sh/);
});

test("release workflow has protected manual publish graph", async () => {
  const workflow = await readFile(path.join(projectRoot, ".github", "workflows", "release.yml"), "utf8");

  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /\n  verify-release-source:\n\s+name: verify-release-source\n/);
  assert.match(workflow, /\n  build-release:\n\s+name: build-release\n[\s\S]*?needs:\n\s+- verify-release-source\n/);
  assert.match(workflow, /\n  approve-production-release:\n\s+name: approve-production-release\n[\s\S]*?needs:\n\s+- build-release\n[\s\S]*?if: github\.event_name == 'workflow_dispatch'/);
  assert.match(workflow, /\n  publish-release:\n\s+name: publish-release\n[\s\S]*?needs:\n\s+- build-release\n\s+- approve-production-release\n[\s\S]*?if: github\.event_name == 'workflow_dispatch'[\s\S]*?permissions:\n\s+contents: write\n[\s\S]*?environment: production/);
  assert.match(workflow, /PRODUCTION_RELEASE_APPROVER/);
});

test("release workflow isolates tests from the release tag environment", async () => {
  const workflow = await readFile(path.join(projectRoot, ".github", "workflows", "release.yml"), "utf8");

  assert.match(workflow, /RELEASE_TAG='' node --test tests\/\*\.test\.mjs/);
});

test("only publish-release workflow job requests contents write", async () => {
  const workflowDir = path.join(projectRoot, ".github", "workflows");
  const workflowFiles = (await readdir(workflowDir)).filter((fileName) => /\.(ya?ml)$/.test(fileName));
  const writeGrants = [];

  for (const fileName of workflowFiles) {
    const workflow = await readFile(path.join(workflowDir, fileName), "utf8");
    const lines = workflow.split("\n");

    for (const [index, line] of lines.entries()) {
      if (!/^\s+contents:\s+write\s*$/.test(line)) {
        continue;
      }

      const jobLine = lines
        .slice(0, index)
        .reverse()
        .find((candidate) => /^  [a-zA-Z0-9_-]+:\s*$/.test(candidate));
      const job = jobLine?.trim().replace(/:$/, "") ?? "<workflow>";

      writeGrants.push({ fileName, job });
    }
  }

  assert.deepEqual(writeGrants, [{ fileName: "release.yml", job: "publish-release" }]);
});

test("workflow job display names are stable lowercase kebab-case", async () => {
  const workflowDir = path.join(projectRoot, ".github", "workflows");
  const workflowFiles = (await readdir(workflowDir)).filter((fileName) => /\.(ya?ml)$/.test(fileName));
  const jobNames = [];

  for (const fileName of workflowFiles) {
    const workflow = await readFile(path.join(workflowDir, fileName), "utf8");

    for (const line of workflow.split("\n")) {
      const match = line.match(/^ {4}name:\s+(.+)$/);
      if (match) {
        jobNames.push({ fileName, name: match[1].trim() });
      }
    }
  }

  for (const { fileName, name } of jobNames) {
    assert.match(name, /^[a-z0-9]+(?:-[a-z0-9]+)*$/, `${fileName} job name ${name} must be lowercase kebab-case`);
  }
});

test("create-release-tag workflow uses approver and GitHub App gates", async () => {
  const workflow = await readFile(path.join(projectRoot, ".github", "workflows", "create-release-tag.yml"), "utf8");

  assert.match(workflow, /permissions:\n  contents: read/);
  assert.match(workflow, /persist-credentials: false/);
  assert.match(workflow, /RELEASE_TAG_APPROVER/);
  assert.match(workflow, /actions\/create-github-app-token@[0-9a-f]{40}/);
  assert.match(workflow, /RELEASE_TAG_APP_ID/);
  assert.match(workflow, /RELEASE_TAG_APP_PRIVATE_KEY/);
  assert.match(workflow, /permission-contents: write/);
  assert.match(workflow, /git tag -a "\$VERSION" -m "Release \$VERSION"/);
  assert.match(workflow, /RELEASE_TAG_TOKEN: \$\{\{ steps\.release-tag-token\.outputs\.token \}\}/);
  assert.match(workflow, /x-access-token:\$\{RELEASE_TAG_TOKEN\}@github\.com/);
  assert.doesNotMatch(workflow, /RELEASE_TAG_DEPLOY_KEY/);
  assert.doesNotMatch(workflow, /permissions:\n  contents: write/);
});

test("required workflow files expose stable names and jobs", async () => {
  const workflowDir = path.join(projectRoot, ".github", "workflows");
  const prChecks = await readFile(path.join(workflowDir, "pr-checks.yml"), "utf8");
  const createReleaseTag = await readFile(path.join(workflowDir, "create-release-tag.yml"), "utf8");
  const release = await readFile(path.join(workflowDir, "release.yml"), "utf8");
  const rulesetAudit = await readFile(path.join(workflowDir, "ruleset-audit.yml"), "utf8");
  const deploy = await readFile(path.join(workflowDir, "deploy.yml"), "utf8");

  assert.match(prChecks, /^name: Pull Request Checks$/m);
  assert.match(prChecks, /\n  validate:\n\s+name: validate\n/);
  assert.match(prChecks, /\n  action-security:\n\s+name: action-security\n/);

  assert.match(createReleaseTag, /^name: Create Release Tag$/m);
  assert.match(createReleaseTag, /\n  create-release-tag:\n\s+name: create-release-tag\n/);

  assert.match(release, /^name: Release$/m);
  assert.match(release, /\n  verify-release-source:\n\s+name: verify-release-source\n/);
  assert.match(release, /\n  build-release:\n\s+name: build-release\n/);
  assert.match(release, /\n  approve-production-release:\n\s+name: approve-production-release\n/);
  assert.match(release, /\n  publish-release:\n\s+name: publish-release\n/);

  assert.match(rulesetAudit, /^name: Ruleset Audit$/m);
  assert.match(rulesetAudit, /\n  audit-rulesets:\n\s+name: audit-rulesets\n/);
  assert.match(rulesetAudit, /GH_TOKEN: \$\{\{ github\.token \}\}/);
  assert.match(rulesetAudit, /gh api "repos\/\$\{GITHUB_REPOSITORY\}\/rulesets" --jq '\.\[\] \| \{name, target, enforcement, bypass_actors, conditions\}'/);

  assert.match(deploy, /^name: Deploy App$/m);
  assert.match(deploy, /\n  build:\n\s+name: build\n/);
  assert.match(deploy, /\n  approve-production-deploy:\n\s+name: approve-production-deploy\n/);
  assert.match(deploy, /\n  deploy:\n\s+name: deploy\n/);
  assert.match(deploy, /environment: production/);
  assert.match(deploy, /PRODUCTION_DEPLOYMENT_APPROVER/);
});
