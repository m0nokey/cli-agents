# syntax=docker/dockerfile:1.7

ARG ALPINE_IMAGE=alpine:3.23
FROM ${ALPINE_IMAGE}

ARG CODEX_VERSION=latest
ARG CODEX_TOOL_PROFILE=full
ARG TERRAFORM_VERSION=latest
ARG STERN_VERSION=latest
ARG GITLEAKS_VERSION=latest
ARG CODEX_ASSET_DIGEST=
ARG CODEX_BASE_IMAGE_DIGEST=
ARG CODEX_DOCKERFILE_SHA256=
ARG TARGETARCH

LABEL org.opencontainers.image.title="codex-rust" \
      org.opencontainers.image.version="${CODEX_VERSION}" \
      org.opencontainers.image.tool-profile="${CODEX_TOOL_PROFILE}" \
      org.opencontainers.image.source-digest="${CODEX_ASSET_DIGEST}" \
      org.opencontainers.image.base.digest="${CODEX_BASE_IMAGE_DIGEST}" \
      org.opencontainers.image.dockerfile-sha256="${CODEX_DOCKERFILE_SHA256}"

ENV HOME=/home/codex \
    XDG_CONFIG_HOME=/home/codex/.config \
    XDG_CACHE_HOME=/home/codex/.cache \
    ANSIBLE_HOME=/home/codex/.cache/ansible \
    ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
    ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
    ANSIBLE_RETRY_FILES_ENABLED=false

SHELL ["/bin/ash", "-e", "-u", "-o", "pipefail", "-c"]

RUN common_packages="\
        age \
        bash \
        bind-tools \
        bubblewrap \
        ca-certificates \
        coreutils \
        curl \
        fd \
        findutils \
        git \
        jq \
        make \
        netcat-openbsd \
        nodejs \
        npm \
        openssh-client \
        openssl \
        py3-pip \
        python3 \
        ripgrep \
        rsync \
        sops \
        tar \
        unzip \
        yq-go \
        zip"; \
    case "${CODEX_TOOL_PROFILE}" in \
        core) \
            profile_packages="ansible-core"; \
            ;; \
        full) \
            profile_packages="\
                ansible \
                ansible-lint \
                crane \
                ffuf \
                helm \
                kubectl \
                kubectx \
                kustomize \
                nmap \
                nmap-scripts \
                pre-commit \
                proxychains-ng \
                shellcheck \
                shfmt \
                yamllint"; \
            ;; \
        *) \
            echo "Unsupported CODEX_TOOL_PROFILE: ${CODEX_TOOL_PROFILE}" >&2; \
            exit 1; \
            ;; \
    esac; \
    apk add --no-cache ${common_packages} ${profile_packages}

RUN addgroup -g 1000 -S codex \
    && adduser -S -D -u 1000 -G codex -h /home/codex -s /bin/bash codex \
    && install -d -m 0755 -o codex -g codex \
        /workspace \
        /home/codex/.codex \
        /home/codex/.config \
        /home/codex/.cache \
    && install -d -m 1777 /tmp/ansible-local /tmp/ansible-remote \
    && ln -sf /usr/bin/python3 /usr/local/bin/python

RUN printf '%s\n' \
        '[features]' \
        'code_mode_host = true' \
        > /home/codex/.codex/config.toml \
    && chown codex:codex /home/codex/.codex/config.toml \
    && chmod 0600 /home/codex/.codex/config.toml

RUN --mount=type=cache,id=codex-downloads,target=/var/cache/codex-downloads \
    case "${TARGETARCH}" in \
        amd64) CODEX_ARCH="x86_64-unknown-linux-musl" ;; \
        arm64) CODEX_ARCH="aarch64-unknown-linux-musl" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    if [ "${CODEX_VERSION}" = "latest" ]; then \
        CODEX_TAG="$(curl -fsSL https://api.github.com/repos/openai/codex/releases/latest \
            | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"; \
    else \
        CODEX_TAG="rust-v${CODEX_VERSION}"; \
    fi; \
    CODEX_ASSET="codex-package-${CODEX_ARCH}.tar.gz"; \
    CODEX_ARCHIVE="/var/cache/codex-downloads/${CODEX_TAG}-${CODEX_ASSET}"; \
    if [ ! -s "${CODEX_ARCHIVE}" ]; then \
        curl --fail --location --show-error --proto "=https" --tlsv1.2 \
            "https://github.com/openai/codex/releases/download/${CODEX_TAG}/${CODEX_ASSET}" \
            -o "${CODEX_ARCHIVE}.tmp"; \
        mv "${CODEX_ARCHIVE}.tmp" "${CODEX_ARCHIVE}"; \
    fi; \
    if [ -n "${CODEX_ASSET_DIGEST}" ]; then \
        printf '%s  %s\n' "${CODEX_ASSET_DIGEST#sha256:}" "${CODEX_ARCHIVE}" \
            | sha256sum -c -; \
    fi; \
    CODEX_EXTRACT="$(mktemp -d)"; \
    tar -xzf "${CODEX_ARCHIVE}" -C "${CODEX_EXTRACT}"; \
    test -x "${CODEX_EXTRACT}/bin/codex"; \
    test -x "${CODEX_EXTRACT}/bin/codex-code-mode-host"; \
    install -m 0755 "${CODEX_EXTRACT}/bin/codex" /usr/local/bin/codex; \
    install -m 0755 "${CODEX_EXTRACT}/bin/codex-code-mode-host" \
        /usr/local/bin/codex-code-mode-host; \
    rm -rf "${CODEX_EXTRACT}"

RUN --mount=type=cache,id=terraform-downloads,target=/var/cache/terraform-downloads \
    case "${TARGETARCH}" in \
        amd64) TOOL_ARCH="amd64" ;; \
        arm64) TOOL_ARCH="arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    if [ "${TERRAFORM_VERSION}" = "latest" ]; then \
        TERRAFORM_VERSION="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform \
            | python3 -c 'import json,sys; print(json.load(sys.stdin)["current_version"])')"; \
    fi; \
    TERRAFORM_ASSET="terraform_${TERRAFORM_VERSION}_linux_${TOOL_ARCH}.zip"; \
    TERRAFORM_DIR="/var/cache/terraform-downloads"; \
    if [ ! -s "${TERRAFORM_DIR}/${TERRAFORM_ASSET}" ]; then \
        curl -fsSL \
            "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TERRAFORM_ASSET}" \
            -o "${TERRAFORM_DIR}/${TERRAFORM_ASSET}"; \
    fi; \
    if [ ! -s "${TERRAFORM_DIR}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" ]; then \
        curl -fsSL \
            "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
            -o "${TERRAFORM_DIR}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    fi; \
    grep " ${TERRAFORM_ASSET}\$" \
        "${TERRAFORM_DIR}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
        | sed "s#  #  ${TERRAFORM_DIR}/#" \
        | sha256sum -c -; \
    TERRAFORM_EXTRACT="$(mktemp -d)"; \
    unzip -q "${TERRAFORM_DIR}/${TERRAFORM_ASSET}" -d "${TERRAFORM_EXTRACT}"; \
    install -m 0755 "${TERRAFORM_EXTRACT}/terraform" /usr/local/bin/terraform; \
    rm -rf "${TERRAFORM_EXTRACT}"

RUN --mount=type=cache,id=agent-downloads,target=/var/cache/agent-downloads \
    case "${TARGETARCH}" in \
        amd64) TOOL_ARCH="amd64"; GITLEAKS_ARCH="x64" ;; \
        arm64) TOOL_ARCH="arm64"; GITLEAKS_ARCH="arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    if [ "${STERN_VERSION}" = "latest" ]; then \
        STERN_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/stern/stern/releases/latest)"; \
        STERN_VERSION="$(printf '%s' "${STERN_RELEASE_JSON}" \
            | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"; \
    else \
        STERN_RELEASE_JSON="$(curl -fsSL \
            "https://api.github.com/repos/stern/stern/releases/tags/v${STERN_VERSION}")"; \
    fi; \
    STERN_ASSET="stern_${STERN_VERSION}_linux_${TOOL_ARCH}.tar.gz"; \
    STERN_URL="$(printf '%s' "${STERN_RELEASE_JSON}" \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); n=sys.argv[1]; print(next(a["browser_download_url"] for a in d["assets"] if a["name"] == n))' "${STERN_ASSET}")"; \
    STERN_DIGEST="$(printf '%s' "${STERN_RELEASE_JSON}" \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); n=sys.argv[1]; print(next((a.get("digest") or "") for a in d["assets"] if a["name"] == n))' "${STERN_ASSET}")"; \
    STERN_ARCHIVE="/var/cache/agent-downloads/${STERN_ASSET}"; \
    if [ ! -s "${STERN_ARCHIVE}" ]; then \
        curl -fsSL "${STERN_URL}" -o "${STERN_ARCHIVE}.tmp"; \
        mv "${STERN_ARCHIVE}.tmp" "${STERN_ARCHIVE}"; \
    fi; \
    if [ -n "${STERN_DIGEST}" ]; then \
        printf '%s  %s\n' "${STERN_DIGEST#sha256:}" "${STERN_ARCHIVE}" | sha256sum -c -; \
    fi; \
    STERN_EXTRACT="$(mktemp -d)"; \
    tar -xzf "${STERN_ARCHIVE}" -C "${STERN_EXTRACT}" stern; \
    install -m 0755 "${STERN_EXTRACT}/stern" /usr/local/bin/stern; \
    rm -rf "${STERN_EXTRACT}"; \
    if [ "${GITLEAKS_VERSION}" = "latest" ]; then \
        GITLEAKS_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest)"; \
        GITLEAKS_VERSION="$(printf '%s' "${GITLEAKS_RELEASE_JSON}" \
            | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"; \
    else \
        GITLEAKS_RELEASE_JSON="$(curl -fsSL \
            "https://api.github.com/repos/gitleaks/gitleaks/releases/tags/v${GITLEAKS_VERSION}")"; \
    fi; \
    GITLEAKS_ASSET="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"; \
    GITLEAKS_URL="$(printf '%s' "${GITLEAKS_RELEASE_JSON}" \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); n=sys.argv[1]; print(next(a["browser_download_url"] for a in d["assets"] if a["name"] == n))' "${GITLEAKS_ASSET}")"; \
    GITLEAKS_DIGEST="$(printf '%s' "${GITLEAKS_RELEASE_JSON}" \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); n=sys.argv[1]; print(next((a.get("digest") or "") for a in d["assets"] if a["name"] == n))' "${GITLEAKS_ASSET}")"; \
    GITLEAKS_ARCHIVE="/var/cache/agent-downloads/${GITLEAKS_ASSET}"; \
    if [ ! -s "${GITLEAKS_ARCHIVE}" ]; then \
        curl -fsSL "${GITLEAKS_URL}" -o "${GITLEAKS_ARCHIVE}.tmp"; \
        mv "${GITLEAKS_ARCHIVE}.tmp" "${GITLEAKS_ARCHIVE}"; \
    fi; \
    if [ -n "${GITLEAKS_DIGEST}" ]; then \
        printf '%s  %s\n' "${GITLEAKS_DIGEST#sha256:}" "${GITLEAKS_ARCHIVE}" | sha256sum -c -; \
    fi; \
    GITLEAKS_EXTRACT="$(mktemp -d)"; \
    tar -xzf "${GITLEAKS_ARCHIVE}" -C "${GITLEAKS_EXTRACT}" gitleaks; \
    install -m 0755 "${GITLEAKS_EXTRACT}/gitleaks" /usr/local/bin/gitleaks; \
    rm -rf "${GITLEAKS_EXTRACT}"

WORKDIR /workspace
USER codex
ENTRYPOINT ["codex"]
CMD ["--help"]
