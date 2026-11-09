# Week 2, Day 2: React demo app and a hand-written pipeline

**Live demo:** https://canyon-react-demo-jackson.azurewebsites.net (Web App `canyon-react-demo-jackson`, resource group `react-lab-rg`, plan `react-lab-asp`, Linux Free F1, West US 2, Node 24 LTS).

**Slides:** `IT360-Weekly-Decks/with-labs/IT360-Week2-Day2-Review-Requirements-and-Pipeline.pptx` (28 slides), and the same slides appended to the Week 2 deck in `IT360-Week2-Agile-CICD-with-labs-and-Day2.pptx`. Spec: `tools/deck-specs/week2-day2.json`.

## What is here

| Path | What it is |
|---|---|
| `react-demo/src/` | *Wasatch Front Fall Sports Schedule*: App, six components, a custom hook and a context. Each part carries a label naming the React concept it shows |
| `react-demo/src/App.test.js` | Four tests: load, filter, cancel, add with validation |
| `react-demo/public/schedule.json` | The published schedule the app fetches |
| `react-demo/Dockerfile`, `nginx.conf`, `.dockerignore` | Two-stage image: Node builds and tests, nginx serves `build/` with a fallback to `index.html` |
| `react-demo/.github/workflows/ci-cd.yml` | Three jobs: test, container (pushed to ghcr.io on main), deploy with OIDC and a smoke test |
| `images/` | Screenshots of the live app, the three diagrams and the terminal evidence used in the slides |

## Run it

```bash
cd react-demo
npm ci
npm start
```

```bash
CI=true npm test -- --watchAll=false
CI=true npm run build
docker build -t my-react-app:local .
docker run -d --name react-local -p 8080:80 my-react-app:local
```

## How the live demo was deployed (2026-11-05)

```bash
REACT_APP_BUILD_SHA=demo2026110502 REACT_APP_BUILD_TIME=$(date -u +%Y-%m-%dT%H:%MZ) CI=true npm run build
mkdir pkg && cp -r build pkg/build && (cd pkg && zip -qr ../pkg.zip .)
az webapp create -g react-lab-rg -p react-lab-asp -n canyon-react-demo-jackson --runtime "NODE:24-lts"
az webapp config set -g react-lab-rg -n canyon-react-demo-jackson --startup-file "pm2 serve /home/site/wwwroot/build --no-daemon --spa"
az webapp deploy -g react-lab-rg -n canyon-react-demo-jackson --src-path pkg.zip --type zip
```

## What was verified, and what was not

Verified on 2026-11-05: the four tests and the `CI=true` build, the Docker image (51 MB, HTTP 200 on `/` and on a deep link), the image build stopping at the starter *learn react* test, `actionlint` on the workflow with and without `environment: production`, and the zip deploy of `build/` to a Web App with the pm2 startup command.

Not verified: a GitHub-hosted run of `ci-cd.yml`, which needs a push to a student repository. The OIDC subject format comes from the managed identity Deployment Center created on 2026-11-01 (`repo:<owner>@<id>/<repo>@<id>:ref:refs/heads/main`). An environment job presents `...:environment:production`, which needs a second federated credential.
