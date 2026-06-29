# Gemini

Google Gemini CLI in an Alpine Docker container.

Gemini runs inside the container. By default, only `./workspace` is mounted as
`/workspace`.

## Start

```bash
./gemini.sh
```

On first run Gemini prints a Google login URL. Open it in the host browser,
authorize, and paste the returned code into the terminal.

If Gemini asks whether you trust the folder, choose:

```text
1. Trust folder (workspace)
```

Do not trust the parent folder unless you intentionally want a broader trust
scope.

Working files go here:

```text
./workspace/
```

`Dockerfile`, `compose.yml`, `gemini.sh`, and `.gemini` stay outside the mounted
workspace, so Gemini does not see or edit the runner files by default.

Useful commands:

```bash
./gemini.sh --login
./gemini.sh --debug
./gemini.sh -p "Explain this repository"
```

## State

Gemini state is stored here:

```text
./.gemini
```

Inside the container:

```text
/home/gemini/.gemini
```

## Rebuild

```bash
GEMINI_FORCE_BUILD=1 ./gemini.sh --help
GEMINI_VERSION=0.49.0 ./gemini.sh --help
```

## Isolation

- Alpine-based image
- non-root user `gemini`
- no Bash inside the image
- no Docker socket mount
- `cap_drop: ALL`
- `no-new-privileges`
- Docker logs disabled
- OTEL exporters disabled

Gemini can still edit files inside `./workspace`, because that directory is
mounted as `/workspace`.
