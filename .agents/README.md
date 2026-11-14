# Work with repository agents

Use ordinary language to describe the result you need. For a substantial task, include these details:

- **Goal:** The behavior to change or the question to answer.
- **Context:** Relevant files, errors, examples, or previous decisions.
- **Constraints:** Requirements that affect the result or the permitted actions.
- **Done when:** Observable behavior and the checks needed to establish completion.

For example:

> Fix the calendar zoom position after switching years. Start with CalendarModel and the existing zoom tests.
> Preserve the current overview behavior. Finish when the regression is covered and the focused tests pass.

For an investigation:

> Compare the two backup import paths. Explain their recovery behavior and cite the implementation.
> Do not change files. Identify any unverified assumptions.

Keep durable repository requirements in `AGENTS.md` and task procedures in skills.
A task prompt needs only the context and constraints that change this task.
Use a named skill when its workflow is the intended job. For complex or ambiguous changes, request a plan first.

## Where guidance lives

The [root contract](../AGENTS.md) directs agents to module instructions and required task references.
The [authoring contract](AGENTS.md) defines ownership, size budgets, and validation.
The [maintenance procedure](references/agent-maintenance.md) owns external installation and generated Claude mirrors.

Read only relevant references. A referenced requirement remains mandatory when its task condition applies.
The same canonical instructions support Codex, Cursor, and Claude through the existing synchronization command.

## Official guidance

- [OpenAI best practices](https://learn.chatgpt.com/guides/best-practices): task context, completion criteria, and concise persistent guidance.
- [Instruction loading](https://learn.chatgpt.com/docs/agent-configuration/agents-md): discovery, overrides, and the combined byte limit.
- [Skill authoring](https://learn.chatgpt.com/docs/build-skills): focused descriptions and conditional references.
- [Skill evaluations](https://developers.openai.com/blog/eval-skills): behavioral validation beyond offline file checks.

This repository currently validates guidance structure offline. Live model evaluation is outside this change.
