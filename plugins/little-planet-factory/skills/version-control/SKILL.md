---
name: version-control
description: How Little Planet Factory agents decide whether and how to use git in a project — resolving the project's version-control policy (none, commit, push, or pull-request), the safety rules that hold under every policy, and which role is allowed to run git writes. Use before any command that changes repository state — commit, branch, push, merge, rebase, stash, tag, or opening a pull request.
user-invocable: false
---

# Version control

Projects disagree about what an agent may do with git. One wants every change committed and pushed straight to `main`. Another wants a branch and a pull request. A third wants the agent to never touch git at all. Getting this wrong is expensive and often irreversible — a push can't be taken back from everyone who fetched it — so you resolve the project's policy before running any git command that writes, and you stay inside it.

## Read versus write

**Read commands** inspect state and are always allowed unless the policy is `none` with reads forbidden: `git status`, `git diff`, `git log`, `git show`, `git blame`, `git branch --list`, `git remote -v`, `git rev-parse`.

**Write commands** change the repository, the index, the working tree through git, or a remote: `add`, `commit`, `checkout`/`switch` (including creating branches), `branch -d/-m`, `merge`, `rebase`, `cherry-pick`, `reset`, `restore`, `stash`, `tag`, `push`, `pull`, `worktree add`, and `gh pr create`/`gh pr merge` or any other forge action. Everything in this skill governs writes.

`git fetch` sits between the two: it changes only remote-tracking refs, never your branches or files. It's allowed under `push` and `pull-request`, and off-limits under `none` and `commit`, which don't touch a remote.

## Policies

Each policy includes everything the one before it allows.

| Policy | The agent may | The agent never |
|---|---|---|
| `none` | Edit files in the working tree. Read git state. | Run any git write. Leaves everything uncommitted for the user. |
| `commit` | Stage and commit its own changes on the current branch. | Push, create or switch branches, or touch a remote. |
| `push` | Commit on the current branch and push it to its upstream. | Create or switch branches, or open pull requests. |
| `pull-request` | Create a branch, commit to it, push it, and open a pull request against the base branch. | Commit or push to the base branch, or merge its own pull request unless the policy says it may. |

`push` means pushing the branch that's checked out, which may be `main`. It never means switching to `main` in order to push there.

## Resolving the policy

Take the first source that settles it:

1. **The user, in this session.** An explicit instruction ("commit and push this", "don't touch git", "open a PR") settles it for the work it covers. Shorthands the project instructions define ("release it" → commit and push) count as explicit.
2. **Project instructions.** `CLAUDE.md` files (repo root, nested, and user-level), `AGENTS.md`, and a declared policy block (below). A nested or repo-level file overrides a broader one for that repo.
3. **Repository evidence, only to fill in details.** `CONTRIBUTING.md`, a PR template, and recent branch names inform *how* to branch, name, and write commit messages. They never raise the policy level on their own: a PR template tells you how to write a PR, not that you may open one.
4. **Default: `none`.** When nothing above settles it, make the changes in the working tree, leave them uncommitted, and say so in your report. Ask before any git write.

**Never assume a project is personal.** Treat every repository as shared, with collaborators, review expectations, and protected branches, unless the user or the project instructions clearly say it's a personal or solo project. A single author in `git log`, a personal account or namespace in the remote URL, no CI, no PR template, or a small or new codebase are not evidence. None of them lowers the caution level or raises the policy. Even when the user calls a project personal, it still follows its declared policy. "Personal" describes the project; it doesn't grant permission to push.

**How the user overrides project policy.** The user is the authority over the project's instructions. An explicit, unambiguous instruction in the session overrides a stricter project policy, but only for the specific action it names. "Push this to main" permits that one push. It doesn't change the policy for later work. An ambiguous phrase ("ship it", "wrap it up", "finish this off") isn't an override. When one conflicts with a stricter project policy, ask what the user means, and name the policy you'd be overriding. Calling a project personal isn't an override either.

Otherwise, resolve conflicts toward the more restrictive reading. A standing permission ("you can commit") doesn't imply the next level up ("you can push").

A policy that forbids something stays in force until the user overrides it as above or the project instructions change. Urgency, a failing hook, an agent's brief, or a task that "obviously needs" a commit don't change it.

### Declared policy block

Projects can state their policy unambiguously with a section in `CLAUDE.md`:

```markdown
## Version control

policy: pull-request
base: main
branch: <type>/<ticket>-<short-description>
commit-style: conventional
merge: never
```

Only `policy` is required. `base` defaults to the repository's default branch. `branch` is a naming pattern. `commit-style` is `conventional` or `match-history`, and defaults to matching `git log`. `merge` is `never` (the default) or `allowed`. `policy: none` may add `reads: forbidden` when even read commands are off-limits. Free-form prose in project instructions ("never create branches", "push straight to main") is just as binding. The block only makes it harder to misread.

## Rules under every policy

These hold regardless of the level, and only an explicit instruction from the user for that specific action overrides them:

- **Commit only what the task changed.** Stage explicit paths. Never `git add -A`, `git add .`, or `git commit -a` in a tree that had changes before you started, or while other agents are working. Unrelated changes, whether the user's or another unit's, stay out of your commit.
- **Never discard work you didn't create.** No `reset --hard`, `checkout -- .`, `restore .`, `clean -fd`, `stash` without popping it, or branch deletion that removes unmerged commits.
- **Never rewrite published history.** No force-push, no `--force-with-lease`, no rebase or amend of commits that exist on a remote. Don't amend commits you didn't make in this session.
- **Never bypass checks.** No `--no-verify`, no disabling hooks, no skipping CI. When a hook fails, fix the cause or report it.
- **Never change git configuration.** No `git config` writes, no new remotes, no credential helpers, and no signing changes.
- **Never commit secrets.** Check the staged diff for keys, tokens, `.env` files, and credentials before committing. If one is staged, unstage it and tell the user.
- **Commit only verified work.** A commit happens after the change passes its verification and any inspection it needed, never as a checkpoint for work in progress, unless the user asks for that.
- **Follow the project's message and attribution conventions.** Match `git log` style or the declared `commit-style`. Add or omit trailers, co-author lines, and footers as the project and user instructions say.

## Working through each policy

**`none`.** Finish the work in the working tree. In your report, list the changed files and state that nothing was committed.

**`commit`.** Check `git status` first so you know what was already dirty. After verification passes, stage your files by path, review `git diff --cached`, and commit. Report the commit hash and message.

**`push`.** As `commit`, then push the current branch to its existing upstream with a plain `git push`. If there's no upstream, the push is rejected as non-fast-forward, or the branch is protected, stop and report it. Don't pull, rebase, or merge to make the push go through unless the policy or the user allows it.

**`pull-request`.**

1. Branch from an up-to-date base, named by the declared pattern or the convention in recent branches.
2. Commit verified work to that branch only.
3. Push the branch and open the pull request with the forge CLI (`gh pr create` or the project's equivalent), filling in the PR template if there is one. Link the ticket or spec if the work has one.
4. Report the PR URL. Don't merge unless the policy declares `merge: allowed`, and never merge with failing or pending required checks.

If the forge CLI isn't authenticated, or the push is refused, stop and report it with the branch name. Don't switch to another way of reaching the remote.

## Forge operations: use the gh CLI

When the remote is on GitHub and `gh` is installed, use `gh` for everything that involves GitHub rather than raw API calls, `curl`, or a browser: `gh pr create`, `gh pr view`, `gh pr checks`, `gh pr comment`, `gh pr merge`, `gh repo view --json defaultBranchRef` to find the base branch, `gh issue view` for the linked ticket, and `gh api` only for what the subcommands don't cover. Reading with `gh` (`view`, `list`, `checks`, `status`) follows the same read/write split as git. Anything that creates, edits, comments, or merges is a write, and is allowed only where the policy allows it.

Run `gh` commands bare, one command per invocation:

- No loops. Don't wrap `gh` in `for`, `while`, `until`, `xargs`, or a script that iterates over PRs, issues, or repos. To act on several items, run a separate `gh` command for each one, so every write is visible and can be approved on its own.
- No polling loops. To wait on CI, use the built-in `gh pr checks <pr> --watch` or `gh run watch <run-id>` rather than `sleep`-and-retry.
- No chaining writes. Don't join several `gh` writes with `&&` or `;`, or bury them in a larger shell pipeline. Piping a read into `jq` is fine, but `gh`'s own `--json` and `--jq` flags are better.
- Use flags, not prompts. Pass `--title`, `--body` or `--body-file`, `--base`, and `--head` explicitly, so the command never waits on interactive input.

If `gh` isn't installed or isn't authenticated (`gh auth status` fails), don't work around it with tokens or `curl`. Report what you couldn't do, with the branch name and the PR title and body ready for the user to use. For forges other than GitHub, use their CLI (`glab` and similar) under the same rules if it's installed. Otherwise stop at the push and report it.

## Multi-agent work

Only the lead — the overseer, or the main session when there is no overseer — runs git writes. Several agents share one working tree, so a commit or stash from any one of them captures or destroys the others' in-flight work.

- **Overseer.** Resolve the policy during planning, and state it in your plan when it's anything other than `none`. Run the git writes once, after the definition of done is met: every unit has reported back, verification passes, inspection is clean, and signoff has returned SIGNED OFF. Commit the combined change, or one commit per logical unit if the project's history favors that. Your report says what was committed, pushed, or opened, or that nothing was.
- **Manager.** Never run git writes. Report the complete file list so the overseer can commit it.
- **Worker.** Never run git writes, even when the brief seems to invite it. If a brief asks you to commit, report that instead. Read commands are fine for understanding the code.
- **Inspector.** Read-only, as always. `git diff` and `git log` are your inputs. Treat a change that includes git writes the policy forbids, or a staged secret, as a blocking finding.
- **Researcher and signoff.** Read-only, like the inspector. Never run git writes; `git status`, `git diff`, and `git log` are fine.

A unit given its own worktree (`isolation: worktree`) is an exception the lead sets up deliberately. Creating that worktree is itself a git write, so it's allowed only where the policy permits branches, or where the user asked for it.
