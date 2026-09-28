// SessionStart hook for the overseer's factory ledger.
//
// The overseer keeps its operational state (running agents, round counts,
// cleanup record, wake-ups) in a ledger file so auto-compaction can't lose it.
// This hook tells the overseer where that ledger lives and, after compaction
// or resume, puts the ledger back into context.
//
// The ledger lives only in the session's own scratchpad_dir. Without one there
// is no ledger path and the hook outputs nothing. It is read-only: it never
// writes, creates, moves, or deletes anything, and it never reads outside
// scratchpad_dir. Any error ends it with exit code 0 and nothing on stdout, so
// it can never break or slow a session. No npm dependencies.

import fs from 'fs';
import path from 'path';

const OVERSEER = 'little-planet-factory:overseer';
const LEDGER_NAME = 'factory-ledger.md';

// Claude Code moves additionalContext over 10,000 characters to a file, so
// everything injected stays at or under this.
const MAX_CONTEXT = 9000;

// A UTF-8 byte encodes at least a third of a UTF-16 code unit, so a ledger
// over this many bytes can't fit in MAX_CONTEXT and is never read.
const MAX_READ_BYTES = MAX_CONTEXT * 3;

const MAX_STDIN_BYTES = 1024 * 1024;
const SELF_TIMEOUT_MS = 5000;

const REINJECT_SOURCES = { compact: 'compaction', resume: 'resume' };

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

function isMissing(error) {
  return Boolean(error) && (error.code === 'ENOENT' || error.code === 'ENOTDIR');
}

// Returns null when there's no ledger to inject (missing or empty),
// { size, text: null } when it's too large to read, and { size, text }
// otherwise. Throws on anything else: resolves outside the scratchpad, not a
// regular file, unreadable, or not valid UTF-8.
function readLedger(scratchpad, ledger) {
  // A symlinked ledger is followed only when its target is inside the
  // scratchpad, so the hook never reads anywhere else.
  let target;
  try {
    target = fs.realpathSync(ledger);
  } catch (error) {
    if (isMissing(error)) return null;
    throw error;
  }
  const relative = path.relative(fs.realpathSync(scratchpad), target);
  if (
    relative === '' ||
    relative === '..' ||
    relative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relative)
  ) {
    throw new Error('ledger resolves outside the scratchpad');
  }

  let fd;
  try {
    // O_NONBLOCK so a FIFO at the ledger path can't hang the open, and
    // O_NOFOLLOW so the resolved path can't be swapped for a symlink.
    const { O_RDONLY, O_NONBLOCK = 0, O_NOFOLLOW = 0 } = fs.constants;
    fd = fs.openSync(target, O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
  } catch (error) {
    if (isMissing(error)) return null;
    throw error;
  }
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile()) throw new Error('ledger is not a regular file');
    if (stat.size === 0) return null;
    if (stat.size > MAX_READ_BYTES) return { size: stat.size, text: null };

    const buffer = Buffer.alloc(stat.size);
    let offset = 0;
    while (offset < buffer.length) {
      const read = fs.readSync(fd, buffer, offset, buffer.length - offset, offset);
      if (read === 0) break;
      offset += read;
    }
    if (offset === 0) return null;
    const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(
      buffer.subarray(0, offset),
    );
    return { size: stat.size, text };
  } finally {
    fs.closeSync(fd);
  }
}

function buildContext(input) {
  const scratchpad = input.scratchpad_dir;
  if (typeof scratchpad !== 'string' || scratchpad === '') return null;
  const ledger = path.resolve(scratchpad, LEDGER_NAME);

  const parts = [];
  if (input.agent_type === OVERSEER) {
    parts.push(`Factory ledger for this session: ${ledger}`);
  }

  const kind = Object.prototype.hasOwnProperty.call(REINJECT_SOURCES, input.source)
    ? REINJECT_SOURCES[input.source]
    : null;
  if (kind) {
    const contents = readLedger(scratchpad, ledger);
    if (contents) {
      let block = null;
      if (contents.text !== null) {
        block =
          `Factory ledger re-injected after ${kind}: ${ledger}\n` +
          `Follow the overseer's "After compaction" steps before doing anything else.\n` +
          `---\n` +
          contents.text;
        if ([...parts, block].join('\n\n').length > MAX_CONTEXT) block = null;
      }
      if (block === null) {
        block =
          `Factory ledger at ${ledger} is ${contents.size} bytes, too large to re-inject. ` +
          `Read it in full, then follow the overseer's "After compaction" steps before doing anything else.`;
      }
      parts.push(block);
    }
  }

  if (parts.length === 0) return null;
  const context = parts.join('\n\n');
  return context.length > MAX_CONTEXT ? null : context;
}

async function main() {
  const raw = await readStdin();
  const input = JSON.parse(raw);
  if (!input || typeof input !== 'object' || Array.isArray(input)) return;

  const context = buildContext(input);
  if (context === null) return;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: context },
    }),
  );
}

process.exitCode = 0;
process.stdout.on('error', () => {});
process.on('uncaughtException', () => process.exit(0));
process.on('unhandledRejection', () => process.exit(0));
setTimeout(() => process.exit(0), SELF_TIMEOUT_MS).unref();

main().catch(() => {});
