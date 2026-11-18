# Into the Wild — Workspace Agent Rules

See [`.agents/README.md`](./.agents/README.md), [`.agents/GODOT_RULES.md`](./.agents/GODOT_RULES.md), and [`.agents/TESTING_AND_SETUP.md`](./.agents/TESTING_AND_SETUP.md) for Godot 4 architecture standards, `godot-ai` MCP workflows, and multi-instance testing conventions.

## Auto-Commit & Push for Web Updates
- Whenever you complete and verify a **major change** (new gameplay feature, UI/shader overhaul, bug-fix pass, or performance pass) on `main`, **automatically stage, commit, and push to `origin main`** without waiting for a separate prompt so [`.github/workflows/deploy-web.yml`](./.github/workflows/deploy-web.yml) builds and deploys the updated Web version to `https://allanwang.github.io/Into-the-Wild/`.
- Before committing:
  1. Verify zero parse/runtime errors via `godot-ai` MCP (`logs_read` / `editor_state`) and verify `git status --short` contains no unintended or temporary files (`build/`, `.godot/`, and `addons/godot_ai/` are gitignored).
  2. Use a concise Conventional Commit message (`feat(...)`, `fix(...)`, `perf(...)`, `chore(...)`).
  3. After `git push origin main`, check the GitHub Actions run (`https://api.github.com/repos/AllanWang/Into-the-Wild/actions/runs?per_page=1`) to confirm `Deploy Web Build to GitHub Pages` starts/succeeds cleanly.
