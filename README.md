# CLI Agents

Project-local Docker Compose runners for terminal agents such as Codex, Gemini, and future Claude-style CLIs.

The main goal is isolation: agent CLIs and their package ecosystems should not be installed directly into the host system. These tools can execute commands, edit files, install dependencies, and make mistakes. Running them in containers reduces the chance that a broken package, compromised dependency, or bad agent action damages the whole laptop environment.

## Why

Agent CLIs are powerful. That also makes them risky:

- global `npm install -g ...` pollutes the host;
- auth/config files get written into the host home directory;
- agent tools may install or execute untrusted packages;
- mistakes can delete or rewrite files outside the intended project;
- Docker/Desktop/BuildKit can produce runtime logs or OTLP trace files by default;
- tool versions drift between machines.

This repository keeps each agent in a small project-local container runner.

## Tools

- `codex` — OpenAI Codex CLI runner.
- `gemini` — Google Gemini CLI runner.
- `claude` — planned.

## Layout

```text
cli-agents/
├── codex/
│   ├── codex.sh
│   ├── Dockerfile
│   ├── compose.yml
│   └── README.md
├── gemini/
│   ├── gemini.sh
│   ├── Dockerfile
│   ├── compose.yml
│   └── README.md
└── README.md
```


## Host Protection

Modern coding agents can run shell commands and modify files. That includes agents such as Codex, Gemini, Claude-style CLIs, OpenCode-style tools, or any future terminal agent installed from npm or another package registry.

A bad prompt, a tool bug, a compromised package, or a wrong command can theoretically do things like:

- delete files with `rm -rf`;
- rewrite source code outside the intended project;
- modify shell profiles or local config files;
- install unexpected packages globally;
- read secrets from the host home directory;
- leave logs, caches, tokens, or telemetry files behind.

This project puts the agent inside a Docker sandbox and mounts only the project directory that you choose to run it from. The agent can still edit that mounted workspace, because that is the point of a coding agent, but it does not get your full host filesystem by default.

In practice:

```text
host laptop
  └── project directory mounted into container
        └── agent can work here
```

Not this:

```text
host laptop
  └── entire home directory exposed to agent
```

This does not make destructive actions impossible inside the project, but it reduces blast radius from "my whole laptop" to "the workspace I intentionally mounted".

## Security Model

The containers are not a perfect sandbox. They intentionally mount the current workspace because agents need to read and edit project files.

What this setup does protect:

- the agent runtime is not installed on the host;
- Node/npm packages stay inside the image;
- auth/config state is project-local (`.codex`, `.gemini`);
- containers run as non-root users;
- Linux capabilities are dropped;
- `no-new-privileges` is enabled;
- Docker runtime logs are disabled;
- common OpenTelemetry exporters are disabled;
- Docker wrapper calls clear common OTEL/BuildKit trace environment variables;
- images are based on `alpine:3.23`;
- no Docker socket is mounted into the agent containers.

What this setup does not protect:

- files inside the mounted workspace;
- secrets you explicitly place in the workspace;
- actions you approve inside an agent session;
- host-level Docker daemon or Docker Desktop telemetry settings outside this project.

## Requirements

Host requirements:

- Docker with the Docker Compose plugin;
- `bash` for the wrapper scripts;
- `curl` and `python3` are recommended for version/digest metadata resolution.

Container notes:

- containers use `/bin/sh`;
- Bash is not installed inside the agent images.

## Quick Start

Codex:

```bash
cd codex
./codex.sh
```

On first Codex startup, the wrapper starts device authorization automatically if no saved auth exists.

Force device authorization:

```bash
./codex.sh --device-auth
```

Use API-key mode instead of saved ChatGPT auth:

```bash
OPENAI_API_KEY=... ./codex.sh --api
```

Resume the latest session:

```bash
./codex.sh --resume last
```

Gemini:

```bash
cd gemini
./gemini.sh
```

On first Gemini startup, the CLI may ask whether you trust the project folder:

```text
Do you trust the files in this folder?
1. Trust folder (workspace)
2. Trust parent folder ()
3. Don't trust
```

For this container layout, choose:

```text
1. Trust folder (workspace)
```

Do not trust the parent folder unless you intentionally want Gemini to load configuration from a broader path.

Each wrapper builds the image when needed, then starts an interactive CLI session.

## Logging And Traces

Both Compose services use:

```yaml
logging:
  driver: "none"
```

The wrappers also clear common Docker/OpenTelemetry variables before invoking Docker.

Docker Desktop / BuildKit may create files like:

```text
traces-otlp-<trace-id>.json
```

The root `.gitignore` excludes them:

```gitignore
traces-otlp-*.json
```

## Vulnerability Scanning

Codex image:

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

Gemini image:

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
