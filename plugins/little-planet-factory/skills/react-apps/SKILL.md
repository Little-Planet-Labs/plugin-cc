---
name: react-apps
description: How Little Planet Factory agents work in React web apps (Vite, Next.js, Remix/React Router, CRA, and similar) — detecting the stack and its commands, verifying without starting dev servers, component and hook discipline, and how to split React work across parallel agents without colliding on shared files. Use when planning, implementing, or reviewing changes in a project whose package.json depends on react.
user-invocable: false
---

# React apps

## Detect the stack before planning

Read these first. They settle most decisions, and they're cheap:

- **Package manager** from the lockfile: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lock`/`bun.lockb` → bun, `package-lock.json` → npm. Use only that one. Running a different manager creates a second lockfile and silently changes resolved versions.
- **Framework and router** from `package.json` and config files: `next.config.*` (check for an `app/` versus `pages/` directory), `vite.config.*`, `react-router.config.*` or `remix.config.*`, `react-scripts`.
- **Scripts.** `package.json` `scripts` are the project's own names for typecheck, lint, test, and build. Prefer them over raw tool invocations, and note which ones exist. A missing `typecheck` script usually means `tsc --noEmit -p <tsconfig>`.
- **TypeScript posture.** `tsconfig` `strict`, path aliases (`paths`, `baseUrl`), and project references. Match the aliasing style the neighboring files use.
- **State, data, styling, UI kit.** Which state library (Redux Toolkit, Zustand, Jotai, context), data layer (TanStack Query, SWR, RTK Query, server components, loaders), styling (CSS Modules, Tailwind, emotion/styled-components, vanilla-extract), and component library or design system are in use. New code uses what's there.
- **Monorepo shape.** `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, or `workspaces` in `package.json`. Run commands scoped to the affected package (`pnpm --filter <pkg> …`, `turbo run … --filter`) rather than the whole repo.

Put what you found in every brief so workers don't re-derive it.

## Verify without a dev server

Never start a long-running dev server (`dev`, `start`, `vite`, `next dev`, `storybook`) unless the user asks. It never exits, it blocks the agent, and it holds ports the user may be using. Verification runs through commands that finish:

1. **Type check** the affected package.
2. **Lint** the changed files, using the project's config.
3. **Tests.** Run the ones covering the changed components or hooks with the project's runner (Vitest, Jest, Playwright component tests), in non-watch mode: `vitest run`, `jest --watchAll=false`, or `CI=true`.
4. **Build.** The lead runs the build on the integrated change when the work touches routing, config, bundler setup, server/client boundaries, or environment variables. Workers don't run full builds.

If a check can only be proven in a running app, say so in your report instead of starting a server.

## Components and hooks

- **Effects are for synchronizing with things outside React** — subscriptions, the DOM, timers, network requests the framework doesn't already own. Don't use one to derive state from props or state (compute it during render), to reset state when a prop changes (use a `key`), to respond to a user action (do it in the event handler), or to chain state updates. Every effect that subscribes, listens, or starts async work returns a cleanup, and async work guards against setting state after unmount or after its inputs change.
- **Dependency arrays are complete.** Fix a `react-hooks/exhaustive-deps` warning by restructuring — moving the function inside the effect, or depending on a primitive — not by suppressing the rule or leaving values out.
- **Hooks follow the rules**: called unconditionally, at the top level, in the same order every render.
- **Keys are stable identities** from the data, never array indexes on lists that reorder, filter, or insert.
- **Memoize for a reason.** Add `useMemo`, `useCallback`, or `memo` when a value feeds a dependency array, a memoized child, or measurably expensive work. If the project uses the React Compiler, don't add manual memoization at all.
- **Keep one source of truth.** Don't copy server data into local state; read it through the data layer. Don't mirror a prop into state unless the component deliberately takes over ownership after mount.
- **Server and client boundaries** (Next App Router, RSC). `"use client"` goes at the lowest component that needs interactivity, not on a page. Props crossing the boundary must be serializable. Server-only modules (secrets, database clients) never get imported from client components; guard them with `server-only` where the project does.
- **Accessibility.** Use semantic elements first: a `<button>` for actions, not a clickable `<div>`. Label inputs, keep focus management intact in modals and menus, and keep interactive elements keyboard-reachable. Follow the project's test-id convention if it has one.

## Scale

Treat these as correctness at realistic data sizes:

- Long lists (hundreds of rows or more) use the virtualization the project already has, and are paginated or filtered at the API rather than in the component.
- Requests that don't depend on each other run in parallel. A parent/child waterfall where each level fetches after mounting is a finding when the data layer supports prefetching or loaders.
- A context whose value changes often re-renders every consumer. Split it, or move the fast-changing value to a store with selectors.
- Don't import a whole library for one function when the project already has a lighter path.

## Dependencies

Don't add a package when the codebase already has a way to do the job. When a new dependency is warranted, say why in the report. Install it with the detected package manager, from the package it belongs to in a monorepo, and pin it the way neighboring dependencies are pinned.

## Splitting React work across agents

Some files in a React app are touched by nearly every feature. Each one belongs to exactly one unit or to the lead's integration step, never to two workers at once:

- `package.json` and the lockfile. Only one agent installs packages, and installs never run concurrently: two installs racing on one `node_modules` corrupt it.
- Route registries, router config, and file-based route layouts shared across features.
- Barrel files (`index.ts` re-exports), shared type modules, and generated API clients or schemas.
- Global stores (root reducer, store setup), theme and token files, i18n message catalogs.
- Root providers and app shells (`App.tsx`, `layout.tsx`, `main.tsx`).

When several units each need a line in one of these, give the lines to one owner (usually the lead during integration) and have the other units report the exact addition they need.

A good split follows feature or route boundaries: one unit per component tree or route, with the shared contract (props, hook signatures, API types) fixed in the briefs before dispatch.

## Review focus

Inspecting React changes, weight these: effects that should be derived state or event handlers; missing cleanups and stale closures; incomplete dependency arrays or suppressed hook lint; unstable keys; client-side filtering of data the API could filter; request waterfalls; secrets or server-only imports reaching client bundles; lost keyboard or screen-reader access; and new dependencies duplicating something the project already has.
