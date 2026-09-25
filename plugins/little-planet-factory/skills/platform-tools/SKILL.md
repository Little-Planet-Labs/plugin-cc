---
name: platform-tools
description: How Little Planet Factory agents use the Cadence and Telescope MCP servers when they are connected — knowledge vault, reports, specs, and upstream-incident diagnosis — with per-role responsibilities for the overseer, manager, worker, researcher, inspector, and signoff.
user-invocable: false
---

# Platform tools: Cadence and Telescope

Two MCP servers change how you work when they're connected. Both are optional: check which tools you actually have before relying on either, and never fail or stall because one is missing.

## Detecting them

The tool-name prefix depends on how the user connected the server (for example `mcp__cadence__…` or `mcp__claude_ai_Cadence__…`), so match on the tool name after the prefix:

- **Cadence** is present if you have tools such as `list_knowledge`, `get_knowledge`, `prepare_report_upload`, or `get_spec`.
- **Telescope** is present if you have `diagnose_suspected_failure` or `get_active_incidents`.

Tools may be deferred — listed by name but not yet loaded. Load the ones you need through tool search before calling them, batching several into one search.

If a server is present but its calls fail, continue with local context and say in your report that the lookup couldn't run.

## Cadence

When Cadence is present it is the home for durable knowledge, reports, and anything else it provides. Prefer a Cadence tool over any other way of doing the same job.

### Knowledge vault

The vault is durable project memory across sessions.

- **Search before non-trivial work.** Call `list_knowledge` with a query for the symbols, errors, and concepts the work touches, and run a separate query for each risky area involved — database, migrations, auth, telemetry, API patterns, environment variables, framework gotchas.
- **Vault versus code.** When an entry conflicts with the code in front of you, check the code, and say so if the conflict affects the work.
- **Saving.** Save only stable, non-obvious constraints, gotchas, and decisions — not routine implementation details or standard framework usage. Search first and prefer appending to a related entry over creating a near-duplicate. Set `projects` to the exact working-directory name.

### Reports

When the user wants a rich or shareable write-up, dashboard, or visualization, build it as a **Cadence report**: a self-contained single-page HTML document uploaded through `prepare_report_upload`. If a `create-report` skill is available, follow it. Reports can be filed with `folderPath`; `list_folders` shows what exists.

Never use the Artifact tool, or any other artifact or page-publishing mechanism, for reports while Cadence is present.

### Specs

Specs are opt-in: use them only when the user names one ("implement spec 14", "the next spec"). Load it with `get_spec`, or `list_specs` with `status: "ready"` for "the next". Its title, description, notes, and success criteria are the definition of done.

### Everything else Cadence provides

Slide decks, file storage, daily notes, research, prompts, release notes, and similar: when the user asks for something Cadence has a tool for, use Cadence rather than a local file or another service.

## Telescope

Telescope tracks live incidents at third-party providers — cloud hosts, APIs, SaaS platforms — from their status pages.

**Check Telescope before chasing a bug that another platform could be causing.** When you hit errors, timeouts, 5xx responses, auth or rate-limit failures, or unexpected behavior from an external service:

1. Call `diagnose_suspected_failure` first, with a short description of the behavior and any failing code, stack traces, or logs as `codeSnippets`.
2. If it matches an incident, stop debugging that path. Report the incident and its status-page link before changing any code to work around it.
3. If it's inconclusive, `get_active_incidents` gives the full open list. It costs more tokens, so use it only when the diagnosis doesn't settle it.
4. If a call returns `rate_limited`, wait `retryAfterSeconds` before trying again. Never retry in a loop.

A clean Telescope result means no known upstream incident, not proof the bug is local. Continue debugging normally.

## Responsibilities by role

### Overseer

- **Vault research.** Do it yourself during planning, once, and quote the relevant findings inline in every brief so managers and workers don't redo it inconsistently.
- **Specs.** You own them. Set the spec to `in_progress` when work starts, and pass its success criteria into briefs as the definition of done. Signoff checks off the criteria it verified with `set_spec_criterion`. You mark the spec `done` only when every criterion is checked, or the user has confirmed that each unchecked criterion was dropped. Ask them as an interview question; don't infer it from the conversation. otherwise leave it `in_progress` and tell the user what remains.
- **Vault writes.** You write them. Collect the "worth saving" flags from managers, workers, and inspection reports, and save what clears the bar before reporting done.
- **Reports and other Cadence output** the user asks for. Producing these isn't implementation, so the no-implementation rule doesn't apply.
- **Telescope.** When a unit reports an external-service failure, make sure Telescope was consulted before re-dispatching a fix.

### Manager

- **Vault research.** Run targeted searches for anything in your sub-task the overseer's brief didn't cover, and quote the findings in your workers' briefs.
- **No vault writes.** List anything worth saving, and any vault entry that conflicts with the code or brief, in your report to the overseer.
- **Telescope.** Consult it before re-dispatching a worker whose unit failed against an external service.

### Worker

- **Vault reads.** Trust the vault findings quoted in your brief. Run a targeted `list_knowledge` query only when you hit something the brief didn't cover — an unfamiliar subsystem, a surprising error, or a risky area.
- **No vault writes.** Flag findings worth saving, and any entry that contradicts your brief or the code, in your report.
- **Telescope.** Consult it before debugging any failure that involves an external service. Report a matched incident rather than coding around it.

### Researcher

- **Vault reads** are part of the job. Search the vault for the question you were sent, and cite the entries you rely on.
- **No vault writes.** List anything worth saving, and any entry that conflicts with the code, in your report.
- **Telescope.** For a question about a failure involving an external service, consult it first, and report a matched incident as a finding.
- **No reports.** You never build them; your output is the research report returned to your lead.

### Signoff

- **Specs.** Load the spec yourself. Check off each criterion you verified against evidence with `set_spec_criterion`. That's your only Cadence write. Never change the spec's status.
- **No vault writes.** List possible durable learnings in your report.
- **Other trackers.** Read tickets and issues for requirements, but never update them. List the updates for the overseer.

### Inspector

- **Vault adherence** is a check when Cadence is present. Search the vault for the areas the change touches, and treat a violation of a stored decision or constraint as a blocking finding, citing the entry.
- **Specs.** When the lead says a spec is involved, check its success criteria as part of brief compliance.
- **No vault writes.** Note possible durable learnings under Notes.
- **Telescope.** If a test or tooling failure involves an external service, check Telescope before reporting it as a defect in the change. Report a matched incident as environmental, not blocking.
- **No reports.** You never build them; your output is the inspection report returned to your lead.
