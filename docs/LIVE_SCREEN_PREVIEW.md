# Pipo live simulator screen preview

This is an optional **manual, read-only** preview of selected Pipo iOS screens on
GitHub's existing `macos-15` runner. It does not change the app or the normal
PR validation workflow. XCTest navigates the app; the viewer has no tap or
keyboard endpoint. The browser refreshes the simulator image about once per
second, so this is a low-frame-rate live view rather than a smooth 30 fps call.

## One-time setup

1. Review and merge the workflow PR to `main`. GitHub only exposes a new
   `workflow_dispatch` workflow in Actions after the workflow exists on the
   default branch. The job itself refuses any ref other than `main`.
2. In the repository's **Settings → Secrets and variables → Actions**, create
   the repository secret `PIPO_PREVIEW_EMAIL` with the single email address
   that should receive Cloudflare's one-time viewing PIN. Do not put the email
   into a workflow input, commit, issue, or public Actions log. The secret is
   passed only to `cloudflared --allowed-mail`.
3. Ensure GitHub Actions is enabled and the owner can open workflow run logs.
   No Tailscale or Cloudflare account is required for the viewer.

## Watch a session

1. Open **Actions → Pipo Live Screen Preview → Run workflow**.
2. Select `main` and choose `all`, `saving`, `overview`, or `auth`.
   `all` runs the named tests sequentially, not the full iOS test suite.
3. Wait for **Start email-protected read-only stream** to finish. Open its
   `trycloudflare.com` URL from the step notice or job summary. Enter the
   email configured in the secret and the PIN sent to that inbox.
4. The selected tour starts after 90 seconds. The URL works only while the
   workflow runs. The job stops after at most 35 minutes.

The recording and focused build/test logs are retained for seven days in the
`pipo-live-screen-<run-id>` artifact. The preview's test failure remains a
failure even when a playable recording exists.

## Scope and access

- Screens are driven by existing synthetic/debug UI fixtures. There are no
  real customer credentials, bank connections, transfers, or actual invites.
- The preview includes the code on `main`. Draft PR #104's auth screens are
  outside this first live session until they are merged or separately scoped.
- `all` covers selected auth safety, saving, Journey, Manage Plan, and card
  routes. It is not a claim that every app page or state was traversed.
- The origin HTTP server binds to `127.0.0.1` and exposes only page, health,
  and screenshot GET routes. Cloudflare Quick Tunnel enforces the allowed
  email PIN before a browser reaches them. The public tunnel URL appears in
  Actions logs, so keep the viewer email secret and use only synthetic data.
- Quick Tunnels are temporary development infrastructure with no uptime
  guarantee. If the tunnel or installed simulator is unavailable, the job
  fails without provisioning a new simulator or changing production settings.

Cloudflare Quick Tunnel reference:
https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
