# Codex

OpenAI Codex CLI in an Alpine Docker container.

Codex runs inside the container, while this directory is mounted as
`/workspace`.

## Start

```bash
./codex.sh
```

If no saved login exists, device authorization starts automatically.

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
- no Bash inside the image
- no Docker socket mount
- `cap_drop: ALL`
- `no-new-privileges`
- Docker logs disabled
- OTEL exporters disabled

Codex can still edit files in this directory because `./` is mounted as
`/workspace`.
