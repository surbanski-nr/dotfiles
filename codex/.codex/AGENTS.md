# Global Agent Instructions

## Working agreements

- Never use em dashes. Use plain hyphens.
- Never add an agent name as a commit co-author.
- Do not hand-edit generated files. Change their source and regenerate them with
  the documented tooling.
- For one-off or infrequent operational work, begin with the simplest direct
  end-to-end path. Add automation only after a concrete blocker or repeated
  need justifies it.
- Reproduce bugs at the closest user-observable boundary before changing code.
- Do not silently reverse documented deliberate decisions. When a decision
  changes, explain why and update the authoritative documentation.
- Do not treat developer time as a deciding constraint unless the user
  explicitly makes it one. Choose the solution that best satisfies correctness,
  simplicity, robustness, security, and long-term maintainability, even when it
  takes substantially longer to implement.

## Maintaining agent guidance

- Keep only guidance useful across most future sessions.
- Point to authoritative documentation or commands instead of duplicating them.
- Rewrite or remove obsolete guidance instead of continually appending new rules.
