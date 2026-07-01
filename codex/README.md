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

## Included Tools

The image includes git, bash, Python/pip, Node/npm, Terraform, Ansible, jq/yq, SSH, and rsync.

Keep projects inside:

```text
./workspace/
```

Keep credentials outside the workspace in:

```text
./.secrets/
```

Secrets are mounted read-only inside the container as `/run/agent-secrets`.

## SSH Deploy Key

Create a separate SSH key for Codex instead of mounting your personal `~/.ssh`:

```bash
./codex.sh --init-ssh-key
```

The command prints a public key. Add it to the target GitHub/GitLab repository as a deploy key. Use read-only access for clone/pull, and enable write access only if Codex must push.

The private key is stored in:

```text
./.ssh/id_ed25519
```

It is ignored by git and mounted read-only into the container as `/home/codex/.ssh`.

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

## Codex Sandbox

The container is the sandbox boundary. The default Codex config uses:

```toml
sandbox_mode = "danger-full-access"
approval_policy = "on-request"
```

This avoids running Codex's inner bubblewrap sandbox inside Docker while keeping Docker volume isolation.

## Isolation

- Alpine-based image
- non-root user `codex`
- Bash is installed for shell-tool compatibility
- no Docker socket mount
- no bubblewrap dependency
- default Codex config uses `sandbox_mode = "danger-full-access"` inside Docker
- `cap_drop: ALL`
- `no-new-privileges`
- Docker logs disabled
- OTEL exporters disabled

Codex can still edit files inside `./workspace`, because that directory is
mounted as `/workspace`.
