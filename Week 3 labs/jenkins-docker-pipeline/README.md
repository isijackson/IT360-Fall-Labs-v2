# Week 3 Lab 2: Docker Containers and a CI/CD Pipeline with Jenkins (Use Case 3.3, Bonneville Brewing)

Canvas assignment **3.3 Team Lab 2: Docker Containers & CI/CD Pipeline with Jenkins**,
40 points, team submission.

Bonneville Brewing runs digital menu boards in four taprooms from a small containerized
web app. Today the owner's nephew builds the image on his laptop and pushes it to Docker
Hub with his personal password. The owner wants a Jenkins job anyone on staff can click
that builds the image, tags it with the build number, and pushes it with a credential that is
stored in Jenkins and **never shown in a log**.

> **Where to run it.** Jenkins can run anywhere Docker runs: a laptop with Docker Desktop,
> or a VM in the **Vocareum** AWS, Azure or GCP lab (free for students). The registry can be
> Docker Hub (create a free account and an access token) or, for a run that needs no
> account at all, the local registry container that `scripts/deploy-lab3-2.sh` starts.

**Click-by-click handout:** `Week 3 Lab 2 Click-by-Click - Docker and a Jenkins CI-CD Pipeline.docx` in this folder is the screenshot-driven version of this guide: every console step has a numbered screenshot of where to click (`images/clicks/`) with a "What you see" description, every terminal step shows real output, and a verification-commands section lists the checks that prove the deployment. It covers Jenkins screenshots (sign-in, credentials, Add Credentials, job, configuration, the masked console output) and the real build logs and registry tags of the 2026-10-29 run. Generated with `docgen/build-click-guide.js`.

## Learning objectives

1. Store a registry credential in Jenkins and reference it by ID.
2. Write a declarative pipeline: checkout, build, smoke test, push.
3. Tag images with the build number and `latest`.
4. Verify the secret is masked in the console log.
5. Run the job twice and watch `latest` move.

## Part 1. Something to build (pipeline author, 10 min)

`menu-board/` in this folder has the site, the Dockerfile and the Jenkinsfile:

```
menu-board/index.html         the menu
menu-board/Dockerfile         FROM nginx:1.27-alpine, copies index.html
menu-board/Jenkinsfile        the pipeline (checkout, build, smoke test, push)
menu-board/.github/workflows/build.yml   the 2026 twin: the same job as GitHub Actions
```

Push `menu-board/` to a GitHub repository `menu-board` so Jenkins can check it out.

## Part 2. Jenkins and the credential (Jenkins administrator, 10 min)

Jenkins needs the Docker Pipeline plugin and access to the Docker socket. `jenkins/Dockerfile`
builds exactly that image. Run it:

```bash
docker build -t it360-jenkins jenkins/
docker network create brewlab
docker run -d --name jenkins --network brewlab -e SMOKE_NET=brewlab -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock it360-jenkins
```

Why the network: Jenkins drives the laptop's Docker daemon through the socket, so the
smoke-test container the pipeline starts is a sibling of the Jenkins container, not a
process inside it. `localhost:18080` inside the Jenkins container is the container's own
loopback, where nothing listens. With `SMOKE_NET` set, the Jenkinsfile starts the smoke
container on that network as `smoke-<build number>` and curls `http://smoke-<build number>/`
instead (`menu-board/Jenkinsfile`, Smoke test stage). On a Jenkins VM without Docker around
Jenkins, leave `SMOKE_NET` unset and the smoke test uses `localhost:18080`.

Open http://localhost:8080 and sign in as `admin` / `admin`: `jenkins/Dockerfile` disables
the setup wizard and `jenkins/init.groovy.d/setup.groovy` creates that account at start-up,
so there is no unlock page or initial password. Manage Jenkins → Credentials → System →
Global credentials (unrestricted) → Add Credentials.
Kind **Username with password**. Username: your Docker Hub username. Password: a Docker
Hub **access token** (Account settings → Personal access tokens, Read and Write). ID:
`dockerhub-credentials` (must match the Jenkinsfile). Save.

**Checkpoint.** Where does the token live now, and who can read it? Encrypted in Jenkins,
readable only by jobs that reference the ID.

## Part 3. Pipeline (pipeline author, 15 min)

New Item → `menu-board` → Pipeline. Definition: *Pipeline script from SCM*, Git, your
repository URL, branch `*/main`, script path `Jenkinsfile`. Save.

`menu-board/Jenkinsfile` reads three environment variables so the same file works for Docker
Hub, a private registry, and Jenkins on a VM or in a container: `IMAGE_NAME`, `REGISTRY_URL`
and `SMOKE_NET`. For Docker Hub, set `IMAGE_NAME` to `<dockerhub-user>/menu-board` in one of
two places: edit the default on line 4 of the Jenkinsfile (replace `YOUR_DOCKERHUB_USER`), or
add it under Manage Jenkins → System → Global properties → Environment variables. The
`REGISTRY_URL` default is Docker Hub. This is the file as it is in the folder (comments
trimmed):

```groovy
pipeline {
    agent any
    environment {
        IMAGE_NAME = "${env.IMAGE_NAME ?: 'YOUR_DOCKERHUB_USER/menu-board'}"
        REGISTRY   = "${env.REGISTRY_URL ?: 'https://index.docker.io/v1/'}"
    }
    stages {
        stage('Checkout') {
            steps { checkout scm }
        }
        stage('Build') {
            steps { script { docker.build("${IMAGE_NAME}:${BUILD_NUMBER}") } }
        }
        stage('Smoke test') {
            steps {
                script {
                    def net  = env.SMOKE_NET ? "--network ${env.SMOKE_NET}" : ""
                    def url  = env.SMOKE_NET ? "http://smoke-${BUILD_NUMBER}/" : "http://localhost:18080/"
                    docker.image("${IMAGE_NAME}:${BUILD_NUMBER}").withRun("-p 18080:80 --name smoke-${BUILD_NUMBER} ${net}") { c ->
                        sh "sleep 2; curl -sf -o /dev/null -w 'HTTP %{http_code}\\n' ${url}"
                    }
                }
            }
        }
        stage('Push') {
            steps {
                script {
                    docker.withRegistry(REGISTRY, 'dockerhub-credentials') {
                        def img = docker.image("${IMAGE_NAME}:${BUILD_NUMBER}")
                        img.push("${BUILD_NUMBER}")
                        img.push('latest')
                    }
                }
            }
        }
    }
}
```

Build Now. Open build #1 → Console Output.

**Validation 1.** The log shows the build, `HTTP 200` from the smoke test, and the push of
two tags. Search the page for your token: it must not appear; Jenkins prints `********` where
the credential was used (`docker login -u <user> -p ********`). Screenshot 1.

## Part 4. Prove and repeat (registry owner and quality lead, 10 min)

**Validation 2.** Docker Hub → Repositories → menu-board → Tags shows `1` and `latest`.
Screenshot 2.

Edit `index.html` to add a third beer, commit, push, Build Now again.

**Validation 3.** Tags `1`, `2` and `latest`, with `latest` updated most recently.
Screenshot 3. Pull and run it anywhere: `docker run --rm -p 8081:80 <user>/menu-board:2`
(port 8081 because Jenkins already holds 8080 on this machine), then open http://localhost:8081
and stop it with Ctrl+C.

**Checkpoint.** A taproom reports the board broke after today's build. Which tag do they
roll back to, and how do they know? Tag 1, because every build left a numbered tag.

## Scripted run (no accounts needed)

`scripts/deploy-lab3-2.sh` does Parts 1 to 4 on a laptop with Docker: it starts a private
registry container with a generated password, builds the Jenkins image, creates the admin
user and the `dockerhub-credentials` credential, creates the job from a bare Git repository
in a volume, runs two builds, greps every build log for the password, and lists the registry
tags. Set `REGISTRY_HOST=index.docker.io REG_USER=<user> REG_PASS=<token>` to push to
Docker Hub instead. `scripts/rollback-lab3-2.sh` removes everything it created.

## Cleanup

Delete the Jenkins job if the server is shared; `docker rm -f jenkins`;
`docker network rm brewlab`; `docker rmi it360-jenkins <user>/menu-board:1 <user>/menu-board:2 <user>/menu-board:latest`
(`docker image prune` alone removes only untagged images and leaves these).
Docker Hub free tier is free. With the script: `bash scripts/rollback-lab3-2.sh -y`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `docker: command not found` in the job | Docker CLI not in the Jenkins image | Use `jenkins/Dockerfile` here, or `apt-get install docker.io` in the container |
| `permission denied ... docker.sock` | Jenkins user cannot use the socket | `sudo usermod -aG docker jenkins` on a VM; on Docker Desktop `docker exec -u root jenkins chmod 666 /var/run/docker.sock` (the container runs as user `jenkins`, so the chmod needs `-u root`) |
| Push fails with authentication error | Credential ID mismatch, or a password instead of a token | ID must be `dockerhub-credentials`; use an access token |
| `docker.build` not found | Docker Pipeline plugin missing | Install `docker-workflow` |
| Image not on Docker Hub | `IMAGE_NAME` differs from the repository name | Match them exactly |
| Smoke test fails with connection refused | Jenkins runs in a container and `SMOKE_NET` is not set, so `curl` hits the Jenkins container's own `localhost:18080` | Start Jenkins with `--network brewlab -e SMOKE_NET=brewlab` as in Part 2 |

## Deliverables (Canvas 3.3)

Screenshots 1 to 3, the Jenkinsfile, the Canvas summary, and one line from the quality lead
confirming no secret appears in the console log.

## The 2026 twin, and the debrief

`menu-board/.github/workflows/build.yml` is the same pipeline as GitHub Actions with the
token stored as a repository secret. Ask the team which one the brewery should keep:
Jenkins needs a server someone patches; Actions needs nothing but the repository. Why tag
with the build number as well as `latest`? Rollback. What would the brewery need to deploy
the new image to the taproom screens automatically? Week 4, Kubernetes.

## What changed in the industry, April to October 2026

- **Docker is an AI runtime now.** Docker Model Runner (GA since October 2025) pulls open-weight
  models from Docker Hub and runs them locally behind an OpenAI-compatible, and now
  Anthropic-compatible, endpoint; the MCP Toolkit (profile templates since Desktop 4.67, March
  2026) wires MCP servers into assistants. Images, models and MCP servers all live in the
  same registry you pushed to.
- **Pipelines run agents.** GitHub's Copilot cloud agent and Agentic Workflows run inside
  Actions; AWS Bedrock AgentCore's managed harness went GA at the New York Summit; the lesson
  of this lab (a credential stored once, referenced by ID, masked in every log) is the rule
  for agent credentials too.
- **Kiro replaces Q Developer** (new sign-ups closed May 15, 2026; end of support April 30,
  2027): spec-driven development, agent hooks and steering files, which is the "write the
  spec, let the agent build the Jenkinsfile" workflow.

### Across the providers: image build and registry (October 2026)

| Provider | What it offers for this week |
|---|---|
| AWS | CodeBuild with ECR; Jenkins on EC2 where it already runs |
| Azure | Azure Pipelines with ACR, or Jenkins on a VM |
| Google Cloud | Cloud Build with Artifact Registry (what the instructor run of Week 4 used) |
| DigitalOcean | DigitalOcean Container Registry (DOCR); App Platform can build from a Dockerfile |
| Oracle Cloud | OCI DevOps build pipelines with OCIR |

Market context (Synergy Research, Q2 2026): 143.4 billion dollars in the quarter, up 43 percent; AWS 28, Azure 20, Google 15 percent.

Sources for this section:
- https://www.bretfisher.com/blog/docker-ai-model-runner-and-mcp-toolkit
- https://whysogeek.com/docker-desktop-mcp-toolkit-model-runner-2026/
- https://aws.amazon.com/blogs/aws/top-announcements-of-the-aws-summit-in-new-york-2026/ (AgentCore harness GA, Kiro)

### AI and automation extension (optional, 30 min)

1. **AI review stage:** after *Smoke test*, add a stage that runs a local model through Docker
   Model Runner (`docker model pull ai/smollm2` then `docker model run ai/smollm2 "Review this
   Dockerfile for size and security problems: $(cat Dockerfile)"`) and prints the review in the
   console. No cloud call, no API key, and the model never sees the registry token.
2. **Twin it in Actions:** push the repository with `.github/workflows/build.yml`, store two
   repository secrets, `DOCKERHUB_USER` and `DOCKERHUB_TOKEN` (the workflow reads both), and compare the two console logs for masking.
3. **Spec first:** write a five-line spec ("build on push, tag with run number and latest, fail
   on non-200 smoke test, never print the token") and have Kiro, Copilot or Gemini CLI generate
   the Jenkinsfile. Diff it against the one here and list what it got wrong.

## Instructor run (2026-10-24, laptop with Docker Desktop)

| Validation | Result |
|---|---|
| Credential | `dockerhub-credentials` listed as `brewer/******` |
| Build #1 | checkout, build, smoke test HTTP 200, push `:1` and `:latest`, SUCCESS |
| Build #2 | after adding a third beer: push `:2`, `latest` moved, SUCCESS |
| Secret in logs | grep of every build log for the password: nothing |
| Registry | tags `1`, `2`, `latest` |
| Rollback | containers, volume, images and network removed by `rollback-lab3-2.sh` |

Fixes that went into the scripts during the run: macOS holds port 5000 (registry on 5005),
the Docker daemon, not the Jenkins container, performs the push (so the registry is addressed
as `localhost:5005`), the git plugin refuses local checkouts unless `ALLOW_LOCAL_CHECKOUT` is
set, and a bare repo owned by another user needs `safe.directory`.
