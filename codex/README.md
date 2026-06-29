# Codex

OpenAI Codex CLI in an Alpine Docker container.

Codex runs inside the container. By default, only `./workspace` is mounted as
`/workspace`.

## Start

```bash
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

Working files go here:

```text
./workspace/
```

`Dockerfile`, `compose.yml`, `codex.sh`, and `.codex` stay outside the mounted
workspace, so Codex does not see or edit the runner files by default.

Useful commands:

```bash
./codex.sh --device-auth
OPENAI_API_KEY=... ./codex.sh --api
./codex.sh --resume last
```

## State

Codex state is stored here:

```text
./.codex
```

Inside the container:

```text
/home/codex/.codex
```

## Rebuild

```bash
CODEX_FORCE_BUILD=1 ./codex.sh --help
CODEX_VERSION=0.70.0 ./codex.sh --help
```

## Isolation

- Alpine-based image
- non-root user `codex`
- Bash is installed for shell-tool compatibility
- no Docker socket mount
- `cap_drop: ALL`
- `no-new-privileges`
- Docker logs disabled
- OTEL exporters disabled

Codex can still edit files inside `./workspace`, because that directory is
mounted as `/workspace`.
