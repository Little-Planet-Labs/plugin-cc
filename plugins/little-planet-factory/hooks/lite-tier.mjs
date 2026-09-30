// PreToolUse hook for the factory's lite tier.
//
// A session launched with LPF_TIER=lite keeps the overseer and managers on
// their own models and runs every other agent on sonnet. This hook enforces
// that on Agent (formerly Task) calls: a spawn of anything but a manager
// that doesn't pass model "sonnet" is denied, and a fork is always denied, with a reason telling the
// caller to re-issue it on sonnet. A spawn whose description carries the
// literal [full-tier] marker, for a unit the user approved for full tier,
// may also pass "opus". Nothing above opus, and never haiku.
//
// It enforces only when the caller is a factory lead (the overseer or a
// manager), so a lite shell's other sessions and other plugins' agents are
// untouched. Caller scoping relies on PreToolUse input carrying agent_type
// under --agent or inside a subagent (hooks reference); a plain session has
// none and passes through. Whether a subagent's agent_type is namespaced is
// unverified (SessionStart shows the --agent main session's is), so the bare
// names are accepted too.
//
// Without LPF_TIER=lite it does nothing. It never outputs "allow", which
// would skip permission prompts: a spawn it doesn't deny gets no output, so
// the normal permission flow decides. It never changes the tool input.
//
// It fails open: any error (bad JSON, oversized stdin, a timeout) ends it
// with exit code 0 and nothing on stdout or stderr, so a broken hook can
// never block or break a session. The prompt rules in the overseer and
// manager instructions still apply when it does. No npm dependencies.
//
// Unverified: the Agent tool_input field names (subagent_type, model,
// description) are inferred from the Agent tool's own parameter names, with
// model absent when the caller omits it. Every field is read defensively.

const MANAGER_TYPE = 'little-planet-factory:manager';
const LEAD_CALLERS = new Set([
  'little-planet-factory:overseer',
  MANAGER_TYPE,
  'overseer',
  'manager',
]);
// A fork inherits its caller's model and ignores the per-call model, so in
// lite it's denied whatever model or marker the call passes.
const FORK_TYPE = 'fork';
const AGENT_TOOLS = new Set(['Agent', 'Task']);
const FULL_TIER_MARKER = '[full-tier]';
const FULL_TIER_MODELS = new Set(['opus', 'sonnet']);
// Claude Code runs an Agent call with no subagent_type as general-purpose.
const DEFAULT_TYPE = 'general-purpose';

const MAX_STDIN_BYTES = 1024 * 1024;
const SELF_TIMEOUT_MS = 5000;

function readStdin() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    process.stdin.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_STDIN_BYTES) {
        process.stdin.destroy();
        reject(new Error('stdin too large'));
        return;
      }
      chunks.push(chunk);
    });
    process.stdin.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    process.stdin.on('error', reject);
  });
}

function stringField(object, key) {
  const value = object[key];
  return typeof value === 'string' ? value : null;
}

// Returns the deny reason for a spawn that breaks the lite rules, or null.
function denyReason(toolInput) {
  const subagentType = stringField(toolInput, 'subagent_type') || DEFAULT_TYPE;
  if (subagentType === MANAGER_TYPE) return null;
  if (subagentType === FORK_TYPE) {
    return (
      `Lite tier: forks aren't allowed. A fork inherits the caller's model and ignores "model", ` +
      `so it can't be held to sonnet, and ${FULL_TIER_MARKER} doesn't change that. ` +
      `Re-issue the call with a factory agent type or a built-in agent type and model "sonnet".`
    );
  }

  const model = stringField(toolInput, 'model');
  if (model === 'sonnet') return null;

  const description = stringField(toolInput, 'description');
  const fullTier = description !== null && description.includes(FULL_TIER_MARKER);
  if (fullTier && FULL_TIER_MODELS.has(model)) return null;

  const shownModel = model === null ? 'none (inherits the session model or its pin)' : `"${model}"`;
  return (
    `Lite tier: this agent type must run on sonnet. ` +
    `Denied subagent_type "${subagentType}" with model ${shownModel}. ` +
    `Re-issue the same call with model "sonnet". ` +
    `Put ${FULL_TIER_MARKER} in the description only for a unit the user approved for full tier, ` +
    `and even then only "opus" or "sonnet" is allowed.`
  );
}

async function main() {
  if (process.env.LPF_TIER !== 'lite') return;

  const raw = await readStdin();
  const input = JSON.parse(raw);
  if (!input || typeof input !== 'object' || Array.isArray(input)) return;
  if (!AGENT_TOOLS.has(input.tool_name)) return;
  if (typeof input.agent_type !== 'string' || !LEAD_CALLERS.has(input.agent_type)) return;

  const toolInput =
    input.tool_input && typeof input.tool_input === 'object' && !Array.isArray(input.tool_input)
      ? input.tool_input
      : {};
  const reason = denyReason(toolInput);
  if (reason === null) return;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: reason,
      },
    }),
  );
}

process.exitCode = 0;
process.stdout.on('error', () => {});
process.on('uncaughtException', () => process.exit(0));
process.on('unhandledRejection', () => process.exit(0));
setTimeout(() => process.exit(0), SELF_TIMEOUT_MS).unref();

main().catch(() => {});
