# Gemini

Google Gemini CLI in an Alpine Docker container.

Gemini runs inside the container. By default, only `./workspace` is mounted as
`/workspace`.

## Start

```bash
./gemini.sh
```

The default model is `gemini-3.1-flash-lite`. Override it when needed:

```bash
GEMINI_MODEL=other-model ./gemini.sh
```

On first run Gemini starts the Google login flow. If a browser does not open automatically, copy the printed URL into your host browser and finish auth there.

The container sets `GEMINI_FORCE_FILE_STORAGE=true`, so OAuth tokens are written to `.gemini/gemini-credentials.json` instead of a desktop keychain.

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
./gemini.sh --tools
./gemini.sh --login
./gemini.sh --debug
./gemini.sh -p "Explain this repository"
```

## Tools Mode

```bash
./gemini.sh --tools
```

This builds and runs `Dockerfile.tools` as `local/gemini-cli-tools:latest`. It adds Terraform, Ansible, yc, aws, gcloud, yq, jq, SSH, and rsync to the Gemini container.

Keep Terraform and Ansible projects inside:

```text
./workspace/
```

The tools image still does not mount the Docker socket or host directories outside `./workspace`.

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
- Bash is installed for shell-tool compatibility
- no Docker socket mount
- `cap_drop: ALL`
- `no-new-privileges`
- Docker logs disabled
- OTEL exporters disabled

Gemini can still edit files inside `./workspace`, because that directory is
mounted as `/workspace`.
