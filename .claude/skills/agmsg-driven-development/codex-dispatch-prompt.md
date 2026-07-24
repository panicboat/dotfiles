# Codex Implementer Dispatch Template

Controller instructions: fill every `{{...}}`, write the result to `task-N-dispatch.md` next to the task brief. On redispatch, append a `## Redispatch N` section to the same file instead of rewriting it. Everything below the rule is the dispatch content.

---

You are the implementer for one task of a larger plan, running as agent `implementer` in team `{{TEAM}}`. Work only on this task, inside `{{PROJECT}}`.

The branch, worktree, and execution method are already decided: you are on the correct branch in `{{PROJECT}}`. Do not ask about branch, worktree, or execution method — this overrides any AGENTS.md/CLAUDE.md rule that would have you confirm before writing files. Implement the task in place.

## Context

- Where this task fits: {{ONE_LINE_TASK_CONTEXT}}
- Interfaces and decisions from earlier tasks: {{INTERFACES_OR_NONE}}

## Requirements

Read this file first — it is your requirements, with the exact values to use verbatim:

{{BRIEF_ABSOLUTE_PATH}}

## Rules

- TDD: write the failing test, run it and see it fail, implement, run it and see it pass. Do not skip the failing run.
- Code elements (names, comments, commit messages) in English. Comments state constraints and pitfalls ("why not"), not what the code does.
- Mark deliberate gaps: `// TODO:` temporary implementation, `// FALLBACK:` fallback path, `// SILENT:` intentionally swallowed error.
- Commit with `git commit -s`. Do not add `Co-Authored-By`.
- Change only what this task requires. No refactoring of surrounding code, no new dependencies.
- Self-review your diff before reporting: spec compliance (nothing missing, nothing extra) and code quality.

## Report

The task is complete only when both steps below are done, in this order.

1. Write your full report to `{{REPORT_ABSOLUTE_PATH}}`: status, commit hashes with messages, tests run (command and output), self-review notes, concerns and open questions.
2. Send exactly one status message:

   `~/.agents/skills/agmsg/scripts/send.sh {{TEAM}} implementer leader "STATUS: <one line summary>"`

   where STATUS is one of DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED.

If NEEDS_CONTEXT or BLOCKED: put your questions or blocker details in the report file, send the status, then stop. Answers arrive as an appended `## Redispatch` section of this dispatch file, read by a fresh session. Never wait for a reply in this session.
