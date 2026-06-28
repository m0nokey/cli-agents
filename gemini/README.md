# Gemini CLI Docker Runner

Dockerized runner for Google Gemini CLI with project-local auth state and a normal interactive TTY. The image keeps Gemini and npm-installed CLI packages isolated from the host system.

## What It Does

- Runs Gemini CLI inside Docker Compose.
- Uses `alpine:3.23` as the base image.
- Installs Gemini CLI from npm package `@google/gemini-cli`.
- Stores Gemini CLI state in project-local `.gemini`.
- Runs as non-root user `gemini`.
- Uses `/bin/sh` inside the container; Bash is not installed in the image.
- Uses the Gemini browser auth-code flow for Google login.
- Skips rebuild when Gemini npm package integrity/version, Alpine base image digest, and Dockerfile hash are unchanged.
- Clears common OTEL/BuildKit trace environment variables before invoking Docker.

## Files

- `Dockerfile` — Alpine-based Gemini CLI image.
- `compose.yml` — interactive Docker Compose service with TTY.
- `gemini.sh` — launcher script.
- `README.md` — this file.

## Login

Normal startup begins the login flow automatically if `.gemini` has no saved authorization.

Gemini CLI prints a Google authorization URL in the terminal. Open the URL in your host browser, authorize, and paste the returned code back into the terminal.

First run:

```bash
cd gemini
./gemini.sh
```

If Gemini asks whether you trust the folder, choose:

```text
1. Trust folder (workspace)
```

This allows Gemini to use configuration from the mounted project workspace. Avoid trusting the parent folder unless you intentionally want a broader trust scope.

Force login:

```bash
./gemini.sh --login
```

Auth state is saved in:

```text
./.gemini
```

Inside the container it is mounted as:

```text
/home/gemini/.gemini
```

## Run

After login, the same command starts Gemini normally:

```bash
./gemini.sh
```

Pass Gemini CLI arguments directly:

```bash
./gemini.sh --help
./gemini.sh -p "Explain this repository"
```

Debug mode:

```bash
./gemini.sh --debug
```

Force rebuild:

```bash
GEMINI_FORCE_BUILD=1 ./gemini.sh --help
```

Pin Gemini package version:

```bash
GEMINI_VERSION=0.1.0 ./gemini.sh --help
```

## Networking

The container uses normal Docker bridge networking.

Google login does not require host networking in the tested flow: Gemini CLI prints a Google auth URL and accepts the returned authorization code in the terminal.

## Host Protection

The agent runs inside a container and only receives the mounted workspace, not the entire host home directory.

This matters because terminal agents can run commands and edit files. If an agent, package, or prompt makes a bad decision, destructive changes are limited to the mounted project workspace instead of the whole laptop by default.

The workspace is still writable. Keep secrets and unrelated personal files outside the project directory.

## Security Defaults

The container uses:

- non-root user `gemini`;
- `no-new-privileges:true`;
- `cap_drop: ALL`;
- tmpfs `/tmp` with `nosuid,nodev`;
- `logging.driver: none`;
- no Docker socket mount;
- no privileged mode;
- OTEL exporters disabled inside the container.

`/workspace` remains writable because Gemini CLI is an agent and needs to edit project files.
