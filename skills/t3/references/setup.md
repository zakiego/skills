# Set up a repo for T3

Gives a repo three things, all as files in the repo:

- `t3.json` at the root: the T3 actions.
- `scripts/setup-worktree.sh`: runs when T3 creates a worktree. Copies gitignored `.env*` and `.dev.vars*` files from the main checkout, then installs from whatever lockfile exists.
- `scripts/clean-worktree.sh`: runs when a thread settles. Deletes `node_modules` and build output, skips anything git tracks, and refuses to run in the main checkout.

Templates live in `$SKILL_DIR/templates/`.

## Facts about T3 that shape this (from pingdotgg/t3code source)

- T3 reads `t3.json` from the repo root, schema `https://t3.codes/schema/t3.json`. The published JSON Schema rejects unknown keys, so editors flag them. It's not confirmed that T3's runtime parser rejects them too (see `json.md`), so don't add keys outside the schema.
  - Top level: `$schema`, `iconPath`, `defaultThreadEnvMode` (`local` | `worktree`), `worktreeSubmodules` (`recursive` | `top-level` | `none`), `scripts`.
  - Script: `name`, `command` (both required), `icon` (`play` | `test` | `lint` | `configure` | `build` | `debug`), `runOnWorktreeCreate`, `runOnSettle`, `stopOnSettle`, `async`, `previewUrl`, `autoOpenPreview`.
- T3 doesn't run actions straight from the file. The setup runner reads the project's saved actions, and `t3.json` actions are only imported there (Settings > Projects > Actions). So always save them to the project too (step 5).
- Only the first `runOnWorktreeCreate` script and the first `runOnSettle` script are used. Keep one of each.
- `async` defaults to `true`, which starts the agent while install is still running. Set `"async": false` so the agent waits for dependencies.
- `runOnSettle` runs in the thread's own worktree each time it settles. Threads in the main checkout skip it.
- `stopOnSettle` only stops a server started through that action, not one the agent started in its own shell.
- Setup gets `T3CODE_PROJECT_ROOT` (the main checkout) and `T3CODE_WORKTREE_PATH` (only in a worktree). There's no terminal attached, so installs must never prompt.
- `previewUrl` is only used by the desktop build.
- A new worktree branches from the default branch, so `t3.json` and the scripts only apply after they're merged there.

## Workflow

1. **Look at the repo.** From the repo root (a worktree is fine):
   ```bash
   ls -a; cat package.json 2>/dev/null | head -40; ls .gitmodules t3.json scripts 2>&1
   ```
   Note the lockfile, the dev/test/typecheck/lint scripts and their ports (check `vite.config.*`, `next` flags, `wrangler.*`), any submodules, and an icon (`public/favicon.svg`, `app/icon.svg`). If `t3.json` already exists, merge into it rather than replacing it.

2. **Copy the scripts.**
   ```bash
   mkdir -p scripts
   cp $SKILL_DIR/templates/setup-worktree.sh $SKILL_DIR/templates/clean-worktree.sh scripts/
   chmod +x scripts/setup-worktree.sh scripts/clean-worktree.sh
   ```
   Adapt them only when the repo needs it:
   - Setup: add a step the repo needs after install (a codegen, `prisma generate`, copying another gitignored secret file).
   - Clean: add a build folder the repo uses (`target` for Rust, `build`). Never add a folder that holds local state: `data/`, `.wrangler/`, local DB files, `.env*`. The tracked-file guard protects committed folders, not ignored state.
   If the repo already has a `scripts/` folder with a different convention (`.ts` scripts, `bin/`), follow it.

3. **Write `t3.json`.** Start from this and keep only what the repo has:
   ```json
   {
     "$schema": "https://t3.codes/schema/t3.json",
     "iconPath": "public/favicon.svg",
     "worktreeSubmodules": "none",
     "scripts": [
       { "name": "Setup Worktree", "command": "bash scripts/setup-worktree.sh", "icon": "configure", "runOnWorktreeCreate": true, "async": false },
       { "name": "Clean Worktree", "command": "bash scripts/clean-worktree.sh", "icon": "configure", "runOnSettle": true },
       { "name": "Dev", "command": "pnpm dev", "icon": "play", "stopOnSettle": true, "previewUrl": "http://localhost:3000" },
       { "name": "Test", "command": "pnpm test", "icon": "test" },
       { "name": "Typecheck", "command": "pnpm typecheck", "icon": "lint" }
     ]
   }
   ```
   - `worktreeSubmodules: "none"` only when there's no `.gitmodules`. Drop the key otherwise.
   - Every long-running action (dev servers, workers) gets `stopOnSettle: true`. Add `previewUrl` when it serves a page and the port is fixed.
   - Use the repo's package manager in commands. Skip actions for scripts that don't exist.

4. **Test it for real.** Check disk first (an install in a JS worktree costs about 1.3 GB; need 5 GB left after):
   ```bash
   df -h /System/Volumes/Data | tail -1
   bash -n scripts/setup-worktree.sh && bash -n scripts/clean-worktree.sh
   python3 -m json.tool t3.json > /dev/null && echo json-ok
   git ls-files | grep -E '(^|/)(node_modules|dist|\.output|\.next|\.venv|coverage)/' | head
   ```
   The last line should print nothing. If it prints tracked build output, that folder is kept by the guard, which is correct, but say so in the report.
   In a linked worktree, run `bash scripts/setup-worktree.sh` then `bash scripts/clean-worktree.sh` and confirm install finishes and clean prints `freed N MB`. In the main checkout, run only the clean script and confirm it prints `not a linked worktree, skipping`.

5. **Save the actions to the T3 project.** Load `mcp__t3-code__t3_project_list` and `mcp__t3-code__t3_project_update` with ToolSearch. Find the project whose `repositoryIdentity.rootPath` (or `workspaceRoot`) is this repo. Then call `t3_project_update` with `scripts` mirroring `t3.json`. Each project script needs `id` (short slug: `install`, `clean`, `dev`, `test`) and `runOnWorktreeCreate` (explicit `false` on all but setup). Copy `runOnSettle`, `stopOnSettle`, `async` and `previewUrl` over as-is. This replaces the whole list, so read the existing project scripts first and keep any the user added that aren't covered.

6. **Document it.** If the repo has `AGENTS.md` or `CLAUDE.md` with a commands section, add two lines for the scripts and one sentence that `t3.json` actions need importing in Settings > Projects > Actions.

7. **Report.** List the files written, the test results (`freed N MB`), and that nothing applies to new worktrees until the files are on the default branch. Don't commit unless asked; offer to commit and open a PR.

## Don'ts

- Don't set `runOnWorktreeCreate` or `runOnSettle` on more than one action.
- Don't put secrets in `t3.json`. Setup copies them from the main checkout instead.
- Don't use `git clean -X` in the clean script. It deletes ignored local state (`.env`, local databases).
- Don't start a dev server to "test" the dev action.
