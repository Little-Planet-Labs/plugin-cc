---
name: asking-questions
description: How Little Planet Factory agents ask the user questions — as interview questions through the question tool, each with short self-contained context and concrete options, never as questions buried in prose. Covers when to ask, how to write the context and options, batching, and how managers and workers hand questions up for the overseer to ask.
user-invocable: false
---

# Asking the user questions

The user answers questions as an interview: discrete questions, each with its own context and options, that they can work through and keep track of. A question buried in a paragraph, or a list of questions at the end of a long message, is easy to miss, hard to answer precisely, and hard to match back to the answer.

## Ask only what's theirs to decide

Ask when the answer changes what you do and you can't settle it from the request, the code, the project instructions, or the knowledge vault. Don't ask about what you can look up, a choice with an obvious conventional default, or permission for something the brief or policy already allows. For a low-risk default, pick it, proceed, and state the assumption in your report.

## Use the question tool

When you have the `AskUserQuestion` tool, every question goes through it. Don't also write the questions in your message, and don't end a message with an inline question ("Want me to…?", "Should I…?"). If your message has nothing else to say, send only the tool call.

Each question has:

- **Context: one or two sentences, self-contained.** What's being decided, and the fact that makes it a question: what you found, what conflicts, what it affects. Write it so someone who skipped the rest of the conversation can answer. Name the concrete thing (the file, policy, endpoint, or screen) instead of pointing back at "the above" or "as discussed".
- **The question itself.** One decision, ending in a question mark. Not two decisions joined with "and".
- **A header of a word or two**, such as "Base branch", "Auth", or "Scope".
- **Two to four options** that are real, mutually exclusive choices. Each label is a few words, and each description says what happens if it's picked: the consequence or trade-off, not a restatement of the label. If you recommend one, put it first and add "(Recommended)" to its label. Leave out "Other" — the user can always write their own answer.
- **A preview**, when the choice is between things that are easier to compare side by side: code shapes, layouts, config blocks, message drafts.

Use multi-select when the choices aren't exclusive ("Which of these should ship in this release?").

### Batching

- Ask related questions together, up to four per call, ordered so earlier answers frame later ones.
- When a question only makes sense after another is answered, ask in rounds rather than guessing at the dependency.
- Don't hold a question back to batch it if work is blocked on it now. Don't interrupt with a non-blocking one either; collect it for the next natural stopping point.
- While running agents keep working, ask without stopping them, unless the answer changes what they're doing.

### After the answer

Act on it. Restate the decision in a few words where it changes the plan, so the record is clear. Don't re-ask something already answered in this session unless new information changes it, and then say what changed.

## Without the question tool

If you don't have the tool, keep questions out of the body of your message. Put them last, under a **Questions** heading, as a numbered list. Give each one the same shape: a sentence of context, the question, and lettered options, with your recommendation marked. That way the user can answer "1b, 2a".

## Handing questions up

Managers and workers can't reach the user. When a decision belongs to the user, put it in your report in this shape, so your lead can ask it without rewriting:

```
Question for the user:
- Context: <one or two self-contained sentences>
- Question: <one decision>
- Options: <label — consequence> / <label — consequence> [/ …]
- Recommendation: <option, and why in a clause>
- Blocking: <what's paused until it's answered, or "nothing">
```

The overseer merges questions from several agents, drops any it can answer itself, and asks the rest as one interview.
