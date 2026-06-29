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

## Requirements

- Docker with Docker Compose plugin
- Bash on the host

Containers are Alpine-based and use `/bin/sh`; Bash is not installed inside the
images.

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
./codex.sh --device-auth
OPENAI_API_KEY=... ./codex.sh --api
./codex.sh --resume last
```

### Gemini

```bash
cd gemini
GEMINI_API_KEY=... ./gemini.sh
```

Or persist the key outside the mounted workspace:

```bash
mkdir -p .gemini
printf 'GEMINI_API_KEY=your-key-here\n' > .gemini/.env
./gemini.sh
```

Google browser/keychain login is less reliable inside Docker. If Gemini asks:

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
