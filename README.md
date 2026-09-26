![Solarpunk code factory with solar panels, wind turbines, conveyor belts, and a robotic arm](assets/brand/solarpunk-factory-hero-v5.png)

# Little Planet Labs Claude Code plugins

A [Claude Code](https://code.claude.com) plugin marketplace from Little Planet Labs.

| Plugin | What it does |
|---|---|
| [Little Planet Factory](#little-planet-factory) | A team of agents that plans, delegates, implements, and inspects multi-part work |

## Install

```
/plugin marketplace add Little-Planet-Labs/plugin-cc
/plugin install little-planet-factory@little-planet-labs-cc
```

To roll it out to everyone working in a repo, add this to the repo's `.claude/settings.json`. Claude Code prompts teammates to install it when they trust the folder:

```json
{
  "extraKnownMarketplaces": {
    "little-planet-labs-cc": {
      "source": { "source": "github", "repo": "Little-Planet-Labs/plugin-cc" }
    }
  },
  "enabledPlugins": {
    "little-planet-factory@little-planet-labs-cc": true
  }
}
```

## Little Planet Factory

Six agents that split a task into parallel units of work and don't call it done until it has been checked.

```
overseer            you talk to this one
├── researcher      answers one question, with cited findings
├── worker          small, well-defined units
├── manager         complex sub-tasks
│   ├── researcher
│   ├── worker
│   ├── worker
│   └── inspector   reviews the manager's sub-task
├── inspector       reviews units and the combined result
└── signoff         confirms everything asked for is done
```

### Start a session

Run Claude Code as the overseer:

```
claude --agent little-planet-factory:overseer
```

Or make it the default for a project in `.claude/settings.json`:

```json
{ "agent": "little-planet-factory:overseer" }
```

The overseer replaces the default Claude Code system prompt for that session.

### The agents

**Overseer** (`little-planet-factory:overseer`) is the controller. It scopes the work, breaks it into units that don't touch the same files, and hands them to workers and managers in parallel. It doesn't write code unless you tell it to. It launches agents in the background so you can keep talking to it while they run: ask questions, add work, or redirect an agent mid-task. It owns final quality. Work isn't done until every unit has reported back, it has read every diff, verification passes, and every required inspection has come back clean.

**Manager** (`little-planet-factory:manager`) sits between the overseer and a group of workers when a sub-task is too complex to hand to one worker. It decomposes the sub-task, runs it across workers, integrates and verifies the result, runs its own inspection, and reports a summary so the overseer doesn't have to track the detail. It makes low-risk calls itself and lists them as assumptions. It comes back to the overseer with anything that changes scope or a shared interface. It picks opus or sonnet for each worker based on the unit's difficulty and risk. It never uses haiku for a worker, and nothing above opus unless you ask for it.

**Researcher** (`little-planet-factory:researcher`) answers one question for the overseer or a manager before it plans or writes a brief: how an external library or API behaves, an end-to-end root-cause trace, or a broad sweep across repos, the knowledge vault, or tickets. It's read-only. Every finding is labeled either confirmed, with its source, or inferred. Findings are verified wherever possible; an unverified one is a last resort and must say what was tried and why it can't be checked. Leads send research back for up to three rounds per question, then you decide. It runs on sonnet by default, haiku for plain sweeps, and opus for hard tracing. It isn't for scoping the files the lead is about to split; the lead reads those itself.

**Worker** (`little-planet-factory:worker`) implements one unit. It stays inside the files it was assigned, matches the surrounding code's conventions, runs targeted checks, and reports what it changed and what it assumed. It can't spawn other agents.

**Signoff** (`little-planet-factory:signoff`) is the last gate, and only the overseer invokes it. After inspection passes, it turns the source of truth into a checklist and checks each item against evidence in the code. The source can be a Cadence spec, a ticket or issue, a document, or your own request, including anything you added mid-session. It checks off verified spec criteria, flags loose ends (TODOs, skipped tests, stale docs, unresolved follow-ups), and runs a language pass: it verifies the copy inventory, flags existing copy the change made wrong, and flags terminology decisions. Those decisions come to you as interview questions. It doesn't rewrite prose itself. Git writes and the final report wait for SIGNED OFF.

**Inspector** (`little-planet-factory:inspector`) reviews a change against its definition of done: brief compliance, correctness, security, efficiency, tooling, whether units from different agents fit together, and maintainability for broad changes. It's read-only. It returns a PASS / PASS WITH NOTES / FAIL verdict with each blocking finding tied to a file, and the lead sends that finding back to whoever owns the file. You can also call it directly for a review.

### Models

Every subagent except the researcher (sonnet) is pinned to opus, so the model you start the session on doesn't carry down to them. Agents without a pin, such as Claude Code's built-in agent types, get an explicit model of opus or lower on every call. Leads can downgrade per call: sonnet for a mechanical worker, haiku for a researcher doing a plain sweep. Workers never run on haiku. Nothing runs above opus unless you ask for it, and then only for the work you named. The overseer runs on whatever model you start it with.

### When inspection runs

The overseer and managers send work to the inspector when:

- you ask for a review
- the change touches a database or migrations, auth, security, telemetry, or an external integration
- it's a risky refactor
- the diff is broad: more than one logical area, 4+ files, about 150+ changed lines, or behavior shared across routes, components, or tools

The overseer applies this to each unit and again to the combined change, since several small units can add up to a broad one. Small, low-risk edits skip inspection but still get verified.

### Skills

The agents share eight skills beyond the platform guidance.

**Version control** (`version-control`) is preloaded into every agent. Before any git command that changes state, the agents work out the project's policy, then stay inside it:

| Policy | What the agents do |
|---|---|
| `none` | Edit the working tree and leave everything uncommitted. This is the default when a project says nothing. |
| `commit` | Commit verified changes on the current branch. Never push. |
| `push` | Commit on the current branch and push it, e.g. straight to `main`. No branches or PRs. |
| `pull-request` | Branch, commit, push the branch, and open a pull request. Never commit to the base branch. |

The policy comes from, in order: what you say in the session, then the project's `CLAUDE.md` or `AGENTS.md`, then the `none` default. Repo conventions like a PR template shape *how* the agents branch and write messages, but never grant a higher level. Conflicts resolve to the more restrictive reading. To state a policy unambiguously, add this to the project's `CLAUDE.md`:

```markdown
## Version control

policy: pull-request
base: main
branch: <type>/<ticket>-<short-description>
commit-style: conventional
merge: never
```

Only `policy` is required. GitHub operations go through the `gh` CLI, one bare command per call, with no loops, polling scripts, or chained writes. Under every policy, the agents stage explicit paths, never force-push, never skip hooks, never change git config, and never discard work they didn't create. Only the overseer runs git writes, once the work passes verification and inspection. Managers and workers never commit, because they share a working tree with agents still in flight.

**React apps** (`react-apps`) and **Xcode projects** (`xcode-projects`) load when the project uses that stack. They cover how to detect the tooling, how to verify with commands that exit (no dev servers, and `xcodebuild` with per-agent DerivedData and without taking over your simulator), what to leave alone (lockfiles, signing, generated project files), which shared files need a single owner when work is split across agents, and what the inspector should weight in review.

**Quality bar** (`quality-bar`) is preloaded into every agent. It aims for no bugs on the first pass, so review confirms quality rather than discovering defects. Foundational work gets the full bar:
- **What counts as foundational:** persistence, schemas, sync, shared interfaces, auth, and concurrency.
- **Pre-mortem:** before dispatch, the lead lists invariants and failure modes, and each becomes a named test.
- **Per-unit inspection** before integration.
- **At least two review rounds.**

Everything else gets the normal inspection heuristic. Every repair diff is re-reviewed. After three review rounds on a unit, repairs stop. The overseer decides what has to change before work resumes: the brief, coordination between units, the agent, or the approach. It asks you when the decision is yours. Signoff's re-runs have the same limit. Claims and verification output are checked rather than trusted: a 0-test "pass" isn't a pass. Agents don't write product prose by default. Short labels are fine if they're listed in the copy inventory. A project's `CLAUDE.md`, or asking in the session, turns this off.

**Asking questions** (`asking-questions`) is preloaded into the overseer, manager, worker, and signoff. The researcher and inspector don't ask. When a decision is yours, it asks through the interview-question UI: each question has a sentence or two of self-contained context, one decision, and two to four options with their consequences, with a recommendation first. No questions are buried in prose, and none of its messages end with an inline "want me to…?". Managers and workers pass questions up in the same shape, and the overseer merges them into one interview.

**Vercel** (`vercel`) loads when a project deploys to Vercel. Deploys happen only by pushing to git, never with `vercel deploy`, `--prod`, `redeploy`, `promote`, or `rollback`, unless you ask for that specific action. Pushing still follows the version-control policy, so under `none` or `commit` the agent reports that the change is ready to deploy rather than deploying it. Unless you ask otherwise, every Vercel project gets Vercel Web Analytics and Speed Insights; the agent adds the components and tells you when Web Analytics still needs enabling in the dashboard. Neon is never used, whether directly, through the Vercel Marketplace, or as the former Vercel Postgres. When a project needs a database, the agent asks you which one. The skill also covers env vars (pull from Vercel, never hand-edit `.env` files, never handle secret values), function limits and costs, Next.js-on-Vercel rules, build file tracing, Blob access, and debugging from logs instead of redeploying.

**Next.js** (`nextjs`) loads when a project depends on `next`, on any host, alongside `react-apps`. Unless you ask otherwise, every site gets a dynamically generated Open Graph image through the `opengraph-image` file convention, and images go through `next/image` rather than a plain `<img>`. It covers the Metadata API and metadata file conventions, `next/image`, `proxy.ts`, hydration safety, Next 16 caching and `"use server"` rules, route-level CSS, and toolchain pins, labeled with the version they were verified on.

**Web design** (`web-design`) loads for any project that builds web pages or sites, whatever the framework. It covers SEO (titles, meta descriptions, canonical URLs, robots and sitemaps, structured data), favicons and app icons, tab titles (no em-dashes), social cards, theming meta, and accessibility and motion rules. The `nextjs` skill implements these in Next.

### Optional integrations

The agents use two MCP servers when they're connected and work normally without them.

**[Cadence](https://cadencecode.dev/)**
- **Knowledge vault.** Agents search it before non-trivial work. The inspector checks changes against decisions stored there. The overseer saves new durable knowledge.
- **Specs.** When you name a spec ("implement spec 14"), its success criteria become the definition of done.
- **Reports and other output.** Reports are built as Cadence reports rather than artifacts. Slides, files, notes, and anything else Cadence has a tool for go through Cadence.

**[Telescope](https://telescope.littleplanetlabs.com/)**
- **Upstream incidents.** Before debugging a failure that involves an external service, agents check Telescope for a live incident at that provider.
- **Matched incident.** If there is one, the agent reports it with a link to the provider's status page instead of changing code to work around it.

Agents detect both servers by their tool names, so it doesn't matter what name you gave the server when you connected it.

## Repository layout

```
.claude-plugin/marketplace.json            marketplace manifest
plugins/little-planet-factory/
  .claude-plugin/plugin.json               plugin manifest
  agents/                                  overseer, manager, worker, researcher, inspector, signoff
  skills/platform-tools/                   Cadence and Telescope guidance, preloaded into every agent
  skills/version-control/                  git policy resolution and safety rules, preloaded into every agent
  skills/react-apps/                       React web app conventions, loaded on demand
  skills/xcode-projects/                   Xcode and Swift conventions, loaded on demand
  skills/quality-bar/                      foundational tiering, pre-mortems, review and copy rules, preloaded into every agent
  skills/asking-questions/                 interview-style questions to the user, preloaded into all agents but the researcher and inspector
  skills/vercel/                           Vercel deploy rules and platform defaults, loaded on demand
  skills/nextjs/                           Next.js conventions and defaults, loaded on demand
  skills/web-design/                       framework-agnostic SEO, icon, title, and design rules, loaded on demand
```

## Development

Validate after editing:

```
claude plugin validate .
claude plugin validate plugins/little-planet-factory
```

Test locally from a clone:

```
/plugin marketplace add ./path/to/plugin-cc
/plugin install little-planet-factory@little-planet-labs-cc
```

Bump `version` in both `plugins/little-planet-factory/.claude-plugin/plugin.json` and the plugin's entry in `.claude-plugin/marketplace.json`, then tag the release with `claude plugin tag`, which checks that the two agree.

---

<a href="https://littleplanetlabs.com"><img src="assets/brand/little-planet-labs-logo.svg" alt="Little Planet Labs" width="132"></a>
