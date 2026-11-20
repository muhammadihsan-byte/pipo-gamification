# Pipo Product Roadmap — automatic status synchronization

Project: https://github.com/users/muhammadihsan-byte/projects/1

## Policy

- **Todo → In Progress** only when a *same-repository* pull request starts work on an existing, OPEN issue already on Pipo Project #1.
- The issue number must be unambiguous in the branch name, e.g. `feat/pipo-48-photo-hero` or `fix/pipo-42-safe-ledger`.
- **Do not close an issue when a partial pull request merges.** A merged PR represents a completed slice, not necessarily a completed roadmap item.
- **Done** remains controlled by the project's native **Item closed → Status Done** workflow after the entire issue's acceptance criteria are verified and the issue is actually closed.
- Never overwrite `In Progress`, `Done`, `Blocked`, or another custom status; never alter PRs, close issues, or create project items.
- For projects that auto-add issues, enable the separate GitHub built-in **Auto-add to project** workflow; this job only changes items already in Project #1.

## GitHub Actions setup — one time

`.github/workflows/roadmap-status.yml` is deliberately inert without GitHub Projects credentials. The standard repository `GITHUB_TOKEN` cannot modify user-owned GitHub Projects.

1. Create a dedicated short-lived GitHub Projects-capable token belonging to an authorized project owner (GitHub App Projects write permission is ideal; a classic personal access token needs `project` scope and, if required to read the private repository issue, `repo` scope).
2. In the `muhammadihsan-byte/pipo-gamification` repository, open **Settings → Secrets and variables → Actions → New repository secret**.
3. Set the **name** to `PIPO_PROJECTS_TOKEN` and paste the credential only into GitHub's secret field. **Never commit or paste the token into a chat, issue, or PR.**
4. After merging the workflow, open a **new** same-repository PR on a branch named `feat/pipo-<issue-number>-<topic>` for a Todo issue already in Project #1. Verify the issue is moved to In Progress. A no-token run emits a notice and makes no changes.
5. Verify the already configured **Item closed → Done** built-in workflow is **enabled**. Do not enable automatic issue closing on partial PR merge.

The workflow uses `pull_request_target` only to read the trusted **main** branch's script. It does not checkout or execute PR-provided code. It rejects forks and unknown branch names. Tests on `pull_request` use no secrets and verify the safety rules.

## Out-of-scope / known limitation

The workflow acts when a recognized PR is opened/reopened/updated, **not when an agent merely begins thinking or writing code without a PR**. Open the draft PR near the start of implementation so the board reflects work promptly.

If the token is not configured, project status is unchanged and workflow logs explicitly explain why. A missing Project item is deliberately not auto-added. New issues should be covered by Project's built-in Auto-add workflow.

This workflow does **not** update issue #44 to Done merely because PR #46 merged, nor issue #48 when the single-photo slice merges while multi-photo work remains.
