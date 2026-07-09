ARG ALPINE_IMAGE=alpine:3.23
FROM ${ALPINE_IMAGE}

ARG CODEX_VERSION=latest
ARG TERRAFORM_VERSION=latest
ARG STERN_VERSION=latest
ARG GITLEAKS_VERSION=latest
ARG CODEX_ASSET_DIGEST=
ARG CODEX_BASE_IMAGE_DIGEST=
ARG CODEX_DOCKERFILE_SHA256=
ARG TARGETARCH

LABEL org.opencontainers.image.title="codex-rust" \
      org.opencontainers.image.version="${CODEX_VERSION}" \
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

RUN apk add --no-cache \
    bash \
    age \
    zip \
    yq-go \
    unzip \
    rsync \
    findutils \
    coreutils \
    bind-tools \
    ansible \
    ansible-lint \
    bubblewrap \
    ca-certificates \
    curl \
    fd \
    ffuf \
    git \
    helm \
    jq \
    kubectl \
    kubectx \
    kustomize \
    make \
    netcat-openbsd \
    nodejs \
    nmap \
    nmap-scripts \
    npm \
    openssl \
    openssh-client \
    pre-commit \
    proxychains-ng \
    python3 \
    py3-pip \
    crane \
    ripgrep \
    shellcheck \
    shfmt \
    sops \
    tar \
    yamllint

RUN addgroup -g 1000 -S codex \
    && adduser -S -D -u 1000 -G codex -h /home/codex -s /bin/bash codex \
    && install -d -m 0755 -o codex -g codex /workspace /home/codex/.codex /home/codex/.config /home/codex/.cache

RUN ln -sf /usr/bin/python3 /usr/local/bin/python

RUN case "${TARGETARCH}" in \
        amd64) CODEX_ARCH="x86_64-unknown-linux-musl" ;; \
        arm64) CODEX_ARCH="aarch64-unknown-linux-musl" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    if [ "${CODEX_VERSION}" = "latest" ]; then \
      CODEX_TAG="$(curl -fsSL https://api.github.com/repos/openai/codex/releases?per_page=1 | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"; \
    else \
      CODEX_TAG="rust-v${CODEX_VERSION}"; \
    fi && \
    test -n "${CODEX_TAG}" && \
    curl --fail --location --show-error --proto "=https" --tlsv1.2 "https://github.com/openai/codex/releases/download/${CODEX_TAG}/codex-${CODEX_ARCH}.tar.gz" -o /tmp/codex.tar.gz && \
    if [ -n "${CODEX_ASSET_DIGEST}" ]; then \
      printf "%s  %s\n" "${CODEX_ASSET_DIGEST#sha256:}" /tmp/codex.tar.gz | sha256sum -c -; \
    fi && \
    tar -xzf /tmp/codex.tar.gz -C /tmp && \
    install -m 0755 "/tmp/codex-${CODEX_ARCH}" /usr/local/bin/codex && \
    rm -f /tmp/codex.tar.gz "/tmp/codex-${CODEX_ARCH}"


RUN set -eu; \
    case "${TARGETARCH}" in \
        amd64) TOOL_ARCH="amd64"; GITLEAKS_ARCH="x64" ;; \
        arm64) TOOL_ARCH="arm64"; GITLEAKS_ARCH="arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    github_asset_field() { \
        python3 -c 'import json,sys; data=json.load(sys.stdin); name=sys.argv[1]; field=sys.argv[2]; print(next(asset.get(field, "") for asset in data["assets"] if asset["name"] == name))' "$1" "$2"; \
    }; \
    if [ "${TERRAFORM_VERSION}" = "latest" ]; then \
        TERRAFORM_VERSION="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | python3 -c 'import json,sys; print(json.load(sys.stdin)["current_version"])')"; \
    fi; \
    TERRAFORM_ASSET="terraform_${TERRAFORM_VERSION}_linux_${TOOL_ARCH}.zip"; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TERRAFORM_ASSET}" -o "/tmp/${TERRAFORM_ASSET}"; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" -o /tmp/terraform_SHA256SUMS; \
    grep " ${TERRAFORM_ASSET}\$" /tmp/terraform_SHA256SUMS | sed 's#  #  /tmp/#' | sha256sum -c -; \
    unzip -q "/tmp/${TERRAFORM_ASSET}" -d /tmp/terraform; \
    install -m 0755 /tmp/terraform/terraform /usr/local/bin/terraform; \
    rm -rf /tmp/terraform "/tmp/${TERRAFORM_ASSET}" /tmp/terraform_SHA256SUMS; \
    if [ "${STERN_VERSION}" = "latest" ]; then \
        STERN_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/stern/stern/releases/latest)"; \
        STERN_VERSION="$(printf '%s' "${STERN_RELEASE_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"; \
    else \
        STERN_RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/stern/stern/releases/tags/v${STERN_VERSION}")"; \
    fi; \
    STERN_ASSET="stern_${STERN_VERSION}_linux_${TOOL_ARCH}.tar.gz"; \
    STERN_URL="$(printf '%s' "${STERN_RELEASE_JSON}" | github_asset_field "${STERN_ASSET}" browser_download_url)"; \
    STERN_DIGEST="$(printf '%s' "${STERN_RELEASE_JSON}" | github_asset_field "${STERN_ASSET}" digest)"; \
    test -n "${STERN_URL}" && test -n "${STERN_DIGEST}"; \
    curl -fsSL "${STERN_URL}" -o /tmp/stern.tar.gz; \
    printf "%s  %s\n" "${STERN_DIGEST#sha256:}" /tmp/stern.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/stern.tar.gz -C /tmp stern; \
    install -m 0755 /tmp/stern /usr/local/bin/stern; \
    rm -f /tmp/stern.tar.gz /tmp/stern; \
    if [ "${GITLEAKS_VERSION}" = "latest" ]; then \
        GITLEAKS_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest)"; \
        GITLEAKS_VERSION="$(printf '%s' "${GITLEAKS_RELEASE_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"; \
    else \
        GITLEAKS_RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/gitleaks/gitleaks/releases/tags/v${GITLEAKS_VERSION}")"; \
    fi; \
    GITLEAKS_ASSET="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"; \
    GITLEAKS_URL="$(printf '%s' "${GITLEAKS_RELEASE_JSON}" | github_asset_field "${GITLEAKS_ASSET}" browser_download_url)"; \
    GITLEAKS_DIGEST="$(printf '%s' "${GITLEAKS_RELEASE_JSON}" | github_asset_field "${GITLEAKS_ASSET}" digest)"; \
    test -n "${GITLEAKS_URL}" && test -n "${GITLEAKS_DIGEST}"; \
    curl -fsSL "${GITLEAKS_URL}" -o /tmp/gitleaks.tar.gz; \
    printf "%s  %s\n" "${GITLEAKS_DIGEST#sha256:}" /tmp/gitleaks.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks; \
    install -m 0755 /tmp/gitleaks /usr/local/bin/gitleaks; \
    rm -f /tmp/gitleaks.tar.gz /tmp/gitleaks

WORKDIR /workspace
USER codex
ENTRYPOINT ["codex"]
CMD ["--help"]
