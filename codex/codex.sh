#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

CODEX_IMAGE_NAME="${CODEX_IMAGE_NAME:-local/codex-rust:latest}"
CODEX_VERSION="${CODEX_VERSION:-latest}"
CODEX_GITHUB_REPO="${CODEX_GITHUB_REPO:-openai/codex}"
CODEX_RUNNER_DIR="${CODEX_RUNNER_DIR:-$SCRIPT_DIR}"
CODEX_WORKSPACE_DIR="${CODEX_WORKSPACE_DIR:-${CODEX_RUNNER_DIR}/workspace}"
PROJECT_CODEX_DIR_NAME="${PROJECT_CODEX_DIR_NAME:-.codex}"
PROJECT_CODEX_DIR="${CODEX_STATE_DIR:-${CODEX_RUNNER_DIR}/${PROJECT_CODEX_DIR_NAME}}"
CODEX_SSH_DIR="${CODEX_SSH_DIR:-${CODEX_RUNNER_DIR}/.ssh}"
CODEX_SECRETS_DIR="${CODEX_SECRETS_DIR:-${CODEX_RUNNER_DIR}/.secrets}"
PROJECT_CONFIG_PATH="${PROJECT_CODEX_DIR}/config.toml"
ROOT_CONFIG_FALLBACK="${CODEX_WORKSPACE_DIR}/config.toml"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-${CODEX_RUNNER_DIR}/Dockerfile}"
COMPOSE_FILE_PATH="${COMPOSE_FILE_PATH:-${CODEX_RUNNER_DIR}/compose.yml}"
COMPOSE_SERVICE_NAME="${COMPOSE_SERVICE_NAME:-codex}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
export CODEX_IMAGE_NAME
export CODEX_RUNNER_DIR
export CODEX_WORKSPACE_DIR
export CODEX_STATE_DIR="$PROJECT_CODEX_DIR"
export CODEX_SSH_DIR
export CODEX_SECRETS_DIR

MODE="auto"
RESUME_VALUE=""
DEBUG_ENABLED=0
TRACE_ENABLED=0
CODEX_RESOLVED_VERSION=""
CODEX_RESOLVED_ASSET_DIGEST=""
CODEX_BASE_IMAGE_REF=""
CODEX_RESOLVED_BASE_IMAGE_DIGEST=""
CODEX_DOCKERFILE_SHA256=""

theme::init() {
    if [[ -t 1 ]]; then
        COLOR_RESET=$'\033[0m'
        COLOR_TEXT=$'\033[97m'
        COLOR_HEADER=$'\033[38;5;183m'
        COLOR_LINE=$'\033[38;5;117m'
        COLOR_INFO=$'\033[38;5;117m'
        COLOR_WARN=$'\033[38;5;221m'
        COLOR_ERROR=$'\033[38;5;203m'
        COLOR_DEBUG=$'\033[38;5;147m'
        COLOR_TRACE=$'\033[38;5;110m'
        COLOR_SUBTITLE=$'\033[38;5;189m'
    else
        COLOR_RESET=''
        COLOR_TEXT=''
        COLOR_HEADER=''
        COLOR_LINE=''
        COLOR_INFO=''
        COLOR_WARN=''
        COLOR_ERROR=''
        COLOR_DEBUG=''
        COLOR_TRACE=''
        COLOR_SUBTITLE=''
    fi
}

log::info() {
    printf '%s[INFO]%s %s%s%s\n' \
        "$COLOR_INFO" \
        "$COLOR_RESET" \
        "$COLOR_TEXT" \
        "$*" \
        "$COLOR_RESET"
}

log::warn() {
    printf '%s[WARN]%s %s%s%s\n' \
        "$COLOR_WARN" \
        "$COLOR_RESET" \
        "$COLOR_TEXT" \
        "$*" \
        "$COLOR_RESET"
}

log::error() {
    printf '%s[ERROR]%s %s%s%s\n' \
        "$COLOR_ERROR" \
        "$COLOR_RESET" \
        "$COLOR_TEXT" \
        "$*" \
        "$COLOR_RESET" >&2
}

log::debug() {
    if [[ "$DEBUG_ENABLED" -eq 1 || "$TRACE_ENABLED" -eq 1 ]]; then
        printf '%s[DEBUG]%s %s%s%s\n' \
            "$COLOR_DEBUG" \
            "$COLOR_RESET" \
            "$COLOR_TEXT" \
            "$*" \
            "$COLOR_RESET"
    fi
}

log::trace() {
    if [[ "$TRACE_ENABLED" -eq 1 ]]; then
        printf '%s[TRACE]%s %s%s%s\n' \
            "$COLOR_TRACE" \
            "$COLOR_RESET" \
            "$COLOR_TEXT" \
            "$*" \
            "$COLOR_RESET"
    fi
}

show_help() {
    printf '%sUsage%s\n' "$COLOR_HEADER" "$COLOR_RESET"
    printf '    %s./%s%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --init-ssh-key%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --device-auth%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --api%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --resume <session-id|last>%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --help%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '\n'

    printf '%sBehavior%s\n' "$COLOR_HEADER" "$COLOR_RESET"
    printf '    %s- No arguments start a new Codex session when saved auth exists.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- If saved auth does not exist, auto mode starts device authorization first.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Uses docker compose instead of docker run.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Mounts ./workspace as /workspace by default.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Keeps Docker files and .codex state outside /workspace.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Creates .codex automatically if it does not exist.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Moves ./config.toml to ./.codex/config.toml when available.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Writes a default ./.codex/config.toml when no config file exists.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Hides docker compose build output unless --debug or --trace is enabled.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- --init-ssh-key creates a per-agent deploy key in ./.ssh.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '\n'

    printf '%sModes%s\n' "$COLOR_HEADER" "$COLOR_RESET"
    printf '    %sdefault%s          %sStart a new session if auth exists, otherwise authenticate first.%s\n' "$COLOR_LINE" "$COLOR_RESET" "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s--device-auth%s    %sForce ChatGPT device authorization, then start a new session.%s\n' "$COLOR_LINE" "$COLOR_RESET" "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s--api%s            %sStart a new session with OPENAI_API_KEY from the host.%s\n' "$COLOR_LINE" "$COLOR_RESET" "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s--resume last%s    %sResume the latest Codex session in the current workspace.%s\n' "$COLOR_LINE" "$COLOR_RESET" "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s--resume <id>%s    %sResume a specific session id.%s\n' "$COLOR_LINE" "$COLOR_RESET" "$COLOR_TEXT" "$COLOR_RESET"
    printf '\n'
}

default_config_contents() {
    cat <<'EOF'
model = "gpt-5.4"
web_search = "live"

approval_policy = "on-request"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = true
EOF
}

docker_cmd() {
    env \
        -u DOCKER_CLI_OTEL_EXPORTER_OTLP_ENDPOINT \
        -u DOCKER_CLI_OTEL_EXPORTER_OTLP_HEADERS \
        -u DOCKER_CLI_OTEL_EXPORTER_OTLP_PROTOCOL \
        -u OTEL_EXPORTER_OTLP_ENDPOINT \
        -u OTEL_EXPORTER_OTLP_TRACES_ENDPOINT \
        -u OTEL_EXPORTER_OTLP_HEADERS \
        -u OTEL_TRACES_EXPORTER \
        -u OTEL_SERVICE_NAME \
        -u BUILDKIT_TRACE \
        "$DOCKER_BIN" "$@"
}

compose_cmd() {
    docker_cmd compose -f "$COMPOSE_FILE_PATH" "$@"
}

github_api_get() {
    local url="$1"
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsSL \
        --connect-timeout 10 \
        --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        "$url"
}

dockerfile_default_codex_version() {
    awk -F= '/^ARG CODEX_VERSION=/ { print $2; exit }' "$DOCKERFILE_PATH" 2>/dev/null || true
}

file_sha256() {
    local path="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    else
        return 1
    fi
}

dockerfile_base_image_ref() {
    awk '/^FROM[[:space:]]+/ { print $2; exit }' "$DOCKERFILE_PATH" 2>/dev/null || true
}

resolve_latest_codex_version() {
    local json tag fallback
    fallback="$(dockerfile_default_codex_version)"
    json="$(github_api_get "https://api.github.com/repos/${CODEX_GITHUB_REPO}/releases?per_page=1" 2>/dev/null || true)"
    tag="$(printf '%s\n' "$json" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
    tag="${tag#rust-v}"
    if [[ -n "$tag" && "$tag" != "$json" ]]; then
        printf '%s' "$tag"
        return 0
    fi
    printf '%s' "${fallback:-latest}"
}

codex_release_arch() {
    case "$(uname -m)" in
        x86_64|amd64) printf '%s' "x86_64-unknown-linux-musl" ;;
        arm64|aarch64) printf '%s' "aarch64-unknown-linux-musl" ;;
        *) return 1 ;;
    esac
}

resolve_codex_asset_digest() {
    local version="$1" arch asset json digest
    arch="$(codex_release_arch 2>/dev/null || true)"
    [[ -n "$arch" ]] || return 0
    asset="codex-${arch}.tar.gz"
    json="$(github_api_get "https://api.github.com/repos/${CODEX_GITHUB_REPO}/releases/tags/rust-v${version}" 2>/dev/null || true)"
    [[ -n "$json" ]] || return 0

    if command -v python3 >/dev/null 2>&1; then
        digest="$(printf '%s' "$json" | python3 -c '
import json
import sys

asset_name = sys.argv[1]
data = json.load(sys.stdin)
for asset in data.get("assets", []):
    if asset.get("name") == asset_name:
        print(asset.get("digest") or "")
        break
' "$asset" 2>/dev/null || true)"
        printf '%s' "$digest"
    fi
}

docker_hub_manifest_digest() {
    local image_ref="$1" repo tag token digest
    [[ "$image_ref" == *:* ]] || return 0
    repo="${image_ref%:*}"
    tag="${image_ref##*:}"
    if [[ "$repo" != */* ]]; then
        repo="library/${repo}"
    fi

    token="$(curl -fsSL \
        --connect-timeout 10 \
        --max-time 30 \
        "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
        | sed -E 's/.*"token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' 2>/dev/null || true)"
    [[ -n "$token" ]] || return 0

    digest="$(curl -fsSI \
        --connect-timeout 10 \
        --max-time 30 \
        -H "Authorization: Bearer ${token}" \
        -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' \
        "https://registry-1.docker.io/v2/${repo}/manifests/${tag}" \
        | tr -d '\r' \
        | awk 'tolower($1)=="docker-content-digest:" { print $2; exit }' 2>/dev/null || true)"
    printf '%s' "$digest"
}

resolve_base_image_digest() {
    local image_ref="$1" digest="" inspect_line=""
    [[ -n "$image_ref" ]] || return 0

    if command -v "$DOCKER_BIN" >/dev/null 2>&1; then
        inspect_line="$(docker_cmd buildx imagetools inspect "$image_ref" 2>/dev/null | awk '/^Digest:/ { print $2; exit }' || true)"
        if [[ -n "$inspect_line" ]]; then
            digest="$inspect_line"
        else
            digest="$(docker_cmd manifest inspect "$image_ref" 2>/dev/null | grep -m1 '"digest"' | sed -E 's/.*"digest"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
        fi
    fi

    if [[ -z "$digest" && "$image_ref" != *.*/* ]]; then
        digest="$(docker_hub_manifest_digest "$image_ref")"
    fi

    printf '%s' "$digest"
}

resolve_codex_build_metadata() {
    if [[ "$CODEX_VERSION" == "latest" ]]; then
        CODEX_RESOLVED_VERSION="$(resolve_latest_codex_version)"
    else
        CODEX_RESOLVED_VERSION="$CODEX_VERSION"
    fi
    CODEX_RESOLVED_ASSET_DIGEST="$(resolve_codex_asset_digest "$CODEX_RESOLVED_VERSION")"
    CODEX_BASE_IMAGE_REF="$(dockerfile_base_image_ref)"
    CODEX_RESOLVED_BASE_IMAGE_DIGEST="$(resolve_base_image_digest "$CODEX_BASE_IMAGE_REF")"
    CODEX_DOCKERFILE_SHA256="$(file_sha256 "$DOCKERFILE_PATH" 2>/dev/null || true)"
}

local_image_label() {
    local label="$1"
    docker_cmd image inspect "$CODEX_IMAGE_NAME" \
        --format "{{ index .Config.Labels \"$label\" }}" 2>/dev/null || true
}

codex_image_is_current() {
    local local_version local_codex_digest local_base_digest local_dockerfile_sha
    local_version="$(local_image_label 'org.opencontainers.image.version')"
    local_codex_digest="$(local_image_label 'org.opencontainers.image.source-digest')"
    local_base_digest="$(local_image_label 'org.opencontainers.image.base.digest')"
    local_dockerfile_sha="$(local_image_label 'org.opencontainers.image.dockerfile-sha256')"

    if [[ -n "$CODEX_RESOLVED_ASSET_DIGEST" ]]; then
        [[ "$local_codex_digest" == "$CODEX_RESOLVED_ASSET_DIGEST" ]] || return 1
    else
        [[ -n "$CODEX_RESOLVED_VERSION" && "$local_version" == "$CODEX_RESOLVED_VERSION" ]] || return 1
    fi

    if [[ -n "$CODEX_RESOLVED_BASE_IMAGE_DIGEST" ]]; then
        [[ "$local_base_digest" == "$CODEX_RESOLVED_BASE_IMAGE_DIGEST" ]] || return 1
    fi

    if [[ -n "$CODEX_DOCKERFILE_SHA256" ]]; then
        [[ "$local_dockerfile_sha" == "$CODEX_DOCKERFILE_SHA256" ]] || return 1
    fi

    return 0
}

ensure_required_files() {
    if [[ ! -f "$DOCKERFILE_PATH" ]]; then
        log::error "Dockerfile not found: $DOCKERFILE_PATH"
        exit 1
    fi

    if [[ ! -f "$COMPOSE_FILE_PATH" ]]; then
        log::error "Compose file not found: $COMPOSE_FILE_PATH"
        exit 1
    fi
}

ensure_project_layout() {
    mkdir -p "$CODEX_WORKSPACE_DIR" "$PROJECT_CODEX_DIR" "$CODEX_SSH_DIR" "$CODEX_SECRETS_DIR"

    if [[ ! -f "$PROJECT_CONFIG_PATH" && -f "$ROOT_CONFIG_FALLBACK" ]]; then
        log::info "Moving project config into Codex state config.toml"
        mv "$ROOT_CONFIG_FALLBACK" "$PROJECT_CONFIG_PATH"
    fi

    if [[ ! -f "$PROJECT_CONFIG_PATH" ]]; then
        log::info "Writing default Codex config: $PROJECT_CONFIG_PATH"
        default_config_contents > "$PROJECT_CONFIG_PATH"
    fi
}

has_saved_auth() {
    [[ -f "${PROJECT_CODEX_DIR}/auth.json" || -f "${PROJECT_CODEX_DIR}/oauth.json" || -f "${PROJECT_CODEX_DIR}/credentials.json" ]]
}

build_image() {
    resolve_codex_build_metadata

    log::info "Latest Codex release: ${CODEX_RESOLVED_VERSION}"
    if [[ -n "$CODEX_RESOLVED_ASSET_DIGEST" ]]; then
        log::debug "Latest Codex asset digest: ${CODEX_RESOLVED_ASSET_DIGEST}"
    else
        log::warn "Could not resolve Codex asset digest; falling back to version label check"
    fi

    if [[ -n "$CODEX_RESOLVED_BASE_IMAGE_DIGEST" ]]; then
        log::debug "Base image ${CODEX_BASE_IMAGE_REF}: ${CODEX_RESOLVED_BASE_IMAGE_DIGEST}"
    else
        log::warn "Could not resolve base image digest for ${CODEX_BASE_IMAGE_REF:-unknown}; base image changes will not trigger rebuild"
    fi

    [[ -n "$CODEX_DOCKERFILE_SHA256" ]] && log::debug "Dockerfile sha256: ${CODEX_DOCKERFILE_SHA256}"

    if [[ "${CODEX_FORCE_BUILD:-0}" != "1" ]] && codex_image_is_current; then
        log::info "Docker image is current, skipping build: $CODEX_IMAGE_NAME"
        return
    fi

    log::info "Building Docker image: $CODEX_IMAGE_NAME"

    if [[ "$DEBUG_ENABLED" -eq 1 || "$TRACE_ENABLED" -eq 1 ]]; then
        compose_cmd build \
            --build-arg "CODEX_VERSION=${CODEX_RESOLVED_VERSION}" \
            --build-arg "CODEX_ASSET_DIGEST=${CODEX_RESOLVED_ASSET_DIGEST}" \
            --build-arg "CODEX_BASE_IMAGE_DIGEST=${CODEX_RESOLVED_BASE_IMAGE_DIGEST}" \
            --build-arg "CODEX_DOCKERFILE_SHA256=${CODEX_DOCKERFILE_SHA256}" \
            "$COMPOSE_SERVICE_NAME"
    else
        compose_cmd build \
            --build-arg "CODEX_VERSION=${CODEX_RESOLVED_VERSION}" \
            --build-arg "CODEX_ASSET_DIGEST=${CODEX_RESOLVED_ASSET_DIGEST}" \
            --build-arg "CODEX_BASE_IMAGE_DIGEST=${CODEX_RESOLVED_BASE_IMAGE_DIGEST}" \
            --build-arg "CODEX_DOCKERFILE_SHA256=${CODEX_DOCKERFILE_SHA256}" \
            "$COMPOSE_SERVICE_NAME" >/dev/null 2>&1
    fi
}

init_ssh_key() {
    local key_path="${CODEX_SSH_DIR}/id_ed25519"
    local public_key_path="${key_path}.pub"

    if ! command -v ssh-keygen >/dev/null 2>&1; then
        log::error "ssh-keygen is required on the host to create an agent SSH key"
        exit 1
    fi

    mkdir -p "$CODEX_SSH_DIR"
    chmod 700 "$CODEX_SSH_DIR"

    if [[ ! -f "$key_path" ]]; then
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "cli-agents-codex" >/dev/null
        chmod 600 "$key_path"
        chmod 644 "$public_key_path"
    else
        log::warn "SSH key already exists: $key_path"
    fi

    cat > "${CODEX_SSH_DIR}/config" <<'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new

Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
EOF
    chmod 600 "${CODEX_SSH_DIR}/config"

    printf '\n%sAdd this public key to your GitHub/GitLab repository as a separate deploy key for Codex.%s\n' "$COLOR_HEADER" "$COLOR_RESET"
    printf '%sUse read-only access for clone/pull. Enable write access only if the agent must push.%s\n\n' "$COLOR_TEXT" "$COLOR_RESET"
    cat "$public_key_path"
    printf '\n\n%sPrivate key path:%s %s\n' "$COLOR_HEADER" "$COLOR_RESET" "$key_path"
    printf '%sMounted read-only inside the container as /home/codex/.ssh.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
}

run_new_session() {
    log::info "Found saved auth, starting new Codex session"
    compose_cmd run --rm "$COMPOSE_SERVICE_NAME" --no-alt-screen
}

run_device_auth_then_session() {
    log::warn "No saved auth found, starting device authorization"
    compose_cmd run --rm \
        --entrypoint /bin/sh \
        "$COMPOSE_SERVICE_NAME" \
        -lc 'codex login --device-auth && exec codex --no-alt-screen'
}

run_api_mode() {
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        log::error "OPENAI_API_KEY is not set."
        exit 1
    fi

    log::info "Starting Codex with OPENAI_API_KEY"
    compose_cmd run --rm "$COMPOSE_SERVICE_NAME" --no-alt-screen
}

run_resume_mode() {
    if [[ "$RESUME_VALUE" == "last" ]]; then
        log::info "Resuming latest Codex session in this workspace"
        compose_cmd run --rm "$COMPOSE_SERVICE_NAME" resume --last
        return
    fi

    log::info "Resuming Codex session: $RESUME_VALUE"
    compose_cmd run --rm "$COMPOSE_SERVICE_NAME" resume "$RESUME_VALUE"
}

run_auto_mode() {
    if has_saved_auth; then
        run_new_session
    else
        run_device_auth_then_session
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --init-ssh-key)
                MODE="init-ssh-key"
                shift
                ;;
            --device-auth)
                MODE="device-auth"
                shift
                ;;
            --api)
                MODE="api"
                shift
                ;;
            --resume)
                MODE="resume"
                shift
                if [[ $# -eq 0 ]]; then
                    log::error "--resume requires a session id or 'last'"
                    exit 1
                fi
                RESUME_VALUE="$1"
                shift
                ;;
            --debug)
                DEBUG_ENABLED=1
                shift
                ;;
            --trace)
                TRACE_ENABLED=1
                DEBUG_ENABLED=1
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log::error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

on_error() {
    local exit_code="$1"
    local line_no="$2"

    if [[ "$exit_code" -eq 130 ]]; then
        printf '\n'
        log::warn "Interrupted by user"
        exit 130
    fi

    log::error "Script failed at line ${line_no} with exit code ${exit_code}"
    exit "$exit_code"
}

main() {
    theme::init
    parse_args "$@"

    trap 'on_error $? $LINENO' ERR
    trap 'exit 130' INT

    if [[ "$TRACE_ENABLED" -eq 1 ]]; then
        set -x
    fi

    if [[ "$MODE" == "init-ssh-key" ]]; then
        init_ssh_key
        exit 0
    fi

    ensure_required_files
    ensure_project_layout
    build_image

    case "$MODE" in
        auto)
            run_auto_mode
            ;;
        device-auth)
            run_device_auth_then_session
            ;;
        api)
            run_api_mode
            ;;
        resume)
            run_resume_mode
            ;;
        *)
            log::error "Unsupported mode: $MODE"
            exit 1
            ;;
    esac
}

main "$@"
