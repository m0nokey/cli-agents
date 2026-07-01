FROM alpine:3.23

ARG CODEX_VERSION=latest
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
    ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
    ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
    ANSIBLE_RETRY_FILES_ENABLED=false

RUN apk add --no-cache \
    bash \
    zip \
    yq-go \
    unzip \
    rsync \
    findutils \
    coreutils \
    bind-tools \
    ansible \
    bubblewrap \
    ca-certificates \
    curl \
    fd \
    git \
    jq \
    nodejs \
    npm \
    openssh-client \
    python3 \
    py3-pip \
    ripgrep \
    tar

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
        amd64) TOOL_ARCH="amd64" ;; \
        arm64) TOOL_ARCH="arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    TERRAFORM_VERSION="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | python3 -c 'import json,sys; print(json.load(sys.stdin)["current_version"])')"; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TOOL_ARCH}.zip" -o /tmp/terraform.zip; \
    unzip -q /tmp/terraform.zip -d /tmp/terraform; \
    install -m 0755 /tmp/terraform/terraform /usr/local/bin/terraform; \
    rm -rf /tmp/terraform /tmp/terraform.zip

WORKDIR /workspace
USER codex
ENTRYPOINT ["codex"]
CMD ["--help"]
