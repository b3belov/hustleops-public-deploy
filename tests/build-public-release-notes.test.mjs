import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const projectRoot = path.resolve(import.meta.dirname, "..");

async function readJson(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

test("builds public release notes from checked-in contract metadata", async () => {
  const outputDir = await mkdtemp(path.join(os.tmpdir(), "hustleops-public-release-"));
  const notesFile = path.join(outputDir, "release-notes.md");
  const githubOutputFile = path.join(outputDir, "github-output.txt");

  const { stderr } = await execFileAsync(
    process.execPath,
    [
      "scripts/build-public-release-notes.mjs",
      "--output",
      notesFile,
      "--github-output",
      githubOutputFile,
    ],
    { cwd: projectRoot },
  );

  assert.equal(stderr, "");

  const manifest = await readJson(path.join(projectRoot, "release-manifest.json"));
  const releaseRecord = await readJson(
    path.join(projectRoot, "releases", `${manifest.release.tag}.json`),
  );
  const notes = await readFile(notesFile, "utf8");
  const githubOutput = await readFile(githubOutputFile, "utf8");

  assert.match(notes, /^## Public Contract$/m);
  assert.match(notes, /^## Runtime Images$/m);
  assert.match(notes, /^## Operator Update$/m);
  assert.match(notes, /^## Verification$/m);
  assert.ok(notes.includes(manifest.release.tag));
  assert.ok(notes.includes(manifest.release.url));
  assert.ok(notes.includes(`releases/${manifest.release.tag}.json`));
  assert.ok(notes.includes(releaseRecord.contract.digestRef));
  assert.ok(notes.includes(manifest.images.backend.digest));
  assert.ok(notes.includes("./scripts/deploy.sh update --env-file .env"));

  assert.match(githubOutput, new RegExp(`^tag=${manifest.release.tag}$`, "m"));
  assert.match(
    githubOutput,
    new RegExp(`^title=HustleOps Public Deploy ${manifest.release.tag}$`, "m"),
  );
  assert.match(
    githubOutput,
    new RegExp(`^release_record_file=releases/${manifest.release.tag}\\.json$`, "m"),
  );
});
