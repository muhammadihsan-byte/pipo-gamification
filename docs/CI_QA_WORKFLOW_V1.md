# Pipo CI & PR QA workflow V1

This document describes incremental CI changes only. It does **not** change the product, Supabase production state, iOS app behavior, or developer tooling.

## PR workflow

1. Open a **draft PR** while implementing small changes. `PR Fast Checks / Static & Harness QA` runs for draft and non-draft PRs, checking the P0 repository preflight, offline QA-harness tests, and roadmap transition logic.
2. The existing `iOS Build and Test / build-and-test` job is **intentionally skipped** while a PR is draft. This is not evidence that iOS QA passed.
3. Batch related commits and mark the PR **Ready for review** at the feature checkpoint. The existing iOS job then executes the iOS build and the unit-test suite, together with feature-specific simulator tests when the existing routing selects them.
4. While a non-draft PR is being updated, newer commits cancel superseded `pull_request` iOS runs. Manual `workflow_dispatch` and release-tag runs are not automatically cancelled by this policy.
5. Read the GitHub Actions **job summary** and downloadable artifacts to inspect the tested commit and selected focused-suite outcomes.
6. Before merge, verify the **latest head SHA** and all applicable mandatory checks. A green check for an older SHA or a skipped suite is not release evidence. Final merge still requires the owner's explicit approval.

No changes to automatic on-push iOS coverage for a ready-for-review PR are included in V1.

## Manual iOS QA modes

In **Actions → iOS Build and Test → Run workflow**, select the branch to test and choose one of:

| Mode | What it runs |
| --- | --- |
| `build-only` | iOS simulator compile, no tests |
| `build-and-test` | Xcode build and unit tests |
| `visual-qa` | Saving journey recording |
| `onboarding-qa` | Onboarding journey recording |
| `issue42-qa` | Focused, review-only plan and money-out simulator test |
| `manage-plan-qa` | Manage Plan V2 focused simulator tests and MP4 |
| `global-experience-qa` | Global Experience V1, currency, accessibility and Manage Plan integration tests and MP4 |

These modes are supplemental targeted QA and can run without depending on a historical branch name. They do **not** replace passing required PR checks or a separate security/data gate where applicable.

## Automatic checks retained

- Account deletion handler security tests stay path-scoped.
- Authenticated two-user live RLS checks remain explicitly opt-in with disposable test-account approval.
- Live anonymous Supabase auth smoke checks remain non-destructive and path-scoped.
- Disposable PostgreSQL 17 and local Supabase Auth/PostgREST integration tests remain intact and path-scoped.
- Pipo iOS unit, focused UI, accessibility and saving/currency test logic remains intact.

`Pipo Roadmap Status Sync` still executes for PR open/reopen, readiness and edits, but not for every commit update (`synchronize`). Updating PR text can re-run it when linked issue references change.

## Failure triage and limited retry

- Build or test failures: examine the exact failing step, `.xcresult` files, screenshots, and logs. Repair the defect on the branch, then allow PR checks to re-run on the updated SHA.
- Transient GitHub runner errors: re-run only the failed job when justified. Do not keep retrying a deterministic assertion without a code fix.
- Keep a maximum of three **manual** investigation/retry cycles as an operating guideline; V1 does not install a coding agent or auto-repair code.
- Never bypass tests, weaken assertions, or treat a skipped job as a passing required check.

## Branch protection: repository owner configuration needed

At the read-only audit, `main` was unprotected. This PR cannot configure repository rulesets or branch protection through the available GitHub integration.

After validating the new checks on this PR, the repository owner should configure **Settings → Rules → Rulesets**, targeted at `main`, to require a pull request and the relevant CI job contexts observed on GitHub, with branch updates and approvals checked against the latest commit. Consider requiring `Static & Harness QA` and the existing `build-and-test` context for iOS. Do not choose a status check that is conditionally skipped for legitimate main-targeting PRs without understanding GitHub's pending/skipped semantics.

Do not enable branch protection until the exact available check names and enforcement behavior have been confirmed with a passing PR run. Keep merge/publish separate from unrelated database deployment and production changes.

## Known limitations

- PR Fast Checks intentionally does not compile SwiftUI or run an iOS Simulator.
- iOS compilation and simulator tests still require a macOS runner; the Apple toolchain is not installed by this workflow.
- Existing focused PR suites use historical branch-name conditions; V1 adds explicit dispatch modes without removing them. A later iteration can replace the old conditions after active PRs are closed.
- Local Codex CLI setup is unchanged and has not been audited remotely.
