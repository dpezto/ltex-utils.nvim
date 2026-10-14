# Contributing

Thanks for helping out. Small, focused PRs merge fastest.

## Development

- `make test`: headless test suite (`tests/run.lua`, which also runs `tests/regressions.lua` and `tests/isolation.lua`). It mocks the LTeX client and file persistence, so no language server is needed. Equivalent to `nvim --headless --clean -l tests/run.lua` from the repository root.
- `COVERAGE=1 make test`: writes `luacov.stats.out`; needs `luacov` and `luacov-reporter-lcov` on `LUA_PATH`. Config is in `.luacov`.
- Lua is indented with tabs (see `.editorconfig`). Keep the surrounding style when editing a file.

Add or extend a test for any behavior change. `tests/regressions.lua` holds one check per fixed bug; copy the nearest existing case.

## Commits and PR titles

PRs are squash-merged, and releases are cut automatically by release-please from the commit history, so **PR titles must follow [Conventional Commits](https://www.conventionalcommits.org)** (`feat: …`, `fix: …`, `docs: …`, etc.). CI checks the title; `feat`/`fix` determine version bumps and CHANGELOG entries.

If your change touches the config surface or commands, update `README.md` and `TUTORIAL.md` in the same PR.

## AI-assisted contributions

AI assistance (Copilot, Claude, etc.) is welcome, with three rules:

1. **Disclose it** in the PR description (a one-liner is fine).
2. **You must understand and have tested the change yourself**: run `make test` locally. You are the author; "the model wrote it" is not a review response.
3. **No unreviewed dumps.** Large AI-generated diffs with no accompanying reasoning, and AI-generated bug reports without a reproducible case, will be closed.

## Bug reports

Use the issue form. The LTeX server and version, the picker backend, and a minimal document plus the code action you ran turn a week of back-and-forth into a same-day fix.
