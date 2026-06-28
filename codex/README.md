# Codex CLI Docker Runner

Dockerized runner for OpenAI Codex CLI with project-local auth/config state and an interactive TTY. The image keeps Codex and its supporting tools isolated from the host system.

## What It Does

- Runs Codex CLI inside Docker Compose.
- Uses `alpine:3.23` as the base image.
- Downloads the official Codex Rust musl release asset from GitHub.
- Stores Codex state in project-local `.codex`.
- Runs as non-root user `codex`.
- Uses `/bin/sh` inside the container; Bash is not installed in the image.
- Skips rebuild when the Codex release asset digest and Alpine base image digest are unchanged.
- Clears common OTEL/BuildKit trace environment variables before invoking Docker.

## Files

- `Dockerfile` — Alpine-based Codex CLI image.
- `compose.yml` — interactive Docker Compose service with TTY.
- `codex.sh` — launcher script.
- `README.md` — this file.

## First Run

```bash
cd codex
./codex.sh
```

If no saved auth exists, the wrapper starts Codex device authorization automatically.

Force device authorization:

```bash
./codex.sh --device-auth
```

Use API-key mode:

```bash
OPENAI_API_KEY=... ./codex.sh --api
```

Auth/config state is saved in:

```text
./.codex
```

Inside the container it is mounted as:

```text
/home/codex/.codex
```

## Resume

Resume the latest session:

```bash
./codex.sh --resume last
```

Resume a specific session:

```bash
./codex.sh --resume <session-id>
```

## Rebuild Controls

Force rebuild:

```bash
CODEX_FORCE_BUILD=1 ./codex.sh --help
```

Pin Codex version:

```bash
CODEX_VERSION=0.70.0 ./codex.sh --help
```

## Host Protection

The agent runs inside a container and only receives the mounted workspace, not the entire host home directory.

This matters because terminal agents can run commands and edit files. If an agent, package, or prompt makes a bad decision, destructive changes are limited to the mounted project workspace instead of the whole laptop by default.

The workspace is still writable. Keep secrets and unrelated personal files outside the project directory.

## Security Defaults

The container uses:

- non-root user `codex`;
- `no-new-privileges:true`;
- `cap_drop: ALL`;
- tmpfs `/tmp` with `nosuid,nodev`;
- `logging.driver: none`;
- no Docker socket mount;
- no privileged mode;
- OTEL exporters disabled inside the container.

`/workspace` remains writable because Codex is an agent and needs to edit project files.
