# Week 2 Lab 2B: Grow the React App and Practice CI/CD

Student handout: `Week 2 Lab 2B - Grow the React App and Practice CI-CD.docx` (24 pages). It builds on 2.2 Team Lab 2 (React app, GitHub, Azure Deployment Center). It assumes each team has the `my-react-app` repository, its Web App and the workflow Deployment Center wrote.

| Part | Students do | CI/CD skill |
|---|---|---|
| A | Four edits to the generated workflow (pull_request trigger, setup-node v4, `npm ci` with a build stamp, no deploy for pull requests), and a footer that shows the live commit | Pull-request checks, deploy only from main |
| B | `public/schedule.json`, a `GameCard` component, fetch in `useEffect`, a list with keys, tests with a mocked fetch | Ship a feature through a pull request |
| C | Field filter (controlled select), cancel and reinstate (events, lifting state up), two more tests | Tests travel with the feature |
| D | Rename the heading without updating the test | A red check blocks the merge; `gh run view --log-failed` |
| E | Push a bad schedule to main, then `git revert HEAD` | Rollback and time to restore |

`starter-code/part-*` holds every file exactly as the handout prints it. The generator reads them, so the handout and the tested code cannot drift apart.

Verified on 2026-11-05:
- The tests and `CI=true` build of every part (2, 3, 5 and 5 tests).
- Part D's failing output.
- The Git branch, push, squash and revert commands, in an interactive zsh against a test remote.
- The edited workflow, with actionlint. The generated workflow's `actions/setup-node@v3` is flagged as too old, which is why Part A upgrades it.
- Every `gh` flag, checked against gh 2.67.

Not verified: the pull-request pages and deploys on a student repository. Those are the students' run.

Rebuild:

```bash
cd docgen
NODE_PATH=<folder with node_modules/docx> node build-lab2b.js "../Week 2 Lab 2B - Grow the React App and Practice CI-CD.docx"
```
