# Global Agent Instructions

## Working agreements

- Never use em dashes. Use plain hyphens.
- Use plain text for status messages. Do not use emoticons or decorative symbols.
- Never add an agent name as a commit co-author.
- Before changing a project, read its authoritative documentation and inspect
  the actual tooling and configuration instead of assuming its workflow.
- Do not hand-edit generated files. Change their source and regenerate them with
  the documented tooling.
- Keep code simple, readable and modular. Preserve async behavior, connection
  lifecycles, retries and resource cleanup when working in asynchronous systems.
- Prefer explicit error handling. Validate external inputs, respect
  environment-based configuration and consider security implications.
- For one-off or infrequent operational work, begin with the simplest direct
  end-to-end path. Add automation only after a concrete blocker or repeated
  need justifies it.
- Run long-lived tooling with sensible timeouts or in non-interactive batch
  mode. Never leave commands waiting indefinitely.
- Reproduce bugs at the closest user-observable boundary before changing code.
- Do not silently reverse documented deliberate decisions. When a decision
  changes, explain why and update the authoritative documentation.
- Do not treat developer time as a deciding constraint unless the user
  explicitly makes it one. Choose the solution that best satisfies correctness,
  simplicity, robustness, security, and long-term maintainability, even when it
  takes substantially longer to implement.
- Do not mark work complete until the relevant checks pass. Never skip, weaken
  or remove meaningful tests solely to make a check pass.

## Maintaining agent guidance

- Keep only guidance useful across most future sessions.
- Point to authoritative documentation or commands instead of duplicating them.
- Rewrite or remove obsolete guidance instead of continually appending new rules.
