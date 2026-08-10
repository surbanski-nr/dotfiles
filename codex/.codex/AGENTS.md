# Global Agent Instructions

## Starting work

- Before changing a project, read its authoritative documentation and inspect
  the actual tooling and configuration instead of assuming its workflow.
- In a workspace containing multiple Git repositories, each repository's
  checked-in documentation and configuration are authoritative for that
  repository. Common sources include `README.md`, files under `docs/`, task
  runners, dependency manifests, lockfiles and compose files.
- Start a new session log for each session. Keep all logs in the workspace root
  at `docs/session_logs/<repo-or-workspace>/YYYY-MM-DD_session_NNN.md`, never
  inside child repositories. Record the full commands used for investigation,
  debugging and operational checks.
- Keep one workspace-level `AGENTS.md`. Do not add nested `AGENTS.md` files to
  child repositories.
- Prefer a repository's documented task runner, such as `Taskfile.yml`, when
  available. Keep its tasks aligned with the actual workflow.
- When scanning with ripgrep, include hidden and ignored files with `-uu` and
  request structured output with `--json`, for example
  `rg -uu --json "TODO" .`.

## Working agreements

- Never use em dashes. Use plain hyphens.
- Use plain text for status messages. Do not use emoticons or decorative symbols.
- Never add an agent name as a commit co-author.
- Do not hand-edit generated files. Change their source and regenerate them with
  the documented tooling.
- Keep code simple, readable and modular. Preserve async behavior, connection
  lifecycles, retries and resource cleanup when working in asynchronous systems.
- Prefer explicit error handling. Validate external inputs, respect
  environment-based configuration and consider security implications.
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
- Do not mark work complete until the relevant checks pass. Never skip, weaken
  or remove meaningful tests solely to make a check pass.

## Develop and verify

- Run long-lived tooling with sensible timeouts or in non-interactive batch
  mode. Never leave commands waiting indefinitely.
- When integration tests depend on sibling repositories or local services,
  start those dependencies explicitly, verify their logs and then run the
  dependent tests.
- When a repository root provides `docker-compose.yml` and the change affects
  the composed system, use that stack for integration verification. Rebuild
  affected services and inspect their logs. Keep the compose file aligned when
  services, environment variables or ports change.
- Behavior changes need relevant tests at the smallest high-signal layer that
  proves the result. Do not add every test type to every change, and do not add
  tests for refactors that do not change behavior.
- Prefer functional tests of observable behavior, business rules, public
  contracts, integration boundaries, caching, concurrency and failure handling
  when those concerns matter.
- Avoid low-value tests that only assert helper calls, delegation, trivial
  constructors, defaults, getters, names, path details, config text or import
  smoke. Test wiring only when it is itself a public contract or an architecture
  rule worth protecting.
- Architecture tests are appropriate when they protect deliberate dependency
  direction or module boundaries.
- Do not skip or mark tests as expected failures merely to make a test run pass.
- Add comments only for behavior that is not clear from the code, such as a
  complex regular expression, unusual constraint or non-obvious workaround.
- Keep documentation synchronized with behavior and deliberate design changes.
- Pin third-party GitHub Actions to immutable commit SHAs when editing workflows.

## Git commits

- Keep unrelated changes out of a commit and inspect the staged diff before
  committing.
- Complete and verify one coherent change before committing it. Do not commit
  when the relevant checks fail.
- Follow the repository's established commit convention. When none exists, use
  `<scope>[, <scope>...]: <imperative summary>`.
- Keep the summary concise, preferably 50 characters or fewer. Start it with a
  lowercase present-tense verb and do not end it with a period.
- When code and its supporting tests or documentation change together, use the
  code's scope instead of adding separate `tests` or `docs` scopes.

## Maintaining agent guidance

- Keep only guidance useful across most future sessions.
- Point to authoritative documentation or commands instead of duplicating them.
- Rewrite or remove obsolete guidance instead of continually appending new rules.
