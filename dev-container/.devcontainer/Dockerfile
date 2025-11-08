# Start from Ubuntu base image
FROM ubuntu:22.04

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Configure apt and install packages
RUN apt-get update \
    && apt-get -y install --no-install-recommends \
        apt-utils \
        dialog \
        ca-certificates \
        curl \
        git \
        wget \
        gnupg2 \
        lsb-release \
        software-properties-common \
        build-essential \
        vim \
        nano \
        sudo \
        openssh-client \
        less \
        iproute2 \
        procps \
        lsof \
        htop \
        net-tools \
        psmisc \
        strace \
        manpages \
        manpages-dev \
        unzip \
        zip \
        jq \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install Java 21 (Amazon Corretto)
RUN wget -O- https://apt.corretto.aws/corretto.key | apt-key add - \
    && add-apt-repository 'deb https://apt.corretto.aws stable main' \
    && apt-get update \
    && apt-get install -y java-21-amazon-corretto-jdk \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto
ENV PATH="$JAVA_HOME/bin:$PATH"

# Install Python 3.11+
RUN add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y \
        python3.12 \
        python3.12-venv \
        python3.12-dev \
        python3-pip \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1

# Install uv (Python package installer)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"

# Install Go (latest stable)
RUN wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz \
    && rm go1.22.0.linux-amd64.tar.gz

ENV PATH="/usr/local/go/bin:$PATH"
ENV GOPATH="/home/$USERNAME/go"
ENV PATH="$GOPATH/bin:$PATH"

# Install Node.js (latest LTS) and npm
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install TypeScript globally
RUN npm install -g typescript ts-node @types/node

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Install Starship prompt
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

# Configure Starship for bash
RUN echo 'eval "$(starship init bash)"' >> /home/$USERNAME/.bashrc

# Set up user permissions
RUN mkdir -p /home/$USERNAME/go \
    && chown -R $USERNAME:$USERNAME /home/$USERNAME

# Copy setup script
COPY .devcontainer/setup.sh /home/$USERNAME/.devcontainer/setup.sh
RUN chmod +x /home/$USERNAME/.devcontainer/setup.sh

# Switch back to dialog for any ad-hoc use of apt-get
ENV DEBIAN_FRONTEND=dialog

# Set the default user
USER $USERNAME
WORKDIR /home/$USERNAME

# Verify installations
RUN java -version \
    && python --version \
    && go version \
    && node --version \
    && npm --version \
    && tsc --version \
    && aws --version \
    && starship --version
