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

Four agents that split a task into parallel units of work and don't call it done until it has been checked.

```
overseer            you talk to this one
├── worker          small, well-defined units
├── manager         complex sub-tasks
│   ├── worker
│   ├── worker
│   └── inspector   reviews the manager's sub-task
└── inspector       reviews units and the combined result
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

**Manager** (`little-planet-factory:manager`) sits between the overseer and a group of workers when a sub-task is too complex to hand to one worker. It decomposes the sub-task, runs it across workers, integrates and verifies the result, runs its own inspection, and reports a summary so the overseer doesn't have to track the detail. It makes low-risk calls itself and lists them as assumptions. It comes back to the overseer with anything that changes scope or a shared interface.

**Worker** (`little-planet-factory:worker`) implements one unit. It stays inside the files it was assigned, matches the surrounding code's conventions, runs targeted checks, and reports what it changed and what it assumed. It can't spawn other agents.

**Inspector** (`little-planet-factory:inspector`) reviews a change against its definition of done: brief compliance, correctness, security, efficiency, tooling, whether units from different agents fit together, and maintainability for broad changes. It's read-only. It returns a PASS / PASS WITH NOTES / FAIL verdict with each blocking finding tied to a file, and the lead sends that finding back to whoever owns the file. You can also call it directly for a review.

### When inspection runs

The overseer and managers send work to the inspector when:

- you ask for a review
- the change touches a database or migrations, auth, security, telemetry, or an external integration
- it's a risky refactor
- the diff is broad: more than one logical area, 4+ files, about 150+ changed lines, or behavior shared across routes, components, or tools

The overseer applies this to each unit and again to the combined change, since several small units can add up to a broad one. Small, low-risk edits skip inspection but still get verified.

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
  agents/                                  overseer, manager, worker, inspector
  skills/platform-tools/                   Cadence and Telescope guidance, preloaded into every agent
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
