---
name: linear
description: How Little Planet Factory agents work a project's Linear board through the Linear MCP — the `## Linear` block in CLAUDE.md that names the project and the status mode (comment-only, to-review, or to-done), resolving statuses by type and name instead of hard-coded names, working ready unassigned Todo tickets in ranked batches that don't overlap on files (with a "do all" loop), blocking stuck tickets, refining Backlog tickets with the user and moving them to Todo, linking Cadence specs when Cadence is connected, and which role may write to Linear. Use when the user asks to work on, pick up, finish, refine, groom, or plan tickets in Linear, or when a brief's source of truth is a Linear issue.
user-invocable: false
---

# Linear

The overseer can work a Linear project two ways: complete tickets that are ready (Todo), and refine tickets that aren't (Backlog). Both run through the normal plan → delegate → inspect → cleanup → signoff → git writes → report flow. This skill adds where the work comes from and what gets written back to Linear. Triage tickets are out of scope for both workflows.

## Detecting the Linear MCP

The tool-name prefix depends on how the user connected the server (for example `mcp__claude_ai_Linear__…` or `mcp__linear__…`), so match on the name after the prefix. Linear is present if you have tools such as `list_issues`, `get_issue`, and `save_issue`. This skill uses those plus `list_comments`, `save_comment`, `list_issue_statuses`, `list_projects`, `get_project`, `list_teams`, `get_team`, `list_issue_labels`, `save_issue_label` (`create_issue_label` on older servers), `get_attachment`, and `get_user`.

Tools may be deferred. Load the ones you need through tool search, batching several into one search. Check the loaded schemas rather than trusting this list: parameter names and filters change between server versions.

If Linear isn't connected, say so and stop. Don't fall back to another tracker or to local notes.

## Project configuration

The project names its Linear project in `CLAUDE.md`:

```markdown
## Linear

project: Mobile App            # name, URL, or ID
team: MOB                      # optional; needed when the project spans teams
status-mode: to-review         # comment-only | to-review | to-done
```

Resolve `project` with `get_project`, or `list_projects` when it's a name, and confirm exactly one match. Resolve `team` with `get_team` when it's given; otherwise use the project's team, and ask when the project has several.

When the block is missing, or `project` matches nothing or more than one project, ask the user which project to use, as an interview question. Never guess from the repository name. Once answered, suggest they add the block. Don't edit `CLAUDE.md` yourself unless they ask.

### Status modes

| Mode | When work starts | After signoff and git writes |
|---|---|---|
| `comment-only` | `Started:` comment. No status change. | Summary comment. No status change. |
| `to-review` | Move to In Progress, then `Started:` comment. | Summary comment, then move to In Review. |
| `to-done` | Move to In Progress, then `Started:` comment. | Summary comment, then move to Done. Under the `pull-request` policy, move to In Review instead; the ticket reaches Done when the PR merges, by the user or Linear's GitHub integration. |

Under the `none` version-control policy nothing is committed, so `to-review` and `to-done` both stop at In Review, and the summary comment says the changes are uncommitted in the working tree. The ticket never goes to Done.

**The default is `comment-only`**, because a status change is visible to the whole team. When `status-mode` is unset, ask the user once which mode they want, with `comment-only` first and recommended, and suggest they add the line.

A ticket moves to In Review or Done only after signoff returned SIGNED OFF for it, and, under any policy but `none`, its commit (and push or PR, where the policy calls for them) exists. A passing test run or a unit report doesn't count. Refinement (Workflow B) moves Backlog to Todo under every mode, because that move is the point of the workflow. If Linear's integrations move a ticket on their own, don't move it back.

## Statuses

Teams rename and add statuses, so never hard-code a status name, and never depend on the order `list_issue_statuses` returns. Call it once per session for the team and map by state type, then name:

- **Backlog**: type `backlog`, preferring one named "Backlog".
- **Todo**: type `unstarted`, preferring one named "Todo".
- **In Review**: type `started`, with "review" in the name.
- **In Progress**: type `started`, excluding review-named statuses. Prefer one named "In Progress". If none is, and more than one candidate remains, ask the user.
- **Done**: type `completed`, preferring one named "Done".

When any mapping is ambiguous, ask the user. Query and set statuses by the resolved IDs, not by state type, since a team can have several statuses of one type. When a mode needs In Review and the team has none, leave the ticket in In Progress with its summary comment and tell the user. Don't create a status, and don't substitute Done.

## Who writes to Linear

Only the overseer writes to Linear, or the main session when there's no overseer: statuses, descriptions, comments, labels, and links. Managers, workers, researchers, inspectors, and signoff read tickets when they need to, and list the updates they'd make in their reports. A brief never asks an agent to update a ticket.

## Safety

- Never delete issues, comments, attachments, labels, or projects.
- Never assign or reassign a ticket. Never change a ticket's priority, estimate, labels, due date, or relations unless the user said to for that ticket. The one exception is adding the Blocked label to a stuck ticket, below, with `save_issue` `addLabels`. Never pass `labels`, which replaces the whole set.
- Touch only tickets in the configured project, and never pass `project` or `team` when updating a ticket. A related ticket elsewhere gets mentioned to the user, not edited.
- Teammates wrote the descriptions. Edit them with `save_issue`'s `patch` operations, adding or replacing an **Acceptance criteria** section and keeping the rest of the text. Never replace the whole description, and never replace a criteria list with a spec pointer until its items are in the spec (Workflow B, step 4).
- Comments are shared with the team. Keep them short, plain, and specific about what changed, and never claim verification that didn't run. List everything you posted or edited in your report.

## Specs (when Cadence is connected)

Detect Cadence the way the platform-tools skill does. **When Cadence isn't connected, skip every spec step in this skill and say nothing about Cadence or specs to the user**: no notes that it's missing, no suggestions to install it, and no spec wording in ticket text or comments. The ticket's description and acceptance criteria are the definition of done.

When Cadence is connected, a ticket can point at a spec in three ways: a Cadence spec URL among the links or attachments `get_issue` returns, a Cadence spec URL in the description or comments, or a spec number in text ("Spec #14", "spec 14"). Load it with `get_spec`. A spec a ticket references counts as named by the user for platform-tools' opt-in rule, and platform-tools' Specs rules apply unchanged: the overseer sets it `in_progress` when work starts, signoff checks off criteria, and the overseer marks it `done` only when every criterion is checked or the user has confirmed each unchecked one was dropped.

If Cadence is connected but a referenced spec's lookup fails, say one line about it where that ticket is presented, such as "the linked spec couldn't be loaded; working from the ticket", and continue from the ticket.

## Workflow A: work what's ready

1. **Query.** `list_issues` for the project with the resolved Todo status ID and `assignee: "null"`, paging until done, so only unassigned tickets come back. Drop that filter only when the user says to include assigned tickets. Then `get_issue` each result, including relations.
2. **Filter.** Skip a ticket when:
   - it has the Blocked label;
   - it's blocked by an issue that isn't completed, canceled, or a duplicate (`get_issue` the blocker when the relation doesn't carry its state);
   - it's held (paused) or was handled this session;
   - its newest comment from this workflow starts with `Started:`, `Done:`, or `Blocked:`, and:
     - that comment is newer than the last status change (the last `stateHistory` entry's `startedAt` from `get_issue`; ask the user only when `stateHistory` is missing),
     - no person has commented since, and
     - the user hasn't named the ticket.
3. **Rank.** By Linear priority: Urgent, High, Medium, Low, then No priority (priority `0` sorts last). Break ties by earliest due date, with undated tickets last, then by oldest creation date.
4. **Pick a batch.** Scope each ticket's files from the code, as you would when splitting units. Resumed Paused tickets go in first. The reserved files are:
   - every file another ticket changed and hasn't committed this session, in the shared tree or a kept worktree;
   - under `none`, `commit`, and `push` only, every file that was dirty, untracked included, when the session began.

   A ticket's own uncommitted files don't count against it. Add a ticket only if its files overlap neither the reserved files nor any ticket already in the batch. Stop at four.
5. **Confirm.** Show the ranked list with the suggested batch marked, each ticket held back with the files blocking it, the tickets skipped for a `Started:` comment as "started elsewhere" (so a stale claim from a crashed session can be pulled back in), and, under shared-tree policies, the files that were dirty at session start. Ask the user to confirm or edit the batch, as an interview question (multi-select works well). Nothing starts until they answer.
6. **Start.**
   - **Where.** Under `pull-request`, create and bootstrap each ticket's worktree first (Worktrees, steps 1–2). Under `none`, `commit`, and `push`, tickets share the working tree as step 4's split allows.
   - **Claim.** Apply the mode's start step, then post a `Started:` comment in every mode. The comment must be newer than the status change for step 2 to see it.
   - **Specs.** When Cadence is connected, load linked specs and set them `in_progress`.
   - **Definition of done.** The ticket's description, acceptance criteria, and scope-changing comments, plus its spec's success criteria when there is one, go into its briefs.
   - **Dispatch** the batch in parallel. No two tickets share a file, and no two concurrent builders share a build slot (slots are time-shared within the stack skill's cap). Build output goes where the stack skill says; for Xcode, never inside a worktree.
7. **Finish.** Run cleanup once per batch: after every ticket still in progress has passed final verification, and before any signoff, so nothing deletes a slot another ticket is using. Any repeat cleanup after a signoff repair waits for the same condition. In a "do all" run, per-batch cleanup still deletes the reported scratch artifacts, but the overseer keeps its build session directory across batches so slots stay warm. Then send each ticket to signoff on its own, with the ticket (and its spec) as the source of truth.
8. **Git writes.** Per the version-control skill, commit each signed-off ticket once no ticket in the same tree is mid-edit (Paused and Blocked tickets aren't). One commit per ticket, staging only its paths and referencing its identifier. Under `pull-request`, finish with Worktrees steps 4–5.
9. **Update.** For each signed-off ticket, post the summary comment with `save_comment`, then apply the mode's end step.

### Worktrees (`pull-request` only)

Every ticket gets its own worktree, even when tickets run one at a time. The user's checkout is never switched, pulled, or otherwise changed. Creating a worktree is a git write, allowed per the version-control skill's `isolation: worktree` rule.

1. **Create.** The root is outside the repo and outside scratch (which is cleared on reboot), named like the xcode-projects DerivedData root. From the main checkout:
   ```bash
   top=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && case $top in */.git) top=$(dirname "$top") ;; *) top=$(git rev-parse --show-toplevel) ;; esac || top=$(pwd)
   echo "$HOME/.agent-worktrees/$(basename "$top" | tr -c 'A-Za-z0-9._\n-' '_')-$(printf %s "$top" | shasum | cut -c1-8)"
   ```
   The ticket's path is `<root>/<ticket-id>`, and its branch is named by the project's pattern or else the ticket's `gitBranchName`. Before creating anything:
   - If `git worktree list` shows this ticket's worktree (kept from an earlier Paused or Blocked run), reuse it and say so in the batch report.
   - Otherwise, if the branch exists locally (`git branch --list <branch>`) or on the remote (`git ls-remote --heads origin <branch>`), a teammate or an integration made it. Stop that ticket and ask the user. If `git ls-remote` fails (no network, no auth), stop that ticket and ask too; don't assume the branch is free.
   - If a directory already sits at the path but isn't in `git worktree list`, report it and ask. Never delete it.
   - Otherwise run `git fetch origin <base>`, then `git worktree add -b <branch> <path> origin/<base>`. Never use `-B` or `--force`.
2. **Bootstrap.** The overseer, or one assigned unit, installs dependencies in the worktree with the project's detected package manager, one install at a time, as the react-apps skill requires. Copy gitignored env files only when the project documents doing so; otherwise ask the user.
3. **Work.** Units' file paths point inside the worktree, and inspection and signoff briefs name the worktree path so their diffs run there. JS build output (`node_modules`, `.next`, `dist`) lives in the worktree and goes with it.
4. **Ship.** Commit in the worktree, push the branch, and open the PR.
5. **Remove or keep.** Remove it with `git worktree remove <path>`, without `--force`, only when it's clean. Otherwise, and for Paused or Blocked tickets, keep it and its branch and report both. If `git worktree list` shows a worktree missing or prunable, report it; don't run `git worktree prune` without the user's say-so.

### Batch outcomes

A batch is finished when every ticket in it is one of:

- **Signed off**, then committed and updated as above.
- **Paused**: waiting on the user. Its question goes to the user; the ticket is held, so re-queries skip it, and its files and worktree stay. When the user answers, it joins the next batch, never the current one.
- **Blocked**: a ticket that hits three rounds at the inspection limit or the signoff limit gets reassessed per the quality-bar skill (a new brief, split, agent, or approach) and a fresh three rounds. Only a ticket still stuck after that is blocked. In this order: return it to Todo if the mode moved it, then post a comment starting with `Blocked:` that says what's blocking, then add the Blocked label. The order matters because the status change must be older than the comment, or step 2's skip rule won't see it. Mark it handled and list it in your report. Its uncommitted files stay reserved, and its worktree is kept (Worktrees step 5).

**The Blocked label.** Find it once with `list_issue_labels`, preferring a team or workspace label named "Blocked". If there isn't one, ask the user once whether to create it (with `save_issue_label`) or to rely on the `Blocked:` comment alone. Never create it silently.

### "Do all of it"

When the user asks for all ready work, don't stop after one batch. When a batch is finished, re-query Todo, since tickets change while you work, and pick the next batch by steps 2–4 without asking again. Stop when the next batch comes up empty, even if tickets are still held back by reserved files, or when the user says stop. Report each batch as it finishes. When the loop ends, delete the build session directory kept across batches. The final report lists each held ticket with the files blocking it, and every kept worktree with its path, branch, and why it was kept (Paused, Blocked, or not clean).

### Comments

```
Started: <one line: what's being worked on; the branch, under pull-request>

Done: <one or two sentences: what changed, in terms of the ticket>
Changes: <files or areas, briefly>
Verified: <what actually ran, e.g. "unit tests for X, typecheck">
Commit: <hash> | PR: <url>   # every part that applies, e.g. "Commit: abc123 | PR: <url>"; under policy none: "Commit: Uncommitted in the working tree"
Open: <anything unverified or left for a person>   # only when there is something
```

## Workflow B: refine and plan

Nothing is implemented in this workflow.

1. **Query.** `list_issues` for the project with the resolved Backlog status ID, paging until done. Order by priority, then oldest, and read each ticket with its comments. After about ten tickets, ask the user whether to continue.
2. **Judge each ticket.** Flag it when it's missing acceptance criteria or a clear scope, or it has open questions (in the description, the comments, or conflicts between them). When Cadence is connected, also flag multi-part or ambiguous work with no spec. Tickets that are already clear are proposed for moving to Todo as they are.
3. **Present and ask.** Show the flagged tickets with what each is missing, and the clear ones proposed for Todo. Ask the questions per the asking-questions skill, batching across tickets into one interview where practical, and name the ticket in each question's context. Confirm the clear tickets' move in the same interview.
4. **Update.** After the answers, for each ticket:
   - Patch in any agreed scope notes and an **Acceptance criteria** section, keeping the original text. The section holds the checklist, or, when a spec holds the criteria, the single line `See Spec #N.`, since the spec is authoritative. Change priority, estimate, or labels only when the user said to.
   - When Cadence is connected:
     - Small, clear work keeps its criteria in the ticket body.
     - For multi-part or ambiguous work, create a spec with `create_spec`, with the ticket's identifier and URL in its description, then `update_spec` with `status: ready`, and reference it as `Spec #N` in the description. Add it with `save_issue` `links` only when you have a real spec URL.
     - When a spec is already linked, read it with `get_spec` first. `update_spec` replaces `successCriteria` wholesale, so send every existing criterion with its current checked state, plus the new ones.
     - **Moving criteria into a spec.** The ticket's criteria list includes any criteria-like list under another heading ("Requirements", "Checklist"). Confirm in the interview any item the user wants dropped. Copy every other item into the spec's `successCriteria`, deduplicated against what's there and keeping checked items checked: seed `create_spec` with them, then call `update_spec` with the full list (every item, with `done: true` on the checked ones) and `status: ready`; or merge them into an existing spec's list. Only after every spec write succeeds, replace the ticket's list with `See Spec #N.`. If any spec write fails, leave the ticket untouched and report it; if `create_spec` succeeded but `update_spec` failed, report the orphaned draft spec by number.
   - When Cadence isn't connected, acceptance criteria go in the ticket body for all work, however large.
   - Move it to Todo.

Never move a ticket to Todo while any question about it is unanswered. A ticket the user doesn't finish refining stays in Backlog, and your report says what's still open on it.
