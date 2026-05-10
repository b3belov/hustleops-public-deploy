#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const scriptDir = import.meta.dirname;
const projectRoot = path.resolve(scriptDir, "..");

const REPLACEMENTS = {
  POSTGRES_PASSWORD: "Ho1!postgres-password-for-ci",
  REDIS_PASSWORD: "Ho1!redis-password-for-ci",
  JWT_ACCESS_SECRET: "ci-access-secret-ci-access-secret-123456",
  JWT_REFRESH_SECRET: "ci-refresh-secret-ci-refresh-secret-123456",
  TWO_FACTOR_ENCRYPTION_KEY: "a".repeat(64),
  BOOTSTRAP_ADMIN_EMAIL: "admin@hustleops.local",
  BOOTSTRAP_ADMIN_PASSWORD: "Ho1!bootstrap-password-for-ci",
  CORS_ORIGIN: "https://hustleops.local",
  OPENSEARCH_ADMIN_PASSWORD: "Ho1!opensearch-password-for-ci",
  N8N_POSTGRES_PASSWORD: "Ho1!n8n-postgres-password-for-ci",
  N8N_REDIS_PASSWORD: "Ho1!n8n-redis-password-for-ci",
  N8N_ENCRYPTION_KEY: "Ho1!n8n-encryption-key-for-ci-123456",
  N8N_RUNNERS_AUTH_TOKEN: "b".repeat(64),
};

function parseArgs(argv) {
  const args = {
    "template-file": path.join(projectRoot, ".env.example"),
    output: path.join(projectRoot, ".hustleops", "ci.env"),
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];

    if (!argument.startsWith("--")) {
      throw new Error(`Unknown argument: ${argument}`);
    }

    const key = argument.slice(2);
    const value = argv[index + 1];

    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${key}.`);
    }

    if (!(key in args)) {
      throw new Error(`Unknown argument: --${key}.`);
    }

    args[key] = value;
    index += 1;
  }

  return {
    templateFile: path.resolve(args["template-file"]),
    outputFile: path.resolve(args.output),
  };
}

function replaceEnvValue(content, key, value) {
  const pattern = new RegExp(`^${key}=.*$`, "m");

  if (!pattern.test(content)) {
    throw new Error(`Env template is missing ${key}.`);
  }

  return content.replace(pattern, `${key}=${value}`);
}

async function main() {
  const { templateFile, outputFile } = parseArgs(process.argv.slice(2));
  let content = await readFile(templateFile, "utf8");

  for (const [key, value] of Object.entries(REPLACEMENTS)) {
    content = replaceEnvValue(content, key, value);
  }

  await mkdir(path.dirname(outputFile), { recursive: true });
  await writeFile(outputFile, content.endsWith("\n") ? content : `${content}\n`);
  process.stdout.write(`Wrote ${outputFile}\n`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
