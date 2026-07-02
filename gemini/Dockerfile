FROM alpine:3.23

ARG GEMINI_VERSION=latest
ARG GEMINI_PACKAGE_INTEGRITY=
ARG GEMINI_BASE_IMAGE_DIGEST=
ARG GEMINI_DOCKERFILE_SHA256=
ARG TARGETARCH

LABEL org.opencontainers.image.title="gemini-cli" \
      org.opencontainers.image.version="${GEMINI_VERSION}" \
      org.opencontainers.image.source-digest="${GEMINI_PACKAGE_INTEGRITY}" \
      org.opencontainers.image.base.digest="${GEMINI_BASE_IMAGE_DIGEST}" \
      org.opencontainers.image.dockerfile-sha256="${GEMINI_DOCKERFILE_SHA256}"

ENV HOME=/home/gemini \
    XDG_CONFIG_HOME=/home/gemini/.config \
    XDG_CACHE_HOME=/home/gemini/.cache

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
    ca-certificates \
    curl \
    fd \
    ffuf \
    git \
    jq \
    netcat-openbsd \
    nodejs \
    nmap \
    nmap-scripts \
    npm \
    openssh-client \
    proxychains-ng \
    python3 \
    py3-pip \
    ripgrep \
    tar

RUN addgroup -g 1000 -S gemini \
    && adduser -S -D -u 1000 -G gemini -h /home/gemini -s /bin/bash gemini \
    && install -d -m 0755 -o gemini -g gemini /workspace /home/gemini/.gemini /home/gemini/.config /home/gemini/.cache

RUN ln -sf /usr/bin/python3 /usr/local/bin/python

RUN npm config set fund false \
    && npm config set audit false \
    && npm install -g "@google/gemini-cli@${GEMINI_VERSION}" \
    && gemini --version


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
USER gemini
ENTRYPOINT ["gemini"]
