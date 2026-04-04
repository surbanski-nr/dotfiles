# Agent Instructions

Guidance for AI agents working in this workspace. Keep it lean, consistent, and up to date with actual tooling and compose config.

## Always do these first

- Know the sources of truth in every workspace or github repository, github repository always wins: `README.md`, `docs/specification.md`, `docs/architecture.md`, `docs/api-contract.md`, `docs/codebase.md` and `docker-compose.yml`
- New session = new session log. Keep all session logs in the workspace root at `/home/surbanski/work/vuln/docs/session_logs/<repo-or-workspace>/YYYY-MM-DD_session_NNN.md`. Do not keep `session_logs` directories inside child git repositories. Inside each log file include all full commands you used for investigating or debugging something, things like kubectl, docker, terminal, psql, etc.
- Keep one workspace-level `AGENTS.md` at `/home/surbanski/work/vuln/AGENTS.md`. Do not add nested `AGENTS.md` files inside child git repositories.

## Develop and test

- Python projects use `uv`. Sync dependencies with `uv sync` or the repo-specific `uv sync` variant documented in `README.md` or `Taskfile.yml`.
- `uv sync` creates `.venv/`. Activate it with `. ./.venv/bin/activate` only when shell activation is useful; prefer `uv run <cmd>` for ad hoc commands.
- Use `Taskfile.yml` tasks when a repo provides them. Keep Taskfile commands aligned with the actual repo workflow.
- Default Python quality tools are `ruff` for lint and format and `basedpyright` for type checking unless a repo documents otherwise.
- When integration tests depend on sibling repos or local services, start those dependencies explicitly, verify their logs, and then run the dependent tests.
- Long-running tooling (tests, docker-compose, migrations, etc.) must always be invoked with sensible timeouts or in non-interactive batch mode. Never leave a process or command waiting indefinitely - prefer explicit timeouts, scripted runs, or log polling after the command exits.

## Coding standards

- No emoticons or decorative symbols; use plain text for status messages
- Keep code clean, modular, and async patterns intact; manage resources carefully
- The code and changes should be readable to humans
- Adhere to Keep It Simple, Stupid (KISS) software engineering principle
- Prefer clear error handling and structured logging with correlation IDs
- Prefer clean architecture and reusable components and methods
- Maintain async patterns carefully in async codebases; do not break connection lifecycle, retries, or resource cleanup behavior.
- Validate inputs, respect env-based configuration, and consider security implications for SBOM/vulnerability processing
- Update `docker-compose.yml` if new services, env vars, or ports are introduced
- For Python dependency changes, pin or update versions in `pyproject.toml` and `uv.lock`
- Pin dependency declarations to exact versions only. Do not use ranges, carets, or tildes in project manifests; refresh the matching lockfile before reinstalling dependencies.
- Pin the GitHub Actions workflows
- Don't add useless comments, they should used only for unintuitive behaviour or complicated patterns like regexes and methods behaving in a complex or unusual manner

## Documentation organization in every git repository, current workspace might contain multiple directories containing different git repositories

- Root only: `README.md` and the workspace root `AGENTS.md`. Do not add repo-local `AGENTS.md` files. Do not use big words or adjectives in `README.md`; say what the project is without noise.
- Everything else in `docs/`
- Keep docs aligned with behavior changes, especially `docs/specification.md` and `docs/architecture.md`
- Add diagrams and keep language natural, like a senior software engineer would write

## Testing requirements

- Every code change needs matching tests; no skipping or xfail to go green, we skip tests on shell scripts and Helm chart changes unless I specifically ask for them
- Work one TODO item at a time: implement + tests, run unit+integration+frontend tests, run `docker-compose up -d --build` and verify logs (`docker-compose logs`), commit, then move to the next TODO
- Run the test stack (`docker-compose -f docker-compose.test-deps.yml up -d`) before integration tests; keep Postgres and cache-service running
- Do not mark work complete until the relevant tests pass

## Git commits

- Follow the established subject format: `<scope>[, <scope>...]: <imperative summary>`
- The imperative summary should be concise (50 chars or less) and start with a lowercase letter, no period at the end and using present tense
- Do not include tests and docs scopes in the message if any other is already included, like frontend
- Common scopes (from recent history): `api`, `auth`, `worker`, `frontend`, `common`, `tests`, `docs`, `build`, `observability`, `ci`
