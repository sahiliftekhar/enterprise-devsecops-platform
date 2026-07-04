FROM jenkins/jenkins:lts-jdk21

LABEL maintainer="Iftekhar Shahil"
LABEL org.opencontainers.image.title="Enterprise Jenkins Controller"
LABEL org.opencontainers.image.description="Custom Jenkins Controller for Enterprise DevSecOps Platform"
LABEL org.opencontainers.image.version="1.0.0"

USER root

RUN apt-get update && \
    apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    zip \
    jq \
    python3 \
    python3-pip \
    ca-certificates \
    gnupg \
    lsb-release && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get clean && rm -rf /var/lib/apt/lists/*


# Docker CLI
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | \
gpg --dearmor -o /usr/share/keyrings/docker.gpg && \
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" \
> /etc/apt/sources.list.d/docker.list && \
apt-get update && \
apt-get install -y docker-ce-cli

# AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
-o "awscliv2.zip" && \
unzip awscliv2.zip && \
./aws/install && \
rm -rf aws awscliv2.zip

# Terraform
RUN wget https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip && \
unzip terraform_1.8.5_linux_amd64.zip && \
mv terraform /usr/local/bin/ && \
rm terraform_1.8.5_linux_amd64.zip

# kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
rm kubectl

# Trivy
RUN wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
gpg --dearmor -o /usr/share/keyrings/trivy.gpg && \
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
> /etc/apt/sources.list.d/trivy.list && \
apt-get update && \
apt-get install -y trivy

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

RUN jenkins-plugin-cli \
--plugin-file /usr/share/jenkins/ref/plugins.txt

# -------------------------------------------------------------------
# Install Node.js 20 LTS
# -------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && node --version \
    && npm --version

# -----------------------------
# Install SonarScanner CLI
# -----------------------------
ENV SONAR_SCANNER_VERSION=7.2.0.5079

RUN wget -q https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip \
    && unzip sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip -d /opt \
    && ln -s /opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64/bin/sonar-scanner /usr/local/bin/sonar-scanner \
    && rm sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip

# -------------------------------------------------------------------
# Validate Installed Tools
# -------------------------------------------------------------------
RUN git --version \
 && docker --version \
 && aws --version \
 && terraform version \
 && kubectl version --client \
 && trivy --version \
 && node --version \
 && npm --version

USER jenkins