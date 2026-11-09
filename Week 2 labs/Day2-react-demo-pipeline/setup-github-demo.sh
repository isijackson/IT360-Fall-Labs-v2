#!/usr/bin/env bash
# Put the Wasatch Front demo app in its own private GitHub repository, let that repository deploy to the
# live demo Web App without a password (OIDC), and run the pipeline once.
# Run it yourself from any folder:  bash "Week 2 labs/Day2-react-demo-pipeline/setup-github-demo.sh"
# Needs: gh signed in (gh auth status), az signed in to the Ensign subscription (az account show).
set -euo pipefail

OWNER=$(gh api user --jq .login)
REPO=wasatch-sports-demo
RG=react-lab-rg
APP=canyon-react-demo-jackson
ID=wasatch-demo-github
HERE=$(cd "$(dirname "$0")" && pwd)

echo "== 1. The Azure identity GitHub Actions signs in as, with deploy rights on $APP only"
az identity show -g "$RG" -n "$ID" >/dev/null 2>&1 || az identity create -g "$RG" -n "$ID" -l westus2 -o none
CID=$(az identity show -g "$RG" -n "$ID" --query clientId -o tsv)
PID=$(az identity show -g "$RG" -n "$ID" --query principalId -o tsv)
SCOPE=$(az webapp show -g "$RG" -n "$APP" --query id -o tsv)
for i in 1 2 3 4 5 6; do
  az role assignment create --assignee-object-id "$PID" --assignee-principal-type ServicePrincipal \
    --role "Website Contributor" --scope "$SCOPE" -o none && break
  echo "   waiting for the new identity to appear in Entra ID ($i)"; sleep 10
done

echo "== 2. The private repository"
gh repo view "$OWNER/$REPO" >/dev/null 2>&1 || gh repo create "$OWNER/$REPO" --private \
  --description "IT 360 Week 2 Day 2 demo: React app, Docker, hand-written CI/CD to Azure"
RID=$(gh api "repos/$OWNER/$REPO" --jq .id)
OWNER_ID=$(gh api "users/$OWNER" --jq .id)

echo "== 3. Trust: the identity accepts GitHub's token for this repository's main branch"
# GitHub may name the repository with or without numeric IDs in the token; trust both forms.
for SUBJ in "repo:$OWNER/$REPO:ref:refs/heads/main" "repo:$OWNER@$OWNER_ID/$REPO@$RID:ref:refs/heads/main"; do
  NAME="gh-main-$(printf '%s' "$SUBJ" | shasum | cut -c1-6)"
  az identity federated-credential show -g "$RG" --identity-name "$ID" -n "$NAME" >/dev/null 2>&1 || \
    az identity federated-credential create -g "$RG" --identity-name "$ID" -n "$NAME" \
      --issuer https://token.actions.githubusercontent.com --subject "$SUBJ" --audiences api://AzureADTokenExchange -o none
  echo "   trusts $SUBJ"
done

echo "== 4. The three IDs as repository secrets (IDs, not passwords)"
gh secret set AZURE_CLIENT_ID -R "$OWNER/$REPO" -b "$CID"
gh secret set AZURE_TENANT_ID -R "$OWNER/$REPO" -b "$(az account show --query tenantId -o tsv)"
gh secret set AZURE_SUBSCRIPTION_ID -R "$OWNER/$REPO" -b "$(az account show --query id -o tsv)"

echo "== 5. Push the app with its workflow pointed at $APP"
WORK=$(mktemp -d)
cp -R "$HERE/react-demo/." "$WORK/"
cd "$WORK"
sed -i.bak \
  -e "s/my-react-app-yourteam/$APP/" \
  -e "s/AZUREAPPSERVICE_CLIENTID_XXXXXXXX/AZURE_CLIENT_ID/" \
  -e "s/AZUREAPPSERVICE_TENANTID_XXXXXXXX/AZURE_TENANT_ID/" \
  -e "s/AZUREAPPSERVICE_SUBSCRIPTIONID_XXXXXXXX/AZURE_SUBSCRIPTION_ID/" \
  .github/workflows/ci-cd.yml
rm .github/workflows/ci-cd.yml.bak
git init -q -b main
git add .
git commit -qm "Wasatch Front Fall Sports Schedule: React demo with a hand-written CI/CD pipeline"
git remote add origin "https://github.com/$OWNER/$REPO.git"
git push -u origin main

echo "== 6. Watch the pipeline: test, container, deploy, smoke test"
sleep 8
RUN=$(gh run list -R "$OWNER/$REPO" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch -R "$OWNER/$REPO" "$RUN" --exit-status
SHA=$(git rev-parse HEAD)
JS=$(curl -s "https://$APP.azurewebsites.net" | grep -o 'static/js/main[^"]*\.js' | head -1)
if curl -s "https://$APP.azurewebsites.net/$JS" | grep -q "$SHA"; then
  echo "LIVE: the site now carries commit ${SHA:0:7} in its footer"
else
  echo "The run finished, but the live bundle does not show ${SHA:0:7} yet; reload in a minute"
fi
echo "Repository: https://github.com/$OWNER/$REPO   Run: https://github.com/$OWNER/$REPO/actions/runs/$RUN"
