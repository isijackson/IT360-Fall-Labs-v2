#!/usr/bin/env bash
# Week 2 Lab 2.2 deploy: GitHub repository canyon-schedule with the Express app, Azure resource group,
# Free F1 Linux plan and Node 20 Web App, GitHub Actions deployment wired by the Azure CLI, then the
# live-change drill timed from push to live.
#   deploy-lab2.sh <TEAM>          (gh and az must be signed in; LOCATION env optional, default eastus)
# App Service quota is per region and per SKU: the Ensign College subscription has 0 F1 and 0 B1 in eastus but F1 in
# westus2, so run LOCATION=westus2 bash scripts/deploy-lab2.sh <team> there. Probe a region with:
#   az appservice plan create -g probe-rg -n probe -l <region> --is-linux --sku F1
set -euo pipefail
TEAM="${1:?usage: $0 <team-suffix>}"; LOC="${LOCATION:-eastus}"; D=$(cd "$(dirname "$0")/.." && pwd)
RG=canyon-soccer-rg; PLAN=canyon-asp; APP="canyon-schedule-$TEAM"; REPO="canyon-schedule"
GH_USER=$(gh api user --jq .login)
echo "== Part 2: repository and app"
W=$(mktemp -d)
if gh repo view "$GH_USER/$REPO" >/dev/null 2>&1; then           # repo exists (a rerun): work on a clone so histories never diverge
  git clone -q "https://github.com/$GH_USER/$REPO.git" "$W"; cp -r "$D/canyon-schedule/." "$W/"; cd "$W"
  git add -A; git commit -qm "Sync schedule site from the lab folder" 2>/dev/null || true; git push -q origin main
else
  cp -r "$D/canyon-schedule/." "$W/"; cd "$W"; git init -q -b main; git add -A; git commit -qm "Initial schedule site"
  gh repo create "$REPO" --public --source=. --push >/dev/null
fi
npm install --silent >/dev/null; npm test >/dev/null && echo "app starts locally (npm test)"
echo "repo: https://github.com/$GH_USER/$REPO"
echo "== Part 1: Azure resources"
az group create -n "$RG" -l "$LOC" -o none
# Free F1 first; some subscriptions (the Ensign College school card, for one) have an F1 quota of 0, so fall back to Basic B1 (about $13/month, delete it after class)
SKU="${SKU:-F1}"
az appservice plan show -g "$RG" -n "$PLAN" -o none 2>/dev/null || az appservice plan create -g "$RG" -n "$PLAN" -l "$LOC" --is-linux --sku "$SKU" -o none 2>/tmp/plan.err \
  || { grep -q "quota" /tmp/plan.err && echo "F1 quota is 0 in $LOC, using B1" && az appservice plan create -g "$RG" -n "$PLAN" -l "$LOC" --is-linux --sku B1 -o none; }
# newest Node LTS the platform offers (NODE:20-lts was retired in October 2026)
RUNTIME=$(az webapp list-runtimes --os-type linux -o tsv | grep -E '^NODE:[0-9]+-lts$' | sort -t: -k2 -V | tail -1); echo "runtime: $RUNTIME"
az webapp show -g "$RG" -n "$APP" -o none 2>/dev/null || az webapp create -g "$RG" -p "$PLAN" -n "$APP" --runtime "$RUNTIME" -o none
az webapp config appsettings set -g "$RG" -n "$APP" --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true -o none
URL="https://$APP.azurewebsites.net"; echo "default page: $(curl -s -o /dev/null -w '%{http_code}' "$URL") $URL"
echo "== Part 3: connect GitHub Actions (Azure writes .github/workflows into the repo)"
# gh is already signed in, so hand its token to Azure instead of doing a second GitHub device login
GH_TOKEN_ARG=$( [ -n "$(gh auth token 2>/dev/null)" ] && echo "--token $(gh auth token)" || echo "--login-with-github" )
# --force: on a rerun the workflow file already exists and az would stop at a "Replace existing workflow file?" prompt (no TTY in a script);
# rewriting it also refreshes the publish-profile secret, which changes whenever the Web App is recreated (a stale one gives the deploy job a 401)
az webapp deployment github-actions add -g "$RG" -n "$APP" --repo "$GH_USER/$REPO" --branch main $GH_TOKEN_ARG --force -o none 2>&1 | grep -v "^WARNING" \
  || echo "(az reported Not Found at the end; the workflow file and the publish-profile secret are already in the repo, which is all the run needs)"
sleep 20; gh run list -R "$GH_USER/$REPO" --limit 1
gh run watch -R "$GH_USER/$REPO" "$(gh run list -R "$GH_USER/$REPO" --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status >/dev/null && echo "first run green"
for i in $(seq 1 30); do curl -s "$URL" | grep -q "Canyon Youth Soccer" && break; sleep 10; done; curl -s "$URL" | grep -o '<h1>.*</h1>'
echo "== Part 4: live change drill"
git pull -q --rebase origin main      # picks up the workflow commit Azure made
sed -i.bak 's|</p>|</p><p><strong>Field 3 closed for drainage repair on 14 Nov.</strong></p>|' index.js; rm -f index.js.bak
T0=$(date +%s); git commit -qam "Field 3 closure notice"; git push -q origin main
sleep 15; gh run watch -R "$GH_USER/$REPO" "$(gh run list -R "$GH_USER/$REPO" --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status >/dev/null
for i in $(seq 1 60); do curl -s "$URL" | grep -q "Field 3" && break; sleep 5; done
echo "push-to-live: $(( ($(date +%s) - T0) / 60 )) min $(( ($(date +%s) - T0) % 60 )) s"; curl -s "$URL" | grep -o '<strong>.*</strong>'
echo "LIVE_URL=$URL"; echo "LAB2_DEPLOY_DONE"
