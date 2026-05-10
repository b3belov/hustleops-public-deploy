import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const projectRoot = path.resolve(import.meta.dirname, "..");

async function git(repoRoot, args) {
  return execFileAsync("git", ["-C", repoRoot, ...args]);
}

async function writeJson(filePath, value) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function manifestFor(tag, version = tag.slice(1)) {
  return {
    schemaVersion: 1,
    release: {
      tag,
      version,
      commitSha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      releasedAt: "2026-05-10T13:27:45Z",
      summary: `Release ${tag}.`,
      url: `https://github.com/HustleOps/HustleOps/releases/tag/${tag}`,
    },
    deploy: {
      trigger: `release-${tag}-aaaaaaaaaaaa`,
    },
  };
}

async function writeReleaseFixture(repoRoot, tag) {
  const manifest = manifestFor(tag);

  await writeJson(path.join(repoRoot, "release-manifest.json"), manifest);
  await writeJson(path.join(repoRoot, "release-verification.json"), {
    schemaVersion: 1,
    release: manifest.release,
  });
  await mkdir(path.join(repoRoot, "deployment"), { recursive: true });
  await writeFile(path.join(repoRoot, "deployment", "release-trigger.txt"), `${manifest.deploy.trigger}\n`);
  await writeJson(path.join(repoRoot, "releases", `${tag}.json`), {
    schemaVersion: 1,
    release: manifest.release,
  });
}

async function commitAll(repoRoot, message) {
  await git(repoRoot, ["add", "."]);
  await git(repoRoot, ["commit", "-m", message]);
}

async function createRepo() {
  const repoRoot = await mkdtemp(path.join(os.tmpdir(), "hustleops-public-deploy-release-"));

  await execFileAsync("git", ["init", repoRoot]);
  await git(repoRoot, ["config", "user.email", "ci@example.test"]);
  await git(repoRoot, ["config", "user.name", "CI Test"]);
  await writeFile(path.join(repoRoot, "README.md"), "# Deploy Bundle\n");
  await writeReleaseFixture(repoRoot, "v2.3.4");
  await commitAll(repoRoot, "chore: initial deploy bundle");

  return repoRoot;
}

async function runBuilder(repoRoot, extraArgs = []) {
  const outputFile = path.join(repoRoot, ".hustleops", "release-notes.md");
  const githubOutputFile = path.join(repoRoot, ".hustleops", "github-output.txt");
  const result = await execFileAsync(
    process.execPath,
    [
      path.join(projectRoot, "scripts", "build-public-deploy-release.mjs"),
      "--repo-root",
      repoRoot,
      "--manifest-file",
      path.join(repoRoot, "release-manifest.json"),
      "--release-dir",
      path.join(repoRoot, "releases"),
      "--output",
      outputFile,
      "--github-output",
      githubOutputFile,
      ...extraArgs,
    ],
    { cwd: projectRoot },
  );

  return {
    ...result,
    json: JSON.parse(result.stdout),
    notes: await readFile(outputFile, "utf8"),
    githubOutput: await readFile(githubOutputFile, "utf8"),
  };
}

test("builds first public deploy release independently from source app version", async () => {
  const repoRoot = await createRepo();
  const { stderr, json, notes, githubOutput } = await runBuilder(repoRoot);

  assert.equal(stderr, "");
  assert.equal(json.shouldPublish, true);
  assert.equal(json.releaseTag, "public-deploy-v0.1.0");
  assert.equal(json.sourceReleaseTag, "v2.3.4");
  assert.match(notes, /Public deploy tag: `public-deploy-v0\.1\.0`/);
  assert.match(notes, /Source app release: \[v2\.3\.4\]/);
  assert.match(notes, /This is the first public deploy release/);
  assert.match(githubOutput, /^should_publish=true$/m);
  assert.match(githubOutput, /^release_tag=public-deploy-v0\.1\.0$/m);
  assert.match(githubOutput, /^release_record_file=releases\/v2\.3\.4\.json$/m);
});

test("bumps patch version for direct repository changes", async () => {
  const repoRoot = await createRepo();

  await git(repoRoot, ["tag", "public-deploy-v0.1.0"]);
  await writeFile(path.join(repoRoot, "README.md"), "# Deploy Bundle\n\nDirect repo change.\n");
  await commitAll(repoRoot, "docs: explain deploy bundle");

  const { json, notes, githubOutput } = await runBuilder(repoRoot);

  assert.equal(json.shouldPublish, true);
  assert.equal(json.releaseTag, "public-deploy-v0.1.1");
  assert.match(notes, /docs: explain deploy bundle/);
  assert.match(notes, /`README\.md`/);
  assert.match(githubOutput, /^previous_tag=public-deploy-v0\.1\.0$/m);
});

test("does not publish when no files changed since previous public deploy tag", async () => {
  const repoRoot = await createRepo();

  await git(repoRoot, ["tag", "public-deploy-v0.1.0"]);

  const { json, notes, githubOutput } = await runBuilder(repoRoot);

  assert.equal(json.shouldPublish, false);
  assert.equal(json.changedFileCount, 0);
  assert.match(notes, /No release will be published because no repository files changed/);
  assert.match(githubOutput, /^should_publish=false$/m);
});

test("supports forced manual releases without file changes", async () => {
  const repoRoot = await createRepo();

  await git(repoRoot, ["tag", "public-deploy-v0.1.0"]);

  const { json, notes, githubOutput } = await runBuilder(repoRoot, ["--force", "true"]);

  assert.equal(json.shouldPublish, true);
  assert.equal(json.releaseTag, "public-deploy-v0.1.1");
  assert.match(notes, /Manual release requested with no file changes/);
  assert.match(githubOutput, /^should_publish=true$/m);
});

test("bumps public deploy version when source app contract changes", async () => {
  const repoRoot = await createRepo();

  await git(repoRoot, ["tag", "public-deploy-v0.1.0"]);
  await writeReleaseFixture(repoRoot, "v2.4.0");
  await commitAll(repoRoot, "chore(release): update public deploy for v2.4.0");

  const { json, notes } = await runBuilder(repoRoot);

  assert.equal(json.shouldPublish, true);
  assert.equal(json.releaseTag, "public-deploy-v0.1.1");
  assert.equal(json.sourceReleaseTag, "v2.4.0");
  assert.match(notes, /The checked-in source app deployment contract changed/);
  assert.match(notes, /Source app release: \[v2\.4\.0\]/);
  assert.match(notes, /`releases\/v2\.4\.0\.json`/);
});
