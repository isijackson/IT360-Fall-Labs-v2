# IT 360 Cloud Integration: Fall 2026 Labs (v2)

Lab guides, scripts, YAML and sample code for **IT 360 Cloud Integration** at Ensign College.
Weeks 1 to 3 are published; later weeks are added as the course progresses.

## Get the files

- **Download everything:** click the green **Code** button above, then **Download ZIP**, and unzip it.
- **Or with Git:** `git clone https://github.com/isijackson/IT360-Fall-Labs-v2.git`
- **Read online:** open a folder below and click a `.pdf` guide; GitHub shows it in the browser.

## What is here

| Week | Folder | Labs |
|---|---|---|
| 1 | [Week 1 labs](Week%201%20labs) | VM migration to Google Cloud (AWS and Azure variants), cross-cloud automation with Ansible, cross-cloud infrastructure as code |
| 2 | [Week 2 labs](Week%202%20labs) | CI/CD for a React app with GitHub and Azure, Lab 2B (grow the app and practise CI/CD), the class demo app |
| 3 | [Week 3 labs](Week%203%20labs) | Lab 1: Kubernetes on GKE with Helm and a NetworkPolicy. Lab 2: Docker and a Jenkins CI/CD pipeline |

### Week 3 at a glance

| Lab | Student guide | Files the guide uses |
|---|---|---|
| Lab 1 (Canvas 3.2), about 80 min | [Week 3 Lab 1 Student Guide (PDF)](Week%203%20labs/gke-helm-networkpolicy) | `Week 3 labs/gke-helm-networkpolicy/k8s/` (the guide downloads both YAML files for you) |
| Lab 2 (Canvas 3.3), about 90 min | [Week 3 Lab 2 Student Guide (PDF)](Week%203%20labs/jenkins-docker-pipeline) | `Week 3 labs/jenkins-docker-pipeline/jenkins/` and `menu-board/` |

For Lab 2, create **your own** public GitHub repository called `menu-board` and upload only
`index.html`, `Dockerfile` and `Jenkinsfile` from `menu-board/`. Jenkins needs them at the top
level of a repository, so do not fork this whole repository for that lab.

## Ground rules

- Every guide was run end to end by the instructor; "You should see" boxes show real output. Your
  names, IP addresses and times will differ.
- Never commit keys, tokens, passwords or account IDs to any repository, including your team's.
- Delete cloud resources at the end of each lab; each guide ends with the clean-up commands.
- Questions or a mistake in a guide: post in Canvas with the exact error text and a screenshot.

Instructor: Jackson Isiko, Ph.D., IT 360 Cloud Integration, Ensign College.
