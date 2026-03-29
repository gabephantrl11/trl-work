ARG UBUNTU_VERSION=22.04

FROM ubuntu:${UBUNTU_VERSION}

ARG NODE_VERSION
ARG NVM_VERSION
ARG PYTHON_VERSION
ARG UBUNTU_VERSION

ENV NODE_VERSION=${NODE_VERSION}
ENV NVM_VERSION=${NVM_VERSION}
ENV PYTHON_VERSION=${PYTHON_VERSION}
ENV UBUNTU_VERSION=${UBUNTU_VERSION}
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /build

# Copy .env once for proxy config and user creation
COPY .devcontainer/.env /build/.env

# Configure apt proxy if provided (setup-env.sh already verified reachability)
RUN . /build/.env && \
    if [ -n "$APT_PROXY_URL" ]; then \
        echo "Acquire::http::Proxy \"$APT_PROXY_URL\";" > /etc/apt/apt.conf.d/01proxy; \
        echo "Acquire::https::Proxy \"DIRECT\";" >> /etc/apt/apt.conf.d/01proxy; \
    fi

# Install system dependencies
COPY .devcontainer/dependencies.txt dependencies.txt
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    $(cat dependencies.txt | sort -u | xargs) && \
    pip install uv

# Install node tools
ENV NVM_DIR=/usr/local/nvm
RUN mkdir -p $NVM_DIR && \
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install ${NODE_VERSION} && \
    nvm alias default ${NODE_VERSION} && \
    nvm use default
ENV PATH=/usr/local/nvm/versions/node/v${NODE_VERSION}/bin:${PATH}

# Install Docker CLI, git-lfs, and GitHub CLI
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-compose-plugin git-lfs gh && \
    git lfs install

# Add dev user and group
RUN set -a && . /build/.env && set +a && \
    rm -f /build/.env && \
    groupadd -g ${DOCKER_GID} docker || true && \
    groupadd -g ${DEV_GID} -r dev && \
    useradd -u ${DEV_UID} -m -r -g dev -s /bin/bash dev && \
    usermod -aG docker dev && \
    usermod -aG sudo dev && \
    echo "dev:100000:65536" >> /etc/subuid && \
    echo "dev:100000:65536" >> /etc/subgid && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Add development files
COPY .devcontainer/devcontainer.aliases /home/dev/.bash_aliases
RUN touch /home/dev/.hushlogin && \
    git clone https://github.com/magicmonty/bash-git-prompt.git /home/dev/.bash-git-prompt --depth=1 && \
    echo "source ~/.bash-git-prompt/gitprompt.sh" >> /home/dev/.bashrc && \
    echo "export DEVCONTAINER_BUILD_DATE=\"\$(cat /etc/devcontainer-build-date 2>/dev/null || echo 'unknown')\"" >> /home/dev/.bashrc && \
    chown -R dev:dev /home/dev

# Remove apt proxy config so devcontainer features use direct apt
RUN rm -f /etc/apt/apt.conf.d/01proxy

# Capture build date
RUN date -u '+%Y-%m-%d %H:%M:%S UTC' > /etc/devcontainer-build-date

USER dev

# Install Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/dev/.local/bin:${PATH}"
