# syntax=docker/dockerfile:1.7
FROM ghcr.io/coder/code-server:latest@sha256:3623e6362abdec6258472882b06fdeec9d6ce2ad3fda316b3c5d7ed092b89add

ARG NODE_VERSION=24.19.0
ARG NODE_SHA256=14b342e71204f811bde6153be8e04b62aef63c236fef92b55f9c83154b409647
ARG KUBECTL_VERSION=1.34.1
ARG KUBECTL_SHA256=7721f265e18709862655affba5343e85e1980639395d5754473dafaadcaa69e3
ARG HELM_VERSION=3.21.0
ARG HELM_SHA256=0093eb572e3d2380f094df162ddb525e219249de88957afe24cfbb19632acd36
ARG CODEX_VERSION=0.145.0
ARG CLAUDE_CODE_VERSION=2.1.227
ARG OPENCODE_VERSION=1.18.4

USER root

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --show-error --location --output /tmp/node.tar.xz \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum --check --strict \
    && tar --extract --xz --file /tmp/node.tar.xz --directory /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && npm install --global \
        "@openai/codex@${CODEX_VERSION}" \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force

RUN curl --fail --show-error --location --output /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum --check --strict \
    && chmod 0755 /usr/local/bin/kubectl

RUN curl --fail --show-error --location --output /tmp/helm.tar.gz \
        "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    && echo "${HELM_SHA256}  /tmp/helm.tar.gz" | sha256sum --check --strict \
    && tar --extract --gzip --file /tmp/helm.tar.gz --directory /tmp \
    && install --owner=root --group=root --mode=0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64

RUN node --version \
    && npm --version \
    && git --version \
    && kubectl version --client=true \
    && helm version --short \
    && codex --version \
    && claude --version \
    && opencode --version

USER coder
