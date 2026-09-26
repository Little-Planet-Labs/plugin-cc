---
name: vercel
description: How Little Planet Factory agents work on projects deployed to Vercel — deploys happen only through git, never the Vercel CLI, unless the user asks otherwise; which CLI actions are allowed; environment variables and secrets; firm defaults (Vercel Web Analytics and Speed Insights always enabled, and never Neon or any Neon-backed database) unless the user asks otherwise; function limits and costs; Next.js-on-Vercel rules; build tracing; Blob access; and how to debug a deployment through logs instead of redeploying. Use when a project has vercel.json, a .vercel/ directory, @vercel/* dependencies, or the user says it deploys to Vercel.
user-invocable: false
---

# Vercel

## Deploys happen through git

Never deploy from the command line. A deployment comes from pushing a commit to a branch Vercel's Git integration watches: production from the production branch, previews from everything else. That holds even when the working tree is clean and matches the remote. A CLI deploy has no commit behind it, so nobody can audit, revert, or bisect it.

**Forbidden unless the user explicitly asks for that specific action:** `vercel`, `vercel deploy` (including `--prebuilt`), `vercel --prod`, `vercel redeploy`, `vercel promote`, `vercel rollback`, and deploy hooks or API calls that create deployments.

**Allowed, because they're configuration and inspection, not deploys:** `vercel link`, `vercel project ls` and `inspect`, `vercel ls`, `vercel inspect`, `vercel logs`, `vercel env ls`/`pull`/`run`, `vercel domains inspect`, and `vercel build`. `vercel build` creates no deployment, but it needs `vercel pull` first (which downloads env vars into `.vercel/`); don't pass `--prod`. The upload step is `vercel deploy --prebuilt`, which is forbidden. Changes to shared configuration — `vercel env add`/`rm`, `vercel domains add`, creating stores, `vercel git connect` — alter what every deployment sees, so do them only when the brief or the user calls for them.

Pushing is governed by the version-control skill. If the policy doesn't allow a push, the change isn't deployable by you: finish the work and report that pushing it will deploy it. Don't reach for the CLI as a way around the policy.

**When a change isn't live:**

1. Check whether it was pushed: `git log origin/<branch>..HEAD` should be empty.
2. Check whether the project is connected to git. `vercel project inspect <name>` shows a Git Repository section when it is. A `vercel ls` full of short CLI deployments with no branch information means auto-deploy was never set up.
3. If the integration is missing, report it and stop. Don't deploy around it.
4. To redeploy without code changes (for example, after an env var change, which only takes effect on the next deployment), push an empty commit where the policy allows it, or ask the user.

Identify projects by `projectId` (in `.vercel/project.json`), not by name. In non-interactive runs, pass `--scope <team>` or set `VERCEL_ORG_ID`/`VERCEL_PROJECT_ID`.

## Environment variables and secrets

- **Vercel is the source of truth for env vars in a linked project.** Don't hand-create or edit `.env*` files. Add the var in Vercel for the right environments (Development, Preview, Production), then `vercel env pull`. The pulled env file (`.env.local` in the CLI docs' examples) is generated, and the next pull overwrites anything appended by hand. `vercel env run -- <cmd>` injects env vars without writing a file.
- **A pulled value that's masked or unreadable** can't be verified or copied locally, whether the variable is Vercel's write-only **Secret** type (formerly Sensitive) or your environment masked it. Don't try to recover it, and don't copy secrets between projects. Suggest team-level shared variables for a credential several projects use.
- **Agents never generate, read back, or relay secret values.** When a secret needs setting, tell the user the variable name, the environments, and how to generate it, and let them set it. Never write secret values to logs, reports, commits, or the knowledge vault.
- **Don't pull production env vars** to run a local workflow that has its own credentials.
- **Cron endpoints** check `Authorization: Bearer <CRON_SECRET>` and fail closed when `CRON_SECRET` is unset. Vercel's example uses a plain compare; a constant-time compare is good practice.

## Functions and runtime

- **Request and response bodies are capped at 4.5 MB.** Move large files through Blob (a presigned upload from the client, a redirect to a presigned download) rather than through the function.
- **Held-open connections cost money under Fluid Compute.** Active CPU pauses while you wait on I/O, but Provisioned Memory is billed for as long as any request on the instance is in flight, so an open SSE stream or long poll bills memory for its whole lifetime. Avoid them where request/response works.
- **In-memory session state doesn't survive across instances.**
- **Keep scheduled work well under `maxDuration`.** Put per-request timeouts on outbound calls.
- **Runtime:** in Next.js, follow `nextjs` (Edge is deprecated in 16). For other Vercel Functions, prefer Node unless the project already uses Edge.

## Next.js on Vercel

Framework-level Next.js rules live in the `nextjs` skill.

- **Server code must not fetch the app's own API routes over HTTP.** On protected preview deployments the request has no auth cookie, so it's sent to the Vercel login page instead of the route. Call the data layer directly. If a same-origin fetch is unavoidable, forward the incoming request's cookies or send `x-vercel-protection-bypass`. A hardcoded production URL in a self-fetch makes previews show production data. Next's image optimizer also fetches without the user's cookies, so don't rely on gated images through the optimizer.
- **Deployment Protection can cover production.** "All Deployments" is free on every plan and can be a team default for new projects, and Standard Protection already gates the production `*.vercel.app` URL. Public webhook endpoints fail until the scope excludes them or a bypass is configured.
- **CDN-cached responses** (any response with a shared-cache `s-maxage`) are keyed by the URL plus `Accept`/`Accept-Encoding` and any `Vary` headers. Don't read `cookies()` or `headers()` or render request-time values in them, or the first requester's variant is served to everyone.

## Web Analytics and Speed Insights

Unless the user asks otherwise, every Vercel project gets both.

- **Web Analytics**: install `@vercel/analytics` and render `<Analytics />` from `@vercel/analytics/next` inside the root layout's `<body>`.
- **Speed Insights**: install `@vercel/speed-insights` and render `<SpeedInsights />` from `@vercel/speed-insights/next` in the same place. This is Vercel Speed Insights (real-user Core Web Vitals), not Google PageSpeed Insights. It needs no enable step; data shows in the project's Speed Insights tab (vercel.com/docs/speed-insights/quickstart).
- **Other frameworks** use the package's framework subpath instead of `/next` (for example `/react`, `/sveltekit`, `/astro`, `/remix`).
- **Web Analytics also has to be enabled under Analytics in the project sidebar.** Deploying the tracking code without it is a documented failure mode (vercel.com/docs/analytics/quickstart, vercel.com/docs/analytics/troubleshooting); routes appear on the deployment after enabling. The toggle changes project settings, so under the rule in Splitting Vercel work across agents it's the user's or overseer's action: the agent reports that it needs doing.
- **Vercel's quickstarts say to deploy with `vercel --prod`.** Ignore that step; deploys go through git.
- **Both components inject their scripts client-side only.** In development they load a debug script and track nothing (package READMEs). Off Vercel, the script 404s and only logs to the console.

## Databases

- **Never use Neon.** That covers Neon directly, the Neon integration from the Vercel Marketplace, and Vercel Postgres, which is no longer offered: Vercel moved existing Vercel Postgres databases to Neon in December 2024 (vercel.com/docs/postgres).
- **When a project needs a database, ask the user which one.** Don't pick a default. Provisioning a store is a shared-configuration change, so it follows the same rule as other project settings.

## Build and packaging

- **Files read with `fs` at runtime must be in the function bundle.** Tracing is static analysis, not a directory rule. In 16.3.0, Turbopack traced literal `join(process.cwd(), …)` paths in the root, `public/`, and `app/`, while `--webpack` traced none of them. Computed paths aren't traced. Always check the route's `.nft.json` under `.next/server/`, and add `outputFileTracingIncludes` (repo-relative globs, never package-manager store paths) for anything missing. Missing files fail only in production (ENOENT).
- **Native modules** can pass every local check and fail only in a deployed function. Treat a native dependency upgrade as verified only after a preview deployment has exercised it. Stay on the version the project pins unless the user wants the upgrade.
- **Don't inline large assets as base64.** They land in the function bundle.

## Storage (Blob)

- **Access is fixed when a store is created.**
- **Gated content goes in a private store** behind short-lived presigned URLs.
- **Public blob paths must be unguessable** (random suffixes), because a deterministic path is a permanent public URL.

## Debugging a deployment

Diagnose from logs and inspection, never by deploying experiments.

- **Build logs**: `vercel inspect <deployment> --logs`, or the REST endpoint `GET /v3/deployments/{id}/events`.
- **Runtime logs**: `vercel logs` queries the last 24 hours by default (`--since`/`--until`, `--level error`, `--status-code 5xx`, `--query`, `--json`). Use `--follow` to tail live, for up to 5 minutes.
- **Previews behind protection**: `curl -sL` against the preview shows whether a failure is the login redirect.
- When the problem might be Vercel itself — elevated errors, stuck builds, DNS — check Telescope for a live incident before changing code.

Verify the effect you're reporting. A command that prints nothing may have failed: macOS has no `timeout` binary, and a pipe through `grep` or `tail` hides the exit status. Starting `next start` or a dev server to smoke-test needs the user's go-ahead. Otherwise, assert against build output, such as the compiled manifests and `.nft.json` files above.

## Splitting Vercel work across agents

`vercel.json`, `next.config.*`, middleware or proxy files, and the project's env var set are shared by every route. Each belongs to one unit. Changes to Vercel project settings, env vars, domains, and stores are made by the overseer (or the main session when there's no overseer) or the user, never by a manager or worker, and each one goes in the report.

## Review focus

Inspecting changes to a Vercel project, weight these: any deploy path other than git; a missing `<Analytics />` or `<SpeedInsights />`; any Neon dependency, Neon Marketplace integration, or Vercel Postgres usage; hand-edited `.env` files or secret values in code, logs, or commits; server code fetching its own API; bodies that can exceed 4.5 MB; held-open connections; CDN-cached responses reading cookies or headers; runtime `fs` reads missing from the route's `.nft.json`; and public blobs at guessable paths.
