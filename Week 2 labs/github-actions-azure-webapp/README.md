# Week 2 Lab: CI/CD Pipeline from GitHub to an Azure Web App (Use Case 2.2, Canyon Youth Soccer)

Canvas assignment **2.2 Team Lab 2: CI/CD Pipeline for React App using GitHub and Azure**,
40 points, team submission.

Canyon Youth Soccer League publishes game schedules on a site maintained by two volunteer
parents. Today one parent emails a zip file to the other, who uploads it by FTP on Tuesday
night; last season a stale upload sent 200 families to the wrong field. The board wants a
change pushed to GitHub to appear on the live site within minutes, with no manual upload.

**Constraint.** The pipeline must redeploy on every push to `main`, and the team must
demonstrate a live change end to end during the session.

> **Where to run it.** Students: the **Vocareum Azure Sandbox** from Canvas (free). Its
> portal works normally for this lab; the one difference from a personal subscription is
> that the Azure CLI on a laptop is blocked by Conditional Access, so use the portal or its
> Cloud Shell. Instructor: the *Ensign College - School Card* subscription with `az login`
> on the laptop, which is what `scripts/deploy-lab2.sh` expects. A free GitHub account is needed. The Canvas guide builds an Express app even
> though the title says React; this guide does the same so it matches what is graded.

Roles: app developer (scaffolds and runs the app), repo owner (repository, first commit),
Azure engineer (Web App and deployment source), release manager (live change, timing, the
board summary).

**Click-by-click handout:** `Week 2 Lab Click-by-Click - CI-CD Pipeline from GitHub to an Azure Web App.docx` in this folder is the screenshot-driven version of this guide: every console step has a numbered screenshot of where to click (`images/clicks/`) with a "What you see" description, every terminal step shows real output, and a verification-commands section lists the checks that prove the deployment. It covers Azure portal screenshots (Create Web App, resource group, plan, Deployment Center settings and logs) and the live site, plus the real output of the 2026-10-29 run and the GitHub CLI view of the Actions runs. Generated with `docgen/build-click-guide.js`.

## Learning objectives

1. Create an Azure resource group, a Free F1 Linux plan and a Web App on the newest Node LTS runtime (Node 24 LTS in October 2026; Node 20 was retired).
2. Push an Express app to GitHub on branch `main`.
3. Connect the Web App's Deployment Center to the repository so Azure commits a GitHub
   Actions workflow.
4. Read the Actions log: which step builds, which step deploys.
5. Push a live change and time push-to-live.

## Naming used in this guide

| Item | Value |
|---|---|
| Resource group | `canyon-soccer-rg` |
| App Service plan | `canyon-asp`, Linux, Free F1 |
| Web App | `canyon-schedule-<team>` → `https://canyon-schedule-<team>.azurewebsites.net` |
| Repository | `canyon-schedule`, public, default branch `main` |

## Before Part 1: set your values once per terminal

The Mac Terminal runs zsh, which does not treat `#` as a comment when you paste and reads
`<word>` as input redirection from a file. The command blocks below therefore carry no
comments and no angle-bracket placeholders; set your values once as variables instead. Replace
`yourteam` (lowercase letters and digits, unique across Azure), `yourgithubuser`, and the
`LAB` path, and run these four lines in every new Terminal or Cloud Shell window:

```bash
TEAM=yourteam
GH_USER=yourgithubuser
LAB="$HOME/Downloads/github-actions-azure-webapp"
APP=canyon-schedule-$TEAM
```

`echo $APP` should print your Web App name, for example `canyon-schedule-jisiko`. If you paste
commands from elsewhere that contain comments, run `setopt interactivecomments` once in that
zsh window first. Cloud Shell runs bash and needs neither.

## Part 1. Azure resources (Azure engineer, 15 min)

Portal → Resource groups → Create `canyon-soccer-rg`. App Service Plans → Create
`canyon-asp`, Linux, Free F1. App Services → Create Web App: name `canyon-schedule-<team>`,
Publish Code, runtime **Node 24 LTS** (the newest LTS the dropdown offers; Node 20 LTS was retired in October 2026), Linux, the plan above.

CLI equivalent (Cloud Shell in the Vocareum portal, or a laptop with `az login`):

```bash
az group create -n canyon-soccer-rg -l westus2
az appservice plan create -g canyon-soccer-rg -n canyon-asp -l westus2 --is-linux --sku F1
az webapp list-runtimes --os-type linux | grep -i node
az webapp create -g canyon-soccer-rg -p canyon-asp -n "$APP" --runtime "NODE:24-lts"
az webapp config appsettings set -g canyon-soccer-rg -n "$APP" --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true
```

Use `westus2`, or the region where your subscription has Free F1 quota (see Troubleshooting).
`list-runtimes` shows the Node versions on offer (on 2026-11-01: `NODE:26`, `NODE:24-lts`,
`NODE:22-lts`); use the newest one marked `-lts`. Node 20 LTS was retired in October 2026.
These five lines were pasted into an interactive zsh on a Mac on 2026-11-01 and ran without
an error; the new site answered HTTP 200.

**Validation 1.** Web App → Browse shows the default Azure page. Screenshot 1.

## Part 2. Repository and app (repo owner and app developer, 30 min)

### Sign in to Git and GitHub (once per laptop)

`git --version`, `node --version`, `npm --version` and `gh --version` must each print a
version (Node 22 or newer). Then tell Git who you are, using your GitHub account's e-mail:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
```

GitHub does not accept your account password for `git push`. Sign in with the GitHub CLI
and let Git use that sign-in:

```bash
gh auth login
gh auth setup-git
gh auth status
```

`gh auth login` asks four things: GitHub.com, HTTPS, *Authenticate Git with your GitHub
credentials?* Yes (if asked), and *Login with a web browser*. It prints a one-time code;
press Enter, paste the code at github.com/login/device and click Authorize. `gh auth status`
then shows `Logged in to github.com account <your user>`. Without the CLI, create a classic
personal access token (GitHub → Settings → Developer settings → Personal access tokens →
Tokens (classic), scopes `repo` and `workflow`) and paste it as the password the first time
Git asks; the macOS keychain remembers it.

### Create the repository, add the app, push


On GitHub create `canyon-schedule`, public, default branch `main`. Clone it and copy the
contents of `canyon-schedule/` from this folder (index.js, package.json, .gitignore), or
scaffold by hand:

```bash
npm init -y && npm install express
```

`index.js` serves the heading *Canyon Youth Soccer — Fall Schedule*; `package.json` has
`"start": "node index.js"`. To clone your repository and copy the lab's app into it:

```bash
git clone "https://github.com/$GH_USER/canyon-schedule.git"
cd canyon-schedule
cp -r "$LAB/canyon-schedule/." .
npm install
npm start
```

`git clone` warns *You appear to have cloned an empty repository*, which is expected. `cp` copies
the lab's `index.js`, `package.json` and the hidden `.gitignore` (the `/.` at the end includes
hidden files); `npm install` downloads Express into `node_modules` (about 68 packages) and writes
`package-lock.json`; `npm start` prints `Schedule site running` and keeps running. Open
http://localhost:3000, then press Ctrl+C and push:

```bash
git add .
git commit -m "Initial schedule site"
git push origin main
```

`git add .` marks every file except what `.gitignore` excludes; `git commit` saves the snapshot
on the laptop (`4 files changed`); `git push origin main` uploads it to GitHub
(`* [new branch] main -> main`).

GitHub's *Quick setup* page on a new repository suggests a different order that ends in the same
place: `echo "# canyon-schedule" >> README.md` (a one-line README), `git init` (make this folder a
repository), `git add` and `git commit` (first snapshot), `git branch -M main` (name the branch
`main`), `git remote add origin <address>` (remember GitHub's address as `origin`) and
`git push -u origin main` (upload, and remember `origin/main` for later `git push` and `git pull`).
To use that route with the lab's files, run it in an empty folder after
`cp -r "$LAB/canyon-schedule/." .`, with `git add .` instead of `git add README.md`. Or, after
`git init`, `git add .` and `git commit`, let the GitHub CLI create the repository and push in one
step: `gh repo create canyon-schedule --public --source=. --push`. Use one route only.

**Validation 2.** The local page. Screenshot 2. Have a second teammate clone and run it
before continuing.
**Checkpoint.** Who else on the team can run this locally right now? If only one laptop
works, fix that before Part 3.

## Part 3. Connect the pipeline (Azure engineer, 15 min)

Web App → Deployment Center → Source **GitHub** → authorise → organisation, repository
`canyon-schedule`, branch `main`, build provider GitHub Actions → Save. Azure commits a
workflow file under `.github/workflows/` in the repository. CLI equivalent:

```bash
az webapp deployment github-actions add -g canyon-soccer-rg -n "$APP" --repo "$GH_USER/canyon-schedule" --branch main --login-with-github
```

**Validation 3.** GitHub → Actions: the run goes green. Open it and expand the single
`build-and-deploy` job to show its build step and its deploy step. Screenshot 3. Reload the live URL: the heading reads Canyon Youth Soccer.
**Checkpoint.** Which step in the log builds the app (the `npm install, build, and test` step
of the `build-and-deploy` job), and which deploys it (the `Deploy to Azure Web App` step, which runs `azure/webapps-deploy`)?

## Part 4. Live change drill (release manager, 15 min)

Pull first, because Azure committed the workflow file:

```bash
git pull
```

Open `index.js` and add this paragraph under the schedule line, inside the HTML string:
`<p><strong>Field 3 closed for drainage repair on 14 Nov.</strong></p>`. Save, then:

```bash
git add .
git commit -m "Field 3 closure notice"
git push origin main
date
```

Note the clock time at the push. Watch Actions; when green, reload the live site and note
the time the notice appeared.

**Validation 4.** The live page with the notice and the address bar. Screenshot 4. Push to live took 46 seconds on 2026-10-29 and up to 4 minutes on 2026-10-31; a few minutes is normal.
**Checkpoint.** How many minutes from push to live? Would the board accept that on a
Tuesday night?

## Deliverables (Canvas 2.2)

The live URL, screenshots 2 and 4 as before and after, the push-to-live minutes, the 2 to 3
sentence summary, and the Team Collaboration and Documentation section.

## Stretch

Push a commit with a deliberate syntax error (remove a closing parenthesis). The Actions run
fails at build and the live site keeps the previous version. Screenshot the red run beside
the still-working site, then fix and push. That is what protects the families.

## Cleanup

Delete `canyon-soccer-rg`; it removes the plan and the app together. F1 is free, so the cost
of forgetting is zero. With the scripts: `bash scripts/rollback-lab2.sh` (add `--repo` to
delete the GitHub repository too).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Live site shows the Azure default page after a green run | Workflow `app-name` does not match the Web App, or no start script | Fix the name; add `"start": "node index.js"` |
| Run fails on `npm ci` | No `package-lock.json` | `npm install` locally and commit the lock file |
| 403 on Deployment Center | GitHub authorised with a different account than the repository owner | Re-authorise with the owner |
| `az login` fails in the Vocareum sandbox | Conditional Access blocks the CLI app | Use the portal's Cloud Shell |
| `rollback-lab2.sh --repo` says the token needs the delete_repo scope | `gh` was signed in without it | `gh auth refresh -h github.com -s delete_repo`, then rerun |

## Scripts in this folder

| Script | Where to run | What it does |
|---|---|---|
| `scripts/deploy-lab2.sh <team>` | Laptop with `gh` and `az` signed in | Parts 1 to 4 end to end, including the timed live change |
| `scripts/rollback-lab2.sh [-n] [-y] [--repo]` | Same | Deletes the resource group (and the repo with `--repo`) |
| `canyon-schedule/` | Copy into the repository | The Express app |

## What changed in the industry, April to October 2026

- **GitHub Agentic Workflows (technical preview, February 2026)** run coding agents inside
  GitHub Actions from a Markdown file: issue triage, daily reports, compliance checks. The
  **Copilot cloud agent** takes an issue, works in its own Actions-powered environment,
  opens a draft PR and tags you for review; it cannot mark its own PR ready or approve it.
- **Keyless deploys are the default pattern.** Azure's recommended path is an OIDC federated
  credential on a managed identity (issuer `https://token.actions.githubusercontent.com`,
  audience `api://AzureADTokenExchange`, `id-token: write` in the job); the publish-profile
  secret Deployment Center still writes is the legacy form. Google (Workload Identity
  Federation) and AWS (`configure-aws-credentials` with a role) use the same OIDC exchange.
- **Microsoft Build 2026 (June):** Foundry hosted agents with per-session sandboxes, Foundry IQ
  retrieval, the Agent Control Specification for runtime governance; the GitHub Copilot SDK
  and Claude Agent SDK integrations reached stable.
- **Jenkins vs Actions:** Actions is the greenfield default; Jenkins persists where a company
  already runs it (Week 3 Lab 2 shows both).

### Across the providers: push-to-live pipelines (October 2026)

| Provider | What it offers for this week |
|---|---|
| AWS | CodePipeline and CodeBuild, or GitHub Actions assuming an IAM role over OIDC; Elastic Beanstalk per the teaching plan |
| Azure | App Service Deployment Center writes the Actions workflow; recommended credential is an OIDC federated credential on a managed identity (this lab) |
| Google Cloud | Cloud Build, or GitHub Actions with Workload Identity Federation deploying to Cloud Run from source (`cloud-run.yml`) |
| DigitalOcean | App Platform builds and deploys on every push to a GitHub branch with no workflow file |
| Oracle Cloud | OCI DevOps pipelines; GitHub Actions can exchange its OIDC token for an OCI token through Workload Identity Federation |

Market context (Synergy Research, Q2 2026): 143.4 billion dollars in the quarter, up 43 percent; AWS 28, Azure 20, Google 15 percent.

Sources for this section:
- https://github.blog/changelog/2026-02-13-github-agentic-workflows-are-now-in-technical-preview/
- https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent
- https://azure-samples.github.io/app-service-labs/docs/deployment-and-cicd/deploy-with-github-actions/ (OIDC federated credential)
- https://developer.microsoft.com/blog/build-recap/ (Build 2026)

### AI and automation extension (optional, 30 min)

1. **Keyless:** replace the publish-profile secret with OIDC. Create a user-assigned managed
   identity, add a federated credential for `repo:<owner>/canyon-schedule:ref:refs/heads/main`,
   give it Website Contributor on the Web App, then use `azure/login@v2` with
   `client-id`, `tenant-id`, `subscription-id` and `permissions: id-token: write` before
   `azure/webapps-deploy@v3`. Delete the secret and push: still green.
2. **Agentic workflow:** add a `.github/workflows/triage.md` agentic workflow that labels new
   issues (`schedule-change`, `field-closure`) and drafts the one-line site notice. Open an
   issue titled *"Field 3 closed 14 Nov"* and watch the agent propose the commit.
3. **Same pipeline, second cloud:** `cloud-run.yml` in this folder deploys the same Express app
   to Google Cloud Run (instructor project `jackson-isiko`) with Workload Identity Federation; the board can compare the two URLs
   and the two push-to-live times.

## Instructor run (2026-10-26, Ensign College - School Card subscription)

| Step | Result |
|---|---|
| App locally | `npm test` passes; `npm start` serves *Canyon Youth Soccer — Fall Schedule* on port 3000 |
| Repository | `canyon-schedule` on GitHub (private on the instructor account; students create a public one) |
| Azure plan and Web App | `canyon-asp` (Free F1) and `canyon-schedule-jisiko` in **westus2** on `NODE:24-lts`. The subscription has **0 App Service quota in eastus** for both F1 and B1, so `LOCATION=westus2` is required; `az webapp list-runtimes --os-type linux` no longer lists Node 20 |
| Deployment Center | `az webapp deployment github-actions add --token $(gh auth token)` wrote `.github/workflows/main_canyon-schedule-jisiko.yml` and the `AZUREAPPSERVICE_PUBLISHPROFILE_*` secret, then ended with a spurious *Not Found*; the script ignores it |
| First run | GitHub Actions run green ("Build and deploy Node.js app to Azure Web App"); `https://canyon-schedule-jisiko.azurewebsites.net` returned 200 with the schedule heading |
| Live change drill | `git push` to the new paragraph live: **0 min 54 s** (Actions run plus App Service restart) |

Teardown: `scripts/rollback-lab2.sh -y` deletes the resource group (plan and app); `--repo`
needs the `delete_repo` scope on the GitHub token, otherwise delete the repository in the GitHub UI.

## Instructor notes

- This is the industry default pipeline: GitHub-hosted source, GitHub Actions build, cloud
  deploy triggered on push to `main`. The Azure-generated workflow authenticates with a
  publish-profile secret; the keyless version uses OpenID Connect federation, the same
  pattern Google Cloud's Workload Identity Federation uses in Week 5.
- Debrief: what did the volunteers give up by adopting the pipeline, and what did they gain?
  Where would a review step belong if the league wanted a second parent to approve changes
  before they go live (a pull request with a required review on `main`)?
