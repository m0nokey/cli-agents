# CLI Agents

Docker runners for terminal coding agents: Codex, Gemini, and future tools.

The goal is simple: run powerful agent CLIs without installing their runtimes,
npm packages, caches, and auth files directly on your laptop.

## Why

Coding agents can run commands and edit files. A bad prompt, tool bug, or
compromised package can damage files on the host.

This project reduces the blast radius:

- only the per-agent `workspace/` directory is mounted;
- Dockerfile, compose.yml, and wrapper scripts stay outside `/workspace`;
- auth/state is stored locally in `.codex` or `.gemini`;
- containers run as non-root users;
- Linux capabilities are dropped;
- Docker logs are disabled;
- no Docker socket is mounted;
- agent packages are installed inside images, not on the host.

This is not a perfect sandbox. The agent can still change files inside the
mounted `workspace/` directory.

## Tools

- `codex/` - OpenAI Codex CLI
- `gemini/` - Google Gemini CLI
- `claude/` - planned

## DevOps Tools Mode

Each agent has an optional tools image:

```bash
./codex.sh --tools
./gemini.sh --tools
```

The tools image keeps the same isolated `workspace/` mount, but adds common DevOps CLIs:

- Terraform from the latest HashiCorp release at build time
- Yandex Cloud CLI from the latest stable release at build time
- Google Cloud CLI from the latest rapid release at build time
- AWS CLI v2 from Alpine packages
- Ansible from Alpine packages
- yq, jq, git, curl, SSH, rsync, and basic shell utilities

Put Terraform, Ansible, and cloud projects inside the agent `workspace/` directory. The agent does not see files outside that mount by default.

## Requirements

- Docker with Docker Compose plugin
- Bash on the host

Containers are Alpine-based and include Bash because agent shell tools commonly spawn `bash`.

## Quick Start

### Codex

```bash
cd codex
./codex.sh
```

On first run Codex asks how to sign in:

```text
1. Sign in with ChatGPT
2. Sign in with Device Code
3. Provide your own API key
```

Choose ChatGPT if your plan includes Codex, Device Code for login from another
device, or API key for usage-based billing.


By default, Codex can edit only files inside:

```text
codex/workspace/
```

The runner files stay outside that mount.

Useful commands:

```bash
./codex.sh --tools
./codex.sh --device-auth
OPENAI_API_KEY=... ./codex.sh --api
./codex.sh --resume last
```

### Gemini

```bash
cd gemini
./gemini.sh
./gemini.sh --tools
```

The default model is `gemini-3.1-flash-lite`. Override it when needed:

```bash
GEMINI_MODEL=other-model ./gemini.sh
```

On first run Gemini starts the Google login flow. If a browser does not open automatically, copy the printed URL into your host browser and finish auth there.

The container sets `GEMINI_FORCE_FILE_STORAGE=true`, so OAuth tokens are written to `.gemini/gemini-credentials.json` instead of a desktop keychain.

If Gemini asks:

```text
Do you trust the files in this folder?
```

Choose:

```text
1. Trust folder (workspace)
```

Do not trust the parent folder unless you intentionally want a broader trust
scope.

By default, Gemini can edit only files inside:

```text
gemini/workspace/
```

The runner files stay outside that mount.

## Security Defaults

- `alpine:3.23`
- non-root users
- `no-new-privileges`
- `cap_drop: ALL`
- `logging.driver: none`
- OTEL exporters disabled
- no privileged mode
- no Docker socket mount

## Scan Images

Codex:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v trivy-cache:/root/.cache/ \
  aquasec/trivy:latest image \
  --scanners vuln \
  --timeout 10m \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  local/codex-rust:latest
```

Gemini:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v trivy-cache:/root/.cache/ \
  aquasec/trivy:latest image \
  --scanners vuln \
  --timeout 10m \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  local/gemini-cli:latest
```
