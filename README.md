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
- Codex internal sandbox is disabled by default because Docker is the isolation boundary;
- Linux capabilities are dropped;
- Docker logs are disabled;
- no Docker socket is mounted;
- no bubblewrap dependency inside agent images;
- agent packages are installed inside images, not on the host.

This is not a perfect sandbox. The agent can still change files inside the
mounted `workspace/` directory.

## Tools

- `codex/` - OpenAI Codex CLI
- `gemini/` - Google Gemini CLI
- `claude/` - planned

## Included Tools

Agent images include the practical local toolchain by default:

- git, bash, curl, SSH, rsync
- Python, pip, Node.js, npm
- Terraform from the latest HashiCorp release at build time
- Ansible from Alpine packages
- jq and yq

Cloud provider CLIs are intentionally not included. For Terraform and Ansible, keep projects in `workspace/` and credentials outside it in `.secrets/`.

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
./codex.sh --device-auth
OPENAI_API_KEY=... ./codex.sh --api
./codex.sh --resume last
```

### Gemini

```bash
cd gemini
./gemini.sh
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

## Secrets

Do not put cloud credentials, Terraform backend secrets, Ansible vault passwords, or private keys into `workspace/`. Store them in per-agent `.secrets/` directories instead:

```text
codex/.secrets/
gemini/.secrets/
```

They are ignored by git and mounted read-only at `/run/agent-secrets`.

Examples:

```text
.secrets/ansible/vault-password.txt
.secrets/aws/credentials
.secrets/gcp/service-account.json
.secrets/yc/authorized_key.json
```

## Per-Agent SSH Keys

Do not mount your personal `~/.ssh` directory into an agent container. Create a separate key for each agent and add only the public key to the repository as a deploy key:

```bash
cd codex
./codex.sh --init-ssh-key

cd ../gemini
./gemini.sh --init-ssh-key
```

The command prints the public key. Add it in GitHub/GitLab repository settings as a deploy key:

- read-only for clone/pull;
- write access only when the agent must push;
- separate key per agent/project when possible.

Private keys stay in `codex/.ssh/` or `gemini/.ssh/`, are ignored by git, and are mounted read-only into the container.

## Security Defaults

- `alpine:3.23`
- non-root users
- `no-new-privileges`
- `cap_drop: ALL`
- `logging.driver: none`
- OTEL exporters disabled
- no privileged mode
- no Docker socket mount
- Codex uses `sandbox_mode = "danger-full-access"` inside the container to avoid a second bubblewrap sandbox

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
