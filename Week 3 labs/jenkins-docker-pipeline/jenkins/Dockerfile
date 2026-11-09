# Jenkins LTS with the Docker CLI, the Docker Pipeline plugin, and a start-up script that configures
# the URL, an admin user, the registry credential (from REG_USER/REG_PASS) and the menu-board job.
FROM jenkins/jenkins:lts-jdk17
USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl git ca-certificates && rm -rf /var/lib/apt/lists/* \
 && ARCH=$(uname -m) && case "$ARCH" in x86_64) A=x86_64;; aarch64|arm64) A=aarch64;; esac \
 && curl -fsSL "https://download.docker.com/linux/static/stable/$A/docker-27.5.1.tgz" | tar -xz -C /tmp \
 && mv /tmp/docker/docker /usr/local/bin/docker && rm -rf /tmp/docker && docker --version
USER jenkins
RUN jenkins-plugin-cli --plugins "docker-workflow git workflow-aggregator credentials-binding"
# the lab checks out from a bare repository in a volume owned by another user
RUN git config --global --add safe.directory "*"
COPY init.groovy.d/setup.groovy /usr/share/jenkins/ref/init.groovy.d/setup.groovy
COPY job-config.xml /usr/share/jenkins/ref/menu-board-job.xml
# ALLOW_LOCAL_CHECKOUT only matters for the self-contained run that checks out from a local bare repo
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
