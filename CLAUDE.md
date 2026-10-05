# Working with the local agent

This project is also worked on by a local AI agent (LM Studio Bionic running a small model). You are the stronger helper it hands off to when it gets stuck.

## When HANDOFF.md exists

1. Read HANDOFF.md first. It explains the goal, the error, and what the local agent already tried.
2. Read the files it lists before changing anything.
3. Fix the problem and confirm the fix by running the relevant build, test, or check.
4. Write HELP-NOTES.md in the project root for the local agent, using this format:

```
# Help notes

## What was wrong
One or two sentences, plain language.

## What I changed
Each file and what changed in it.

## How to continue
Short, numbered steps the local agent should follow next. Keep each step small enough for a 9B model: one file or one function at a time.

## Watch out for
Any trap the local agent is likely to fall into again.
```

5. Delete HANDOFF.md once the problem is solved, so the local agent does not act on an old handoff.

## Style

- Keep files small and focused. The local agent struggles with files over a few hundred lines.
- Prefer simple, readable code the local agent can follow and extend.
- The work must not look AI-generated: no em dashes in user-facing copy, no gradients, no pill-shaped buttons, no emoji icons, no vague hero text, no fake metrics, no hype marketing language.
