---
name: vercel
description: How Little Planet Factory agents work on projects deployed to Vercel — deploys happen only through git, never the Vercel CLI, unless the user asks otherwise; which CLI actions are allowed; environment variables and secrets; function limits; Next.js-on-Vercel, Blob, and DNS gotchas; and how to debug a deployment through logs instead of redeploying. Use when a project has vercel.json, a .vercel/ directory, @vercel/* dependencies, or the user says it deploys to Vercel.
user-invocable: false
---

# Vercel

## Deploys happen through git

Never deploy from the command line. A deployment comes from pushing a commit to a branch Vercel's Git integration watches: production from the production branch, previews from everything else. That holds even when the working tree is clean and matches the remote. A CLI deploy has no commit behind it, so nobody can audit, revert, or bisect it.

**Forbidden unless the user explicitly asks for that specific action:** `vercel`, `vercel deploy` (including `--prebuilt`), `vercel --prod`, `vercel redeploy`, `vercel promote`, `vercel rollback`, and deploy hooks or API calls that create deployments.

**Allowed, because they're configuration and inspection, not deploys:** `vercel link`, `vercel project ls` and `inspect`, `vercel ls`, `vercel inspect`, `vercel logs`, `vercel env ls`/`pull`, `vercel domains inspect`, and `vercel build` (builds into `.vercel/output` and uploads nothing; the upload is `vercel deploy --prebuilt`, which is forbidden). Changes to shared configuration — `vercel env add`/`rm`, `vercel domains add`, creating stores, `vercel git connect` — alter what every deployment sees, so do them only when the brief or the user calls for them.

Pushing is governed by the version-control skill. If the policy doesn't allow a push, the change isn't deployable by you: finish the work and report that pushing it will deploy it. Don't reach for the CLI as a way around the policy.

**When a change isn't live:**

1. Check whether it was pushed: `git log origin/<branch>..HEAD` should be empty.
2. Check whether the project is connected to git. `vercel project inspect <name>` shows a Git Repository section when it is. A `vercel ls` full of short CLI deployments with no branch information means auto-deploy was never set up.
3. If the integration is missing, report it and stop. Don't deploy around it.
4. To redeploy without code changes (for example, after an env var change, which only takes effect on the next deployment), push an empty commit where the policy allows it, or ask the user.

Identify projects by `projectId` (in `.vercel/project.json`), not by name. After a rename, looking a project up by its old name returns `project_not_found` even though the project still exists. Match on the ID in `vercel project ls`.

In non-interactive runs, pass `--scope <team>`. A JSON reply with `"action_required"` usually means the scope is missing. The team that owns a domain can differ from the CLI's default scope.

## Environment variables and secrets

- **Vercel is the source of truth for env vars in a linked project.** Don't hand-create or edit `.env*` files. Add the var in Vercel for the right environments (Development, Preview, Production), then `vercel env pull`. A pulled `.env.local` is generated, and the next pull overwrites anything appended by hand.
- **A pulled value of literal `[SENSITIVE]`** means the value wasn't readable. Either the variable is Vercel's write-only Sensitive type, or your environment masked it. Either way the value can't be verified or copied locally. Don't try to recover it, and don't copy secrets between projects. Suggest team-level shared variables for a credential several projects use.
- **Agents never generate, read back, or relay secret values.** When a secret needs setting, tell the user the variable name, the environments, and how to generate it, and let them set it. Never write secret values to logs, reports, commits, or the knowledge vault.
- **Don't pull production env vars** to run a local workflow that has its own credentials.
- **Cron endpoints** check `Authorization: Bearer <CRON_SECRET>` with a constant-time compare, and fail closed when `CRON_SECRET` is unset.

## Functions and runtime

- **Request and response bodies are capped at 4.5 MB.** Move large files through Blob (a presigned upload from the client, a redirect to a presigned download) rather than through the function.
- **Held-open connections cost money under Fluid Compute**, which bills for as long as a function instance is open. Avoid SSE and long-lived streams where request/response works. In-memory session state doesn't survive across instances. When retiring a costly path, remove it (return 410) — a deprecation header doesn't stop configured clients from calling it.
- **MCP servers on Vercel** use the stateless Streamable HTTP transport (`sessionIdGenerator: undefined`, `enableJsonResponse: true`), POST only, with GET and DELETE answered 405. Clean up in `finally`, not on `res.on("close")`, which also fires on client abort.
- **The Host header is rewritten**, so `req.url` in a handler doesn't match the public URL a caller signed. Rebuild the URL from a configured public base URL plus the path and query before verifying a URL-signed webhook.
- **Keep scheduled work well under `maxDuration`.** Put per-request timeouts on outbound calls.
- **Prefer the Node runtime to Edge** unless the project already uses Edge. Read bundled files with `fs` from `process.cwd()` at module scope. `fetch(new URL('./file', import.meta.url))` works only on Edge.
- **Plain Vercel Functions in TypeScript** (outside a framework) keep import specifiers as written. Use `.js` specifiers with `NodeNext` resolution, or every request fails with `ERR_MODULE_NOT_FOUND`. `vercel build` locally, then import the built output, to confirm.

## Next.js on Vercel

- **Server code must not fetch the app's own API routes over HTTP.** On protected preview deployments the request has no auth cookie. It's redirected to the Vercel login page, and `res.json()` throws on the HTML (`Unexpected token '<'`). Call the data layer directly. The same applies to `next/image` for gated images, since the optimizer fetches without the user's cookie. A hardcoded production URL in a self-fetch makes previews show production data.
- **Deployment Protection** can cover production on new projects, so public webhook endpoints return 401 until protection is limited to previews.
- **App Router dynamic params can arrive percent-encoded.** Decode any param used as a lookup key with `decodeURIComponent`, falling back to the raw value if decoding throws. Decode unconditionally, never based on the environment.
- **Next 16 middleware/proxy**: `middleware.ts` is renamed `proxy.ts` and its exported function `proxy`, and it runs on the Node runtime. Follow whichever the project's Next version uses. The exported matcher is still `config`. A wrong export name silently drops the matcher, and every route gets gated while build and tests still pass. The matcher must be a literal (it's read statically). Confirm it in `.next/server/functions-config-manifest.json`.
- **Next 16 `cacheComponents`**: a client component calling `useSearchParams()` on a statically prerendered route never mounts, and there's no error. Check third-party client components in the root layout. `useParams()` and `usePathname()` are safe.
- **Route handlers and the build (Next 16).** `next build` runs a GET handler that opts into static generation (`dynamic = 'force-static'` or `'error'`, a `revalidate` value, or `generateStaticParams`). A data client that needs runtime env vars then fails the build. Use `dynamic = "force-dynamic"` and cache inside the handler.
- **Cache invalidation (Next 16).** `revalidateTag(tag, "max")` only marks the entry stale, so the next request still gets old data. For webhook- or cron-driven invalidation use `revalidateTag(tag, { expire: 0 })`. `unstable_cache` persists across instances and deployments. `use cache` is in-memory per instance by default.
- **CDN-cached responses are functions of the URL only.** Don't read `cookies()` or `headers()` or render request-time values in them, or the first requester's variant is served to everyone.
- **OG images (`ImageResponse`/Satori)**: flexbox only, and every element with more than one child needs `display: flex`. Bundle TTF/OTF/WOFF fonts in the repo (no `.woff2`, no variable fonts, which crash at render time) rather than fetching them at runtime. Set `metadataBase`. Render a new image locally once, because failures appear only at render time.

## Build and packaging

- **Files read with `fs` at runtime** must be in the function bundle. Files under `app/` are traced automatically. Files at the project root or in `public/` need `outputFileTracingIncludes`, with repo-relative globs, never paths into a package-manager store. Confirm with the route's `.nft.json` under `.next/server/`. Missing files fail only in production (ENOENT).
- **pnpm doesn't hoist transitive dependencies.** Anything imported — including root-level scripts that `tsconfig` pulls into the type check — must be a direct dependency. Reproduce a Vercel-only build failure in a clean copy with `pnpm install --frozen-lockfile`, because a stale local `node_modules` hides it.
- **Native modules** (sharp and similar) can pass every local check and fail only in a deployed function. Treat a native dependency upgrade as verified only after a preview deployment has exercised it. Stay on the version the project pins unless the user wants the upgrade.
- **Don't inline large assets as base64.** They land in the function bundle.

## Storage (Blob)

- **Auth**: Blob v2 resolves an explicit `token`, then OIDC (`VERCEL_OIDC_TOKEN` with `BLOB_STORE_ID`), then `BLOB_READ_WRITE_TOKEN`. Gate on either `BLOB_STORE_ID` or `BLOB_READ_WRITE_TOKEN`, since which one a store injects varies, and don't pass `token` so OIDC is used on Vercel. `handleUpload()` needs a read-write token. Under OIDC, use the presigned upload flow.
- **Conditional writes**: `get()` returns a weak ETag (`W/"…"`) that `put(…, { ifMatch })` rejects as a mismatch (seen in `@vercel/blob` 2.8.0). Strip the `W/` prefix. The bug hides until the second write.
- **Read-modify-write with retries**: decide what to delete inside the retried callback, or a race orphans the newer blob.
- **Access is fixed when a store is created.** Anything gated belongs in a private store behind short-lived presigned URLs. Public blobs need unguessable paths (random suffixes), because a deterministic path is a permanent public URL.

## DNS and domains

A subdomain that resolves only through a `*` wildcard record stops resolving the moment any record is added beneath it (`_acme-challenge.x`, `_dmarc.x`, a TXT for verification). The name becomes an empty non-terminal and returns NODATA, taking the site down with no function logs. Give the subdomain an explicit record first — a CNAME to the target the domain config shows — before adding anything under it. Check with `dig +short <name>` before and after.

## Debugging a deployment

Diagnose from logs and inspection, never by deploying experiments.

- **Build logs**: `vercel inspect <deployment> --logs`, or the REST endpoint `GET /v3/deployments/{id}/events`, where the text and type fields are top-level on each event.
- **Runtime logs**: `vercel logs` tails from now, with no history. Retention depends on the plan and is short, so reproduce the request while tailing.
- **Previews behind protection**: `curl -sL` against the preview shows whether a failure is the login redirect.
- When the problem might be Vercel itself — elevated errors, stuck builds, DNS — check Telescope for a live incident before changing code.

Verify the effect you're reporting. A command that prints nothing may have failed: macOS has no `timeout` binary, and a pipe through `grep` or `tail` hides the exit status. Starting `next start` or a dev server to smoke-test needs the user's go-ahead. Otherwise, assert against build output, such as the compiled manifests and `.nft.json` files above.

## Splitting Vercel work across agents

`vercel.json`, `next.config.*`, middleware or proxy files, and the project's env var set are shared by every route. Each belongs to one unit. Changes to Vercel project settings, env vars, domains, and stores are made by the overseer (or the main session when there's no overseer) or the user, never by a manager or worker, and each one goes in the report.

## Review focus

Inspecting changes to a Vercel project, weight these: any deploy path other than git; hand-edited `.env` files or secret values in code, logs, or commits; server code fetching its own API; bodies that can exceed 4.5 MB; held-open connections; CDN-cached responses reading cookies or headers; runtime `fs` reads without tracing includes; matchers or static-generation settings that silently change behavior; and DNS changes under wildcard-resolved names.
