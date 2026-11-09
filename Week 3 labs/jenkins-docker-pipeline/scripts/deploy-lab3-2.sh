#!/usr/bin/env bash
# Week 3 Lab 3.3 deploy: Jenkins in Docker with the Docker Pipeline plugin, a stored registry credential
# (ID dockerhub-credentials), a pipeline job menu-board that builds, smoke-tests, tags :BUILD_NUMBER
# and :latest and pushes. By default it pushes to a LOCAL registry container so the lab needs no account;
# set REGISTRY_HOST=index.docker.io REG_USER=<dockerhub user> REG_PASS=<access token> for Docker Hub.
#   deploy-lab3-2.sh            then open http://localhost:8080 (admin / admin)
set -euo pipefail
D=$(cd "$(dirname "$0")/.." && pwd)
REG_USER="${REG_USER:-brewer}"; REG_PASS="${REG_PASS:-$(openssl rand -hex 12)}"
# a rerun against a running Jenkins keeps the credential that Jenkins and the registry already share
if docker ps --format '{{.Names}}' | grep -qx jenkins; then
  REG_USER=$(docker exec jenkins printenv REG_USER); REG_PASS=$(docker exec jenkins printenv REG_PASS)
fi
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5005}"        # the local registry as the Docker DAEMON reaches it (host port); it does the push
IMAGE_NAME="${IMAGE_NAME:-$REGISTRY_HOST/bonneville/menu-board}"
REGISTRY_URL="${REGISTRY_URL:-http://$REGISTRY_HOST}"
[ "$REGISTRY_HOST" = "index.docker.io" ] && { IMAGE_NAME="${IMAGE_NAME_HUB:-$REG_USER/menu-board}"; REGISTRY_URL="https://index.docker.io/v1/"; }
echo "== Part 0: lab network, local registry, Jenkins image"
docker network inspect brewlab >/dev/null 2>&1 || docker network create brewlab >/dev/null
if [ "$REGISTRY_HOST" = "localhost:5005" ]; then
  if ! docker ps --format '{{.Names}}' | grep -qx registry; then
    docker pull -q httpd:2.4-alpine >/dev/null; docker pull -q registry:2 >/dev/null
    T=$(mktemp -d); docker run --rm --entrypoint htpasswd httpd:2.4-alpine -Bbn "$REG_USER" "$REG_PASS" > "$T/htpasswd"
    # host port 5005: macOS AirPlay Receiver listens on 5000 and Lab 4.3 may hold 5001. Inside the lab network the registry is still registry:5000
    docker run -d --name registry --network brewlab -p 5005:5000 -v "$T/htpasswd:/auth/htpasswd:ro" \
      -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=brewlab -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd registry:2 >/dev/null
  fi
fi
docker build -q -t it360-jenkins "$D/jenkins" >/dev/null 2>&1 || docker build -t it360-jenkins "$D/jenkins" | tail -5
echo "== Part 1: a git repository Jenkins can check out (bare repo in a volume)"
docker volume inspect brewlab-git >/dev/null 2>&1 || docker volume create brewlab-git >/dev/null
docker run --rm -v brewlab-git:/git -v "$D/menu-board:/src:ro" --entrypoint sh alpine/git:latest -c '
  set -e; cd /git; [ -d menu-board.git ] || git init -q --bare menu-board.git; git -C menu-board.git symbolic-ref HEAD refs/heads/main
  rm -rf /tmp/w && git clone -q /git/menu-board.git /tmp/w && cp -r /src/. /tmp/w/ && cd /tmp/w
  git config user.email lab@example.com; git config user.name lab; git checkout -q -B main
  git add -A && (git commit -q -m "Menu board v1" || true) && git push -q origin main' >/dev/null
echo "== Part 2 and 3: Jenkins with Docker access; the start-up script sets the URL, admin/admin, credential dockerhub-credentials and the job"
if ! docker ps --format '{{.Names}}' | grep -qx jenkins; then
  docker run -d --name jenkins --network brewlab -p 8080:8080 -v /var/run/docker.sock:/var/run/docker.sock -v brewlab-git:/git:ro \
    $( [ "$(uname)" = Linux ] && echo "--group-add $(stat -c %g /var/run/docker.sock)" ) \
    -e REGISTRY_URL="$REGISTRY_URL" -e IMAGE_NAME="$IMAGE_NAME" -e SMOKE_NET=brewlab -e REG_USER="$REG_USER" -e REG_PASS="$REG_PASS" -e REPO_URL="file:///git/menu-board.git" it360-jenkins >/dev/null
fi
docker exec -u root jenkins sh -c 'chmod 666 /var/run/docker.sock' 2>/dev/null || true
for i in $(seq 1 90); do curl -s -o /dev/null -w '%{http_code}' -u admin:admin http://localhost:8080/api/json | grep -q 200 && break; sleep 3; done
docker exec jenkins sh -c 'curl -s -o /tmp/cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar'
docker exec jenkins sh -c 'java -jar /tmp/cli.jar -s http://localhost:8080/ -auth admin:admin list-jobs; java -jar /tmp/cli.jar -s http://localhost:8080/ -auth admin:admin list-credentials system::system::jenkins 2>/dev/null | grep -i dockerhub'
echo "== Part 4: build twice and prove the secret never appears"
for n in 1 2; do
  [ $n = 2 ] && docker run --rm -v brewlab-git:/git --entrypoint sh alpine/git:latest -c 'rm -rf /tmp/w && git clone -q -b main /git/menu-board.git /tmp/w && cd /tmp/w && sed -i "s|</ul>|<li>Timp Trail IPA 6.5%</li></ul>|" index.html && git config user.email lab@example.com && git config user.name lab && git commit -qam "Add third beer" && git push -q origin main' >/dev/null
  docker exec jenkins sh -c 'java -jar /tmp/cli.jar -s http://localhost:8080/ -auth admin:admin build menu-board -s -v' | tail -25 | sed 's/\x1b\[[0-9;]*m//g'
done
echo "-- grep the console logs for the secret:"; docker exec jenkins sh -c "grep -rl '$REG_PASS' /var/jenkins_home/jobs/menu-board/builds/ 2>/dev/null" | grep . && echo 'LEAK' || echo "no build log contains the password (Jenkins prints ******** in its place)"
echo "== Registry tags now:"
[ "$REGISTRY_HOST" = "localhost:5005" ] && curl -s -u "$REG_USER:$REG_PASS" http://localhost:5005/v2/bonneville/menu-board/tags/list || echo "(check Docker Hub → Repositories → menu-board → Tags)"
echo "REG_USER=$REG_USER REG_PASS=$REG_PASS  (local registry only; Jenkins UI: http://localhost:8080 admin/admin)"
echo "LAB3_2_DEPLOY_DONE"
