#!/usr/bin/env node

import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

const scriptDir = import.meta.dirname;
const projectRoot = path.resolve(scriptDir, "..");
const execFileAsync = promisify(execFile);

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
  PUBLIC_HOST_ALIASES: "ops.internal.hustleops.local,127.0.0.1",
  NGINX_HTTP_BIND: "127.0.0.1",
  NGINX_HTTPS_BIND: "127.0.0.1",
  NGINX_TLS_CERT_PATH: "./.hustleops/nginx/certs/fullchain.pem",
  NGINX_TLS_KEY_PATH: "./.hustleops/nginx/certs/privkey.pem",
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

function upsertEnvValue(content, key, value) {
  const pattern = new RegExp(`^${key}=.*$`, "m");
  const line = `${key}=${value}`;

  if (pattern.test(content)) {
    return content.replace(pattern, line);
  }

  return `${content.endsWith("\n") ? content : `${content}\n`}${line}\n`;
}

async function writeNginxTestCerts() {
  const certDir = path.join(projectRoot, ".hustleops", "nginx", "certs");
  const configFile = path.join(certDir, "openssl.cnf");
  const certFile = path.join(certDir, "fullchain.pem");
  const keyFile = path.join(certDir, "privkey.pem");

  await mkdir(certDir, { recursive: true });
  await writeFile(
    configFile,
    [
      "[req]",
      "default_bits = 2048",
      "prompt = no",
      "default_md = sha256",
      "distinguished_name = dn",
      "x509_extensions = v3_req",
      "",
      "[dn]",
      "CN = hustleops.local",
      "",
      "[v3_req]",
      "subjectAltName = DNS:hustleops.local,DNS:ops.internal.hustleops.local,IP:127.0.0.1",
      "",
    ].join("\n"),
  );

  await execFileAsync("openssl", [
    "req",
    "-x509",
    "-nodes",
    "-newkey",
    "rsa:2048",
    "-days",
    "1",
    "-keyout",
    keyFile,
    "-out",
    certFile,
    "-config",
    configFile,
  ]);
}

async function main() {
  const { templateFile, outputFile } = parseArgs(process.argv.slice(2));
  let content = await readFile(templateFile, "utf8");

  for (const [key, value] of Object.entries(REPLACEMENTS)) {
    content = replaceEnvValue(content, key, value);
  }

  content = upsertEnvValue(
    content,
    "POSTGRES_PASSWORD_ENCODED",
    encodeURIComponent(REPLACEMENTS.POSTGRES_PASSWORD),
  );

  await writeNginxTestCerts();
  await mkdir(path.dirname(outputFile), { recursive: true });
  await writeFile(outputFile, content.endsWith("\n") ? content : `${content}\n`);
  process.stdout.write(`Wrote ${outputFile}\n`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
