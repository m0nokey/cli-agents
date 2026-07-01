#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

GEMINI_IMAGE_NAME="${GEMINI_IMAGE_NAME:-local/gemini-cli:latest}"
GEMINI_PACKAGE_NAME="${GEMINI_PACKAGE_NAME:-@google/gemini-cli}"
GEMINI_VERSION="${GEMINI_VERSION:-latest}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.1-flash-lite}"
GEMINI_RUNNER_DIR="${GEMINI_RUNNER_DIR:-$SCRIPT_DIR}"
GEMINI_WORKSPACE_DIR="${GEMINI_WORKSPACE_DIR:-${GEMINI_RUNNER_DIR}/workspace}"
PROJECT_GEMINI_DIR_NAME="${PROJECT_GEMINI_DIR_NAME:-.gemini}"
PROJECT_GEMINI_DIR="${GEMINI_STATE_DIR:-${GEMINI_RUNNER_DIR}/${PROJECT_GEMINI_DIR_NAME}}"
GEMINI_SSH_DIR="${GEMINI_SSH_DIR:-${GEMINI_RUNNER_DIR}/.ssh}"
GEMINI_SECRETS_DIR="${GEMINI_SECRETS_DIR:-${GEMINI_RUNNER_DIR}/.secrets}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-${GEMINI_RUNNER_DIR}/Dockerfile}"
COMPOSE_FILE_PATH="${COMPOSE_FILE_PATH:-${GEMINI_RUNNER_DIR}/compose.yml}"
COMPOSE_SERVICE_NAME="${COMPOSE_SERVICE_NAME:-gemini}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
export GEMINI_IMAGE_NAME
export GEMINI_MODEL
export GEMINI_RUNNER_DIR
export GEMINI_WORKSPACE_DIR
export GEMINI_STATE_DIR="$PROJECT_GEMINI_DIR"
export GEMINI_SSH_DIR
export GEMINI_SECRETS_DIR

MODE="run"
DEBUG_ENABLED=0
TRACE_ENABLED=0
GEMINI_RESOLVED_VERSION=""
GEMINI_PACKAGE_INTEGRITY=""
GEMINI_BASE_IMAGE_REF=""
GEMINI_BASE_IMAGE_DIGEST=""
GEMINI_DOCKERFILE_SHA256=""
GEMINI_ARGS=()

COLOR_RESET=''
COLOR_TEXT=''
COLOR_HEADER=''
COLOR_LINE=''
COLOR_INFO=''
COLOR_WARN=''
COLOR_ERROR=''
COLOR_DEBUG=''

init_theme() {
    if [[ -t 1 ]]; then
        COLOR_RESET=$'\033[0m'
        COLOR_TEXT=$'\033[97m'
        COLOR_HEADER=$'\033[38;5;183m'
        COLOR_LINE=$'\033[38;5;117m'
        COLOR_INFO=$'\033[38;5;117m'
        COLOR_WARN=$'\033[38;5;221m'
        COLOR_ERROR=$'\033[38;5;203m'
        COLOR_DEBUG=$'\033[38;5;147m'
    fi
}

log_info() { printf '%s[INFO]%s %s%s%s\n' "$COLOR_INFO" "$COLOR_RESET" "$COLOR_TEXT" "$*" "$COLOR_RESET"; }
log_warn() { printf '%s[WARN]%s %s%s%s\n' "$COLOR_WARN" "$COLOR_RESET" "$COLOR_TEXT" "$*" "$COLOR_RESET"; }
log_error() { printf '%s[ERROR]%s %s%s%s\n' "$COLOR_ERROR" "$COLOR_RESET" "$COLOR_TEXT" "$*" "$COLOR_RESET" >&2; }
log_debug() {
    if [[ "$DEBUG_ENABLED" -eq 1 || "$TRACE_ENABLED" -eq 1 ]]; then
        printf '%s[DEBUG]%s %s%s%s\n' "$COLOR_DEBUG" "$COLOR_RESET" "$COLOR_TEXT" "$*" "$COLOR_RESET"
    fi
}

show_help() {
    printf '%sUsage%s\n' "$COLOR_HEADER" "$COLOR_RESET"
    printf '    %s./%s%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --init-ssh-key%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --login%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --debug%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --trace%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '    %s./%s --help%s\n' "$COLOR_LINE" "$SCRIPT_NAME" "$COLOR_RESET"
    printf '\n'
    printf '%sBehavior%s\n' "$COLOR_HEADER" "$COLOR_RESET"
    printf '    %s- No arguments start Gemini when saved auth exists.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- If saved auth does not exist, auto mode starts Google login first.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Mounts ./workspace as /workspace by default.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Keeps Docker files and .gemini state outside /workspace.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Uses normal Docker bridge networking; Google auth uses browser auth-code flow.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- Rebuilds only when npm package integrity/version or Alpine base digest changes.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
    printf '    %s- --init-ssh-key creates a per-agent deploy key in ./.ssh.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
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

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        log_error "Required file not found: $path"
        exit 1
    fi
}

ensure_layout() {
    mkdir -p "$GEMINI_WORKSPACE_DIR" "$PROJECT_GEMINI_DIR" "$GEMINI_SSH_DIR" "$GEMINI_SECRETS_DIR"
}


http_get() {
    local url="$1"
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsSL --connect-timeout 10 --max-time 30 "$url"
}

package_registry_name() {
    printf '%s' "${GEMINI_PACKAGE_NAME//@/%40}" | sed 's#/#%2F#g'
}

resolve_npm_metadata() {
    local encoded json version integrity
    encoded="$(package_registry_name)"

    if [[ "$GEMINI_VERSION" == "latest" ]]; then
        json="$(http_get "https://registry.npmjs.org/${encoded}/latest" 2>/dev/null || true)"
    else
        json="$(http_get "https://registry.npmjs.org/${encoded}/${GEMINI_VERSION}" 2>/dev/null || true)"
    fi

    if [[ -n "$json" ]] && command -v python3 >/dev/null 2>&1; then
        version="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version", ""))' 2>/dev/null || true)"
        integrity="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("dist", {}).get("integrity", ""))' 2>/dev/null || true)"
    fi

    GEMINI_RESOLVED_VERSION="${version:-$GEMINI_VERSION}"
    GEMINI_PACKAGE_INTEGRITY="${integrity:-}"
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

docker_hub_manifest_digest() {
    local image_ref="$1" repo tag token digest
    [[ "$image_ref" == *:* ]] || return 0
    repo="${image_ref%:*}"
    tag="${image_ref##*:}"
    if [[ "$repo" != */* ]]; then
        repo="library/${repo}"
    fi

    token="$(curl -fsSL --connect-timeout 10 --max-time 30 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" | sed -E 's/.*"token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' 2>/dev/null || true)"
    [[ -n "$token" ]] || return 0

    digest="$(curl -fsSI --connect-timeout 10 --max-time 30 -H "Authorization: Bearer ${token}" -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://registry-1.docker.io/v2/${repo}/manifests/${tag}" | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:" { print $2; exit }' 2>/dev/null || true)"
    printf '%s' "$digest"
}

resolve_base_image_digest() {
    local image_ref="$1" digest=""
    [[ -n "$image_ref" ]] || return 0

    if command -v "$DOCKER_BIN" >/dev/null 2>&1; then
        digest="$(docker_cmd buildx imagetools inspect "$image_ref" 2>/dev/null | awk '/^Digest:/ { print $2; exit }' || true)"
        if [[ -z "$digest" ]]; then
            digest="$(docker_cmd manifest inspect "$image_ref" 2>/dev/null | grep -m1 '"digest"' | sed -E 's/.*"digest"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
        fi
    fi

    if [[ -z "$digest" && "$image_ref" != *.*/* ]]; then
        digest="$(docker_hub_manifest_digest "$image_ref")"
    fi

    printf '%s' "$digest"
}

resolve_build_metadata() {
    resolve_npm_metadata
    GEMINI_BASE_IMAGE_REF="$(dockerfile_base_image_ref)"
    GEMINI_BASE_IMAGE_DIGEST="$(resolve_base_image_digest "$GEMINI_BASE_IMAGE_REF")"
    GEMINI_DOCKERFILE_SHA256="$(file_sha256 "$DOCKERFILE_PATH" 2>/dev/null || true)"
}

local_image_label() {
    local label="$1"
    docker_cmd image inspect "$GEMINI_IMAGE_NAME" --format "{{ index .Config.Labels \"$label\" }}" 2>/dev/null || true
}

gemini_image_is_current() {
    local local_version local_integrity local_base_digest local_dockerfile_sha
    local_version="$(local_image_label 'org.opencontainers.image.version')"
    local_integrity="$(local_image_label 'org.opencontainers.image.source-digest')"
    local_base_digest="$(local_image_label 'org.opencontainers.image.base.digest')"
    local_dockerfile_sha="$(local_image_label 'org.opencontainers.image.dockerfile-sha256')"

    if [[ -n "$GEMINI_PACKAGE_INTEGRITY" ]]; then
        [[ "$local_integrity" == "$GEMINI_PACKAGE_INTEGRITY" ]] || return 1
    else
        [[ "$local_version" == "$GEMINI_RESOLVED_VERSION" ]] || return 1
    fi

    if [[ -n "$GEMINI_BASE_IMAGE_DIGEST" ]]; then
        [[ "$local_base_digest" == "$GEMINI_BASE_IMAGE_DIGEST" ]] || return 1
    fi

    if [[ -n "$GEMINI_DOCKERFILE_SHA256" ]]; then
        [[ "$local_dockerfile_sha" == "$GEMINI_DOCKERFILE_SHA256" ]] || return 1
    fi
}

build_image() {
    resolve_build_metadata

    log_info "Gemini CLI package: ${GEMINI_PACKAGE_NAME}@${GEMINI_RESOLVED_VERSION}"
    [[ -n "$GEMINI_PACKAGE_INTEGRITY" ]] && log_debug "Gemini npm integrity: ${GEMINI_PACKAGE_INTEGRITY}"
    [[ -n "$GEMINI_BASE_IMAGE_DIGEST" ]] && log_debug "Base image ${GEMINI_BASE_IMAGE_REF}: ${GEMINI_BASE_IMAGE_DIGEST}"
    [[ -n "$GEMINI_DOCKERFILE_SHA256" ]] && log_debug "Dockerfile sha256: ${GEMINI_DOCKERFILE_SHA256}"

    if [[ "${GEMINI_FORCE_BUILD:-0}" != "1" ]] && gemini_image_is_current; then
        log_info "Docker image is current, skipping build: $GEMINI_IMAGE_NAME"
        return
    fi

    log_info "Building Docker image: $GEMINI_IMAGE_NAME"
    if [[ "$DEBUG_ENABLED" -eq 1 || "$TRACE_ENABLED" -eq 1 ]]; then
        compose_cmd build --build-arg "GEMINI_VERSION=${GEMINI_RESOLVED_VERSION}" --build-arg "GEMINI_PACKAGE_INTEGRITY=${GEMINI_PACKAGE_INTEGRITY}" --build-arg "GEMINI_BASE_IMAGE_DIGEST=${GEMINI_BASE_IMAGE_DIGEST}" --build-arg "GEMINI_DOCKERFILE_SHA256=${GEMINI_DOCKERFILE_SHA256}" "$COMPOSE_SERVICE_NAME"
    else
        compose_cmd build --build-arg "GEMINI_VERSION=${GEMINI_RESOLVED_VERSION}" --build-arg "GEMINI_PACKAGE_INTEGRITY=${GEMINI_PACKAGE_INTEGRITY}" --build-arg "GEMINI_BASE_IMAGE_DIGEST=${GEMINI_BASE_IMAGE_DIGEST}" --build-arg "GEMINI_DOCKERFILE_SHA256=${GEMINI_DOCKERFILE_SHA256}" "$COMPOSE_SERVICE_NAME" >/dev/null 2>&1
    fi
}

has_saved_auth() {
    [[ -f "${PROJECT_GEMINI_DIR}/tokens.json" || -f "${PROJECT_GEMINI_DIR}/oauth_creds.json" || -f "${PROJECT_GEMINI_DIR}/settings.json" ]]
}

init_ssh_key() {
    local key_path="${GEMINI_SSH_DIR}/id_ed25519"
    local public_key_path="${key_path}.pub"

    if ! command -v ssh-keygen >/dev/null 2>&1; then
        log_error "ssh-keygen is required on the host to create an agent SSH key"
        exit 1
    fi

    mkdir -p "$GEMINI_SSH_DIR"
    chmod 700 "$GEMINI_SSH_DIR"

    if [[ ! -f "$key_path" ]]; then
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "cli-agents-gemini" >/dev/null
        chmod 600 "$key_path"
        chmod 644 "$public_key_path"
    else
        log_warn "SSH key already exists: $key_path"
    fi

    cat > "${GEMINI_SSH_DIR}/config" <<'EOF'
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
    chmod 600 "${GEMINI_SSH_DIR}/config"

    printf '\n%sAdd this public key to your GitHub/GitLab repository as a separate deploy key for Gemini.%s\n' "$COLOR_HEADER" "$COLOR_RESET"
    printf '%sUse read-only access for clone/pull. Enable write access only if the agent must push.%s\n\n' "$COLOR_TEXT" "$COLOR_RESET"
    cat "$public_key_path"
    printf '\n\n%sPrivate key path:%s %s\n' "$COLOR_HEADER" "$COLOR_RESET" "$key_path"
    printf '%sMounted read-only inside the container as /home/gemini/.ssh.%s\n' "$COLOR_TEXT" "$COLOR_RESET"
}

run_gemini() {
    log_info "Starting Gemini CLI"
    if [[ "${#GEMINI_ARGS[@]}" -gt 0 ]]; then
        compose_cmd run --rm "$COMPOSE_SERVICE_NAME" "${GEMINI_ARGS[@]}"
    else
        compose_cmd run --rm "$COMPOSE_SERVICE_NAME"
    fi
}

run_auto() {
    if has_saved_auth; then
        run_gemini
        return
    fi

    log_warn "No saved Gemini auth found in ${PROJECT_GEMINI_DIR}"
    log_warn "Starting Google login first"
    run_login
}

run_login() {
    log_warn "Starting Gemini Google login"
    log_warn "If browser does not open automatically, copy the printed Google login URL into your host browser"
    compose_cmd run --rm "$COMPOSE_SERVICE_NAME"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --init-ssh-key)
                MODE="init-ssh-key"
                shift
                ;;
            --login|--auth)
                MODE="login"
                shift
                ;;
            --debug)
                DEBUG_ENABLED=1
                GEMINI_ARGS+=("-d")
                shift
                ;;
            --trace)
                TRACE_ENABLED=1
                DEBUG_ENABLED=1
                set -x
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --)
                shift
                GEMINI_ARGS+=("$@")
                break
                ;;
            *)
                GEMINI_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

on_error() {
    local exit_code="$1"
    local line_no="$2"
    if [[ "$exit_code" -eq 130 ]]; then
        printf '\n'
        log_warn "Interrupted by user"
        exit 130
    fi
    log_error "Script failed at line ${line_no} with exit code ${exit_code}"
    exit "$exit_code"
}

main() {
    init_theme
    parse_args "$@"
    trap 'on_error $? $LINENO' ERR
    trap 'exit 130' INT

    if [[ "$MODE" == "init-ssh-key" ]]; then
        init_ssh_key
        exit 0
    fi

    require_file "$DOCKERFILE_PATH"
    require_file "$COMPOSE_FILE_PATH"
    ensure_layout
    build_image

    case "$MODE" in
        login)
            run_login
            ;;
        run)
            run_auto
            ;;
        *)
            log_error "Unsupported mode: $MODE"
            exit 1
            ;;
    esac
}

main "$@"
