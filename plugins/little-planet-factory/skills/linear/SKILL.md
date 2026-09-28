---
name: linear
description: How Little Planet Factory agents work a project's Linear board through the Linear MCP — the `## Linear` block in CLAUDE.md that names the project and the status mode (comment-only, to-review, or to-done), resolving statuses by type and name instead of hard-coded names, working ready unassigned Todo tickets in ranked batches that don't overlap on files or build together (with a "do all" loop), blocking stuck tickets, refining Backlog tickets with the user and moving them to Todo, linking Cadence specs when Cadence is connected, and which role may write to Linear. Use when the user asks to work on, pick up, finish, refine, groom, or plan tickets in Linear, or when a brief's source of truth is a Linear issue.
user-invocable: false
---

# Linear

The overseer can work a Linear project two ways: complete tickets that are ready (Todo), and refine tickets that aren't (Backlog). Both run through the normal plan → delegate → inspect → cleanup → signoff → git writes → report flow. Under `pull-request`, the PR's review and the PR review signoff come between the git writes and the report, when the version-control skill says they apply. This skill adds where the work comes from and what gets written back to Linear. Triage tickets are out of scope for both workflows.

**Compaction.** In a Linear run, keep the run's Linear state in the ledger's Linear section (Workflow A, Ledger), per the overseer's Ledger section. Compaction keeps only the start of this skill, so after compaction re-invoke it before any Linear read or write, and follow Ledger's recovery steps.

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
- Comments are shared with the team. Write them to the format in Workflow A's Comments section, and never claim verification that didn't run. List everything you posted or edited in your report.

## Specs (when Cadence is connected)

Detect Cadence the way the platform-tools skill does. **When Cadence isn't connected, skip every spec step in this skill and say nothing about Cadence or specs to the user**: no notes that it's missing, no suggestions to install it, and no spec wording in ticket text or comments. The ticket's description and acceptance criteria are the definition of done.

When Cadence is connected, a ticket can point at a spec in three ways: a Cadence spec URL among the links or attachments `get_issue` returns, a Cadence spec URL in the description or comments, or a spec number in text ("Spec #14", "spec 14"). Load it with `get_spec`. A spec a ticket references counts as named by the user for platform-tools' opt-in rule, and platform-tools' Specs rules apply unchanged: the overseer sets it `in_progress` when work starts, signoff checks off criteria, and the overseer marks it `done` only when every criterion is checked or the user has confirmed each unchecked one was dropped.

If Cadence is connected but a referenced spec's lookup fails, say one line about it where that ticket is presented, such as "the linked spec couldn't be loaded; working from the ticket", and continue from the ticket.

## Workflow A: work what's ready

1. **Query.** `list_issues` for the project with the resolved Todo status ID and `assignee: "null"`, paging until done, so only unassigned tickets come back. Drop that filter only when the user says to include assigned tickets. Then `get_issue` each result, including relations. Remove resumed Paused or Halted tickets from the results before filtering. They skip step 2's claim-comment and held checks, since those were ours, but nothing else: `get_issue` each one and check that it doesn't have the Blocked label, isn't blocked by an issue that isn't completed, canceled, or a duplicate, is still in the configured project, isn't completed or canceled, and isn't assigned to someone, unless the user included assigned tickets or named this ticket earlier in the session. If any check fails, don't resume it. It stays Paused or Halted and is shown as held, with the failed check as its reason (such as "canceled by a teammate" or "now blocked by ABC-9"), in step 5 and the final report. When the check shows the ticket is dead (completed, canceled, moved out of the project, or assigned to someone else), its uncommitted work is handled by policy:
   - **`pull-request`.** Its edits are isolated in its own worktree. Ask the user, as an interview question, whether to release it, so other tickets may touch or build over its files. Releasing is the default and recommended option, and it lifts both its file reservation and its build-together hold (step 4). Either way its worktree and branch are kept per Worktrees step 5, and nothing is deleted.
   - **`none`, `commit`, and `push`.** Its edits sit in the shared working tree, so don't offer a release. Its files stay reserved and its build-together hold stays. Tell the user the ticket is dead and list its uncommitted files by path, for them to keep, commit, or discard. Never discard them yourself. It's released only once `git status` shows those files clean.

   A Blocked label or an open blocker isn't dead: the ticket stays held and its files stay reserved. The rest rejoin at step 4.
2. **Filter.** Skip a ticket when:
   - it has the Blocked label;
   - it's blocked by an issue that isn't completed, canceled, or a duplicate (`get_issue` the blocker when the relation doesn't carry its state);
   - it's held (Paused or Halted) or was handled this session;
   - its newest comment from this workflow starts with the label `Started:`, `Progress:`, `Paused:`, `Done:`, or `Blocked:`, bold (`**Done:**`) or plain (older comments), and:
     - that comment is newer than the last status change (the last `stateHistory` entry's `startedAt` from `get_issue`; ask the user only when `stateHistory` is missing),
     - no person has commented since, and
     - the user hasn't named the ticket.

   To read the label, take the comment's raw body, strip leading whitespace and markdown emphasis (`*` and `_`), and check what's left.
3. **Rank.** By Linear priority: Urgent, High, Medium, Low, then No priority (priority `0` sorts last). Break ties by earliest due date, with undated tickets last, then by oldest creation date.
4. **Pick a batch.** Scope each ticket's files, and what its builds and tests compile, from the code, as you would when splitting units. Resumed Paused or Halted tickets go in first; this step's rules against tickets already in the batch still apply. The reserved files are:
   - every file another ticket changed and hasn't committed this session, in the shared tree or a kept worktree;
   - under `none`, `commit`, and `push` only, every file that was dirty, untracked included, when the session began.

   A ticket's own uncommitted files don't count against it. A released ticket (step 1) reserves nothing and holds nothing back, so neither its files nor the build-together clause below apply to it. Add a ticket only if its files overlap neither the reserved files nor any ticket already in the batch, and it doesn't **build together** (overseer, Plan and delegate step 2) with a ticket already in the batch or, unless the user added it anyway, with a Paused, Blocked, or Halted ticket's uncommitted files. Stop at four.
5. **Confirm.** Show the ranked list with the suggested batch marked, each ticket held back with what's blocking it (its overlapping files, or what it builds together with, such as "builds together with ABC-12 (MyApp)" or "MyApp has ABC-9's unfinished work (Paused)"), the tickets skipped for a `Started:`, `Progress:`, or `Paused:` comment as "started elsewhere" (so a stale claim from a crashed session can be pulled back in), except a Paused or Halted ticket from this session, which is shown as held (with its failed resume check as the reason, when it has one), and, under shared-tree policies, the files that were dirty at session start. Ask the user to confirm or edit the batch, as an interview question (multi-select works well). Nothing starts until they answer. A ticket held back for building together that the user adds anyway waits for the next batch; tell the user. When the current batch finishes, it's ranked first for the next batch, after resumed Paused or Halted tickets, starting one by steps 2–5 if no batch is running; step 4's rules against tickets already in the batch still apply. If it was held back for a Paused, Blocked, or Halted ticket's unfinished work, tell them its build may fail on that work.
6. **Start.**
   - **Where.** Under `pull-request`, create and bootstrap each ticket's worktree first (Worktrees, steps 1–2). Under `none`, `commit`, and `push`, tickets share the working tree as step 4's split allows.
   - **Claim.** Apply the mode's start step, then post a `Started:` comment, with its Plan (Comments), in every mode. The comment must be newer than the status change for step 2 to see it. Then schedule the wake-up (Progress check).
   - **Specs.** When Cadence is connected, load linked specs and set them `in_progress`.
   - **Definition of done.** The ticket's description, acceptance criteria, and scope-changing comments, plus its spec's success criteria when there is one, go into its briefs.
   - **Dispatch** the batch in parallel. No two tickets in the batch share a file or build together, and no two concurrent builders share a build slot (slots are time-shared within the stack skill's cap). Build output goes where the stack skill says; for Xcode, never inside a worktree.
   - **Milestones.** While tickets run, post comments as Comments' "When to post" says.
7. **Finish.** Run cleanup once per batch: after every ticket still in progress has passed final verification, and before any signoff, so nothing deletes a slot another ticket is using. Any repeat cleanup after a signoff repair waits for the same condition. In a "do all" run, per-batch cleanup still deletes the reported scratch artifacts, but the overseer keeps its build session directory across batches so slots stay warm. Cleanup leaves the progress wake-up running while any ticket is in progress; it's cancelled when the batch finishes (Progress check). Then send each ticket to signoff on its own, with the ticket (and its spec) as the source of truth.
8. **Git writes.** Per the version-control skill, commit each signed-off ticket once no ticket in the same tree is mid-edit (Paused, Blocked, and Halted tickets aren't). One commit per ticket, staging only its paths and referencing its identifier. Under `pull-request`, finish with Worktrees steps 4–5. The ticket stays in progress through its PR's review, so the progress check keeps covering it.
9. **Update.** For each signed-off ticket (under `pull-request`, once its PR review signoff returned SIGNED OFF, when PR review applies), post the summary comment with `save_comment`, then apply the mode's end step. When the batch finishes with nothing in progress, cancel the progress wake-up (Progress check).

### Worktrees (`pull-request` only)

Every ticket gets its own worktree, even when tickets run one at a time. The user's checkout is never switched, pulled, or otherwise changed. Creating a worktree is a git write, allowed per the version-control skill's `isolation: worktree` rule.

1. **Create.** The root is outside the repo and outside scratch (which is cleared on reboot), named like the xcode-projects DerivedData root. From the main checkout:
   ```bash
   top=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && case $top in */.git) top=$(dirname "$top") ;; *) top=$(git rev-parse --show-toplevel) ;; esac || top=$(pwd)
   echo "$HOME/.agent-worktrees/$(basename "$top" | tr -c 'A-Za-z0-9._\n-' '_')-$(printf %s "$top" | shasum | cut -c1-8)"
   ```
   The ticket's path is `<root>/<ticket-id>`, and its branch is named by the project's pattern or else the ticket's `gitBranchName`. Before creating anything:
   - If `git worktree list` shows this ticket's worktree (kept from an earlier Paused, Blocked, or Halted run), reuse it and say so in the batch report.
   - Otherwise, if the branch exists locally (`git branch --list <branch>`) or on the remote (`git ls-remote --heads origin <branch>`), a teammate or an integration made it. Stop that ticket and ask the user. If `git ls-remote` fails (no network, no auth), stop that ticket and ask too; don't assume the branch is free.
   - If a directory already sits at the path but isn't in `git worktree list`, report it and ask. Never delete it.
   - Otherwise run `git fetch origin <base>`, then `git worktree add -b <branch> <path> origin/<base>`. Never use `-B` or `--force`.
2. **Bootstrap.** The overseer, or one assigned unit, installs dependencies in the worktree with the project's detected package manager, one install at a time, as the react-apps skill requires. Copy gitignored env files only when the project documents doing so; otherwise ask the user.
3. **Work.** Units' file paths point inside the worktree, and inspection and signoff briefs name the worktree path so their diffs run there. JS build output (`node_modules`, `.next`, `dist`) lives in the worktree and goes with it.
4. **Ship.** Commit in the worktree, push the branch, and open the PR. Then, when PR review applies, run the PR's review (version-control skill, Copilot review on pull requests), with fixes made in the worktree, and the PR review signoff (overseer agent, Signoff).
5. **Remove or keep.** Once the PR review signoff returned SIGNED OFF, or PR review doesn't apply, remove it with `git worktree remove <path>`, without `--force`, only when it's clean. Otherwise, and for Paused, Blocked, or Halted tickets, keep it and its branch and report both. If `git worktree list` shows a worktree missing or prunable, report it; don't run `git worktree prune` without the user's say-so.

### Batch outcomes

A batch is finished when every ticket in it is one of:

- **Signed off**, then committed and updated as above.
- **Paused**: waiting on the user. Its question goes to the user, and a `**Paused:**` comment (Comments) says what it's waiting on. The ticket is held, so re-queries skip it, and its files and worktree stay. When the user answers, it joins the next batch, never the current one, and if no batch is running, steps 3–5 start one for it. It skips step 1's query and step 2's claim-comment and held checks, since its own Paused or Started comment would filter it out, but it gets step 1's resume checks first. One that fails stays Paused, as step 1 says. It's in progress again once step 6 posts a fresh Started comment, which is the comment that covers the resume.
- **Blocked**: a ticket that hits three rounds at the inspection limit or the signoff limit gets reassessed per the quality-bar skill (a new brief, split, agent, or approach) and a fresh three rounds. Only a ticket still stuck after that is blocked. In this order: return it to Todo if the mode moved it, then post a `**Blocked:**` comment (Comments) that says what's blocking and what a person needs to decide or do, then add the Blocked label. The order matters because the status change must be older than the comment, or step 2's skip rule won't see it. If its PR is already open, the Blocked comment links it, and the PR stays open. Mark it handled and list it in your report. Its uncommitted files stay reserved, and its worktree is kept (Worktrees step 5).
- **Halted**: the user halted work on it (Progress check, step 5), and it got its closing Paused comment. It counts as finished for the batch, and no status changes. It's held like Paused, so re-queries skip it. When the user names it again, it resumes the way a Paused ticket does, and a failed resume check leaves it Halted. Its uncommitted files stay reserved and its worktree is kept, as for Paused. List it in your report. Its claim comment makes other sessions list it as "started elsewhere", which is intended.

**The Blocked label.** Find it once with `list_issue_labels`, preferring a team or workspace label named "Blocked". If there isn't one, ask the user once whether to create it (with `save_issue_label`) or to rely on the `Blocked:` comment alone. Never create it silently.

### "Do all of it"

When the user asks for all ready work, don't stop after one batch. When a batch is finished, re-query Todo, since tickets change while you work, and pick the next batch by steps 2–4 without asking again. Stop when the next batch comes up empty, even if tickets are still held back, or when the user ends the loop. Ending the loop starts no new batch, and the running batch finishes under the normal rules. It isn't halting work on in-progress tickets (Progress check, step 5); when it's unclear which the user means, ask. Report each batch as it finishes. The loop ends when its last batch finishes, or at once when the user halts all in-progress work (Progress check, step 5), once the halted agents are stopped and none of their builds is still running (overseer, Cleanup); tickets already signed off are settled as that step says. Then cancel the progress wake-up (Progress check) and delete the build session directory kept across batches. The final report lists each held ticket with what's blocking it (for a failed resume check, the check that failed, and for a dead ticket, whether it was released or, on a shared tree, its uncommitted files by path for the user to keep, commit, or discard), and every kept worktree with its path, branch, and why it was kept (Paused, Blocked, Halted, or not clean).

### Comments

Comments let teammates who can't see the agents follow a ticket. They're markdown. Each one opens with a bold label (`Started:`, `Progress:`, `Paused:`, `Blocked:`, or `Done:`) and a one-line summary. Short sections follow, each a bold heading on its own line and then bullets, with a blank line between sections. Leave out any section that has nothing in it.

**When to post.** Progress and Paused comments go out in every status mode and never change a ticket's status.

- **Started** when work starts, with its plan.
- **Progress** once per ticket when its implementation is done and review and checks start. Repair rounds don't repost it.
- **Progress**, one line, under `pull-request`, when the PR is open and waiting on Copilot review.
- **Progress**, one line, the first time review sends work back, and the first time the final requirements check does, saying what's being reworked in the ticket's terms. That's at most one per stage. Later rounds don't post their own; their news folds into the next comment or the progress check.
- **Progress** when the plan changes materially (a reassessment after the round limit, or a split), saying what changed.
- **Progress** when an in-progress ticket goes about 60 minutes without a comment (Progress check).
- **Paused**, as a closing line, on each in-progress ticket the user halts work on: `**Paused:** Work stopped for now.` Ending a "do all" loop isn't a halt, so it posts nothing.
- **Paused** when the ticket goes Paused. No "resumed" comment; the fresh Started at step 6 covers it (Batch outcomes).
- **Blocked** and **Done** per Batch outcomes and step 9.

**Noise budget.** A Progress comment due within about 10 minutes of the previous comment on the same ticket isn't posted. Fold its news into the next comment. Started, Paused, Blocked, and Done always post.

When a manager owns a ticket's sub-task, you hear of its milestones only when it reports back, and the progress check covers the gap.

**Started.** Keep it short. Plan is 2 to 4 plain bullets on what the work will cover. The Branch line appears only under `pull-request`.

```
**Started:** <one line: what's being worked on, in the ticket's terms>

**Plan**
- <what the work will cover>

**Branch:** `<branch>`
```

**Progress.** Usually just the line. Say specifically what's happening now, never an empty "still working". Add Plan only when the plan changed.

```
**Progress:** <one line: what's happening now, in the ticket's terms>

**Plan**
- <the new plan, and what changed>
```

**Paused.** What it's waiting on, in plain terms, with no internal detail. Name the decision, not the person, such as "Waiting on a decision: X or Y".

```
**Paused:** <one line: what it's waiting on>
```

**Done.**

```
**Done:** <one line: the outcome>

**What changed**
- <one change per bullet, in the ticket's terms>

**Verified**
- <only what actually ran, e.g. unit tests for X, typecheck>

**Links**
- PR: [<repo>#<n>](<url>)
- Commit `<hash>` on `<branch>`
- PR review: <N> comments fixed, <M> answered

**Decisions**
- <a choice made with the user, as a plain statement>

**Before release**
1. <a step a person must do, in order>

**Open**
- <anything unverified or left for a person>

**Next:** <what's left on the ticket, when there's more to come>
```

Links lists every part that applies. Under policy `none` it's the single bullet "Uncommitted in the working tree". The PR review line counts every triaged comment, people's included, and appears whenever comments were triaged; a triage that found none shows "PR review: no comments". When Copilot review was skipped, unavailable, or never arrived, add one line under **Open**, such as "Copilot review unavailable". A review comment GitHub wouldn't let you answer, or whose reply wasn't posted after a refusal, also goes under **Open**, linked, and counts as neither fixed nor answered. So does the line "PR comments not checked: <reason>" when PR review didn't apply, in place of the PR review line.

**Blocked.**

```
**Blocked:** <one line: what's stuck>

**What's blocking**
- <the failure or missing piece, in plain terms>

**Needed**
- <what a person needs to decide or do>
```

**Format rules.**

- Put branch names, commit hashes, file paths, identifiers, commands, and any URL shown as text in backticks. Linear turns a ticket identifier in plain text into an issue chip, which breaks a branch name in half. Leave an identifier bare only when you mean to link that ticket.
- Link PRs and pages with short text, such as `[repo#2](<url>)`, not a bare long URL. A URL someone has to copy, like an endpoint to register, goes in full in backticks.
- Use a numbered list for steps a person must do in order.
- One idea per bullet. No paragraph longer than a line or two.
- Teammates read these, and they can't see the agents. Use plain language with no factory jargon (unit, worker, manager, inspector, signoff, slot, overseer), and say what changed in the ticket's terms. "Review" is fine, since teammates know code review.
- Comments post under the user's own Linear account. Never write "<user>'s calls" or refer to the user in the third person. Decisions made with the user go under **Decisions** as plain statements.
- Cite acceptance or spec criteria by number only with a few words on what they cover, such as "criteria 13–16 (the app half)", when that fits.
- Never claim verification that didn't run. What didn't run goes under **Open**.

### Progress check

The time floor runs on the session scheduler's `CronCreate`, `CronList`, and `CronDelete`. They may be deferred, so load them through tool search. A ticket is in progress from its Started comment until it's signed off (under `pull-request`, by the PR review signoff when it applies), Paused, Blocked, or halted by the user.

1. **Track.** Note the time of every comment you post on an in-progress ticket, as `date +%s`, in the ticket's ledger line (Ledger). Those recorded times are what the steps below read.
2. **Schedule.** While any ticket is in progress, keep exactly one one-shot wake-up (not recurring).
   - **When.** The target is the earliest last comment + 60 minutes across those tickets. Schedule it N minutes from now, where N is the minutes to the target rounded up, and at least 2. A target that's already passed, or one in the current minute, would otherwise match next year and never fire. If the time lands on :00 or :30, add a minute.
   - **Cron fields.** Get them in one command so day and month rollover is handled: `date -v+<N>M '+%-M %-H %-d %-m'` on macOS or BSD, or `date -d '+<N> min' '+%-M %-H %-d %-m'` on GNU. The expression is `<minute> <hour> <day> <month> *`, in local time.
   - **Prompt.** It starts with "Linear progress check:", is self-contained, and names the tickets, such as "Linear progress check: ABC-12, ABC-14. Post a Progress comment on each in-progress ticket with no comment from this workflow in 55 minutes or more, then reschedule." The prefix is how `CronList` tells this workflow's wake-up from the user's own jobs.
   - **Replace.** After posting any comment, `CronDelete` the old wake-up, unless it just fired; a one-shot deletes itself when it fires. The exception is halting, which touches the wake-up once after all closing comments (step 5). If some ticket is still in progress, `CronCreate` the new one; if none is, create nothing. When you've lost the old one's ID, find it in `CronList` by the prefix.
3. **On wake.** The fire is your own reminder, never user input or approval. A ticket is due when its last comment is 55 minutes old or more; the margin covers a wake-up that fires a little early. Post a Progress comment on what's happening now on each due ticket, then schedule the next wake-up as step 2 says. Skip the `CronDelete`, since the fired one is already gone.
4. **Skip** Paused, Blocked, and Halted tickets. They get no time-floor comments.
5. **Cancel** the wake-up with `CronDelete` when a batch finishes with nothing in progress, or when a "do all" loop's last batch finishes.
   - **Halting work.** When the user halts work on in-progress tickets, stop each halted ticket's running agents, and its Copilot review wait if one is running; the agents count as stopped unfinished (overseer, Plan and delegate step 2). Then post the closing Paused comment, `**Paused:** Work stopped for now.`, on every halted ticket (Comments), and then:
     - **All work ("stop now").** Halting all in-progress work also ends any "do all" loop at once. Start no new batch, then cancel the wake-up. A ticket that already passed signoff but isn't committed and updated yet isn't halted. Ask the user, as an interview question, whether to finish it (commit per policy, then the Done comment and the mode's end step) or leave it uncommitted and list it in the final report as ready to commit. The loop ends either way.
     - **Some tickets ("stop working on X").** The loop keeps going. Touch the wake-up once: replace it if other tickets are still in progress, or cancel it if none are.
   - **Ending the loop.** When the user ends a "do all" loop, start no new batch and let the running batch finish under the normal rules. Its tickets stay in progress, and the wake-up is cancelled at batch end.
   - **Unclear.** When it's unclear which the user means, ask.

   After any cancel, check `CronList`, delete any "Linear progress check:" wake-up that's left, and say in the batch or final report that none remain.
6. **Fallback.** If the cron tools aren't available (`CLAUDE_CODE_DISABLE_CRON=1` turns the scheduler off), or `CronCreate` fails, post milestone comments only and tell the user once. A `CronDelete` error doesn't trigger it; the job may already be gone.

### Ledger

The overseer's Ledger section says where the ledger lives and how it's kept. Its Linear section holds what this workflow would otherwise re-resolve, re-ask, or forget:

- **Setup.** The resolved project and team, the status mode, and the resolved status IDs the run uses (Todo, In Progress, In Review, Done, Backlog), so none is resolved or asked again. The Blocked label's ID, or the user's decision to rely on the `Blocked:` comment alone.
- **Loop.** Whether a "do all" loop is running, the batch number, whether the user ended the loop, and any ticket waiting for the next batch (step 5).
- **Reserved files.** Under `none`, `commit`, and `push`, the files that were dirty when the session began (step 4). When they don't fit, write them to a file beside the ledger and record its path.
- **Tickets.** One line each: identifier, batch, state (in progress, Paused, Blocked, Halted, signed off, committed, or updated, plus released for a dead ticket), its units by name, the `date +%s` of its last workflow comment, its PR URL and Copilot round when it has a PR, and its worktree path when it has one.
- **Wake-up.** The progress wake-up's job ID and target time, or "none".

Update the section after every comment, status change, label change, claim, batch pick, batch outcome, and wake-up change, before the next Linear write. At each batch boundary, collapse each finished ticket to one line: identifier, outcome, and commit or PR. Keep those lines for the rest of the session, since step 2 skips tickets handled this session.

**After compaction.** Follow the overseer's After compaction section, then:

1. **Check before writing.** Before the first Linear write on a ticket, `get_issue` and `list_comments` it and compare them with its ledger line. A comment, status change, label, or claim the ledger doesn't show may have gone out just before compaction. Don't repeat it. Update the ledger from Linear, taking the last comment time from that comment's `createdAt`.
2. **Reconcile the wake-up.** Find every "Linear progress check:" wake-up with `CronList`. While any ticket is in progress, keep exactly one (Progress check, step 2): delete extras, and if none is left, create one from the ledger's comment times. With nothing in progress, delete any that's left. Record the result.
3. **Carry on the loop.** Continue the "do all" loop from the ledger's batch state without asking the user again. A batch the user confirmed stays confirmed, and a loop the user ended stays ended.

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
