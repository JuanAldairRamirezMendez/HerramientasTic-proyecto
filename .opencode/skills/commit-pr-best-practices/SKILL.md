---
name: Commit and PR Best Practices
description: Use before creating or reviewing any commit, branch, or pull request in this project. Enforces conventional commits, atomic changes, quality gates, honest PR descriptions, and the main/develop/release flow with safe submodule handling.
---

# Commit and PR Best Practices

Apply this workflow to every commit and pull request you create in this
repository, including its submodules.

## 1. Branch first

Never commit directly to `main`, `master`, or `develop` unless the user
explicitly asks for it.

Use a short, scoped branch name:

```text
feat/<topic>        new capability
fix/<topic>         bug fix
refactor/<topic>    behavior-preserving change
chore/<topic>       tooling, deps, cleanup
docs/<topic>        documentation only
test/<topic>        tests only
release/<version>   promotion branch cut from develop
hotfix/<topic>      urgent fix cut from main
```

Examples: `chore/cleanup-legacy-provider`, `fix/job-timeout`, `feat/gemini-classifier`.

Create every work branch from `develop` (backend/frontend). The root repo
currently uses `master`; treat it as its stable branch until a `develop`/`main`
split is introduced.

## 2. Branch and promotion flow

Branch model:

```text
main        stable / production
  ↑
develop     integration
  ↑
feature/*   short-lived work branches
```

Rules:

- `main` only receives changes from `develop` or from a `release/*` branch cut
  from `develop`.
- `develop` receives PRs from `feat/*`, `fix/*`, `chore/*`, `docs/*`,
  `refactor/*`, and `test/*`.
- Never send a feature branch directly to `main`.
- Never cut a promotion branch from `main`.
- The only branch that starts from `main` is `hotfix/*`.

### Change or feature

1. Update `develop`:

   ```bash
   git checkout develop
   git pull --ff-only origin develop
   ```

2. Create the child branch:

   ```bash
   git checkout -b feat/<topic>
   ```

3. Commit atomically, push, and open the PR to `develop`:

   ```bash
   git push -u origin feat/<topic>
   gh pr create --base develop --head feat/<topic>
   ```

4. Wait for the required checks and approval, then merge. Delete the branch
   after merging.

### Promotion to `main`

Use one of these two forms. Both keep the promotion branch rooted in
`develop`; neither requires "Update branch".

#### Option A — direct `develop` → `main`

Use when `develop` already contains `main`:

```bash
git checkout develop
git pull --ff-only origin develop
gh pr create --base main --head develop
```

If `main` has commits that `develop` does not contain, do the back-merge
first. Otherwise GitHub will ask for "Update branch".

#### Option B — `release/*` cut from `develop`

Use when `develop` and `main` diverged or the release needs stabilization:

```text
develop ──┬── release/<version> ──> PR → main
main ─────┘
```

```bash
git checkout develop
git pull --ff-only origin develop
git checkout -b release/<version>
git merge origin/main          # resolve the divergence
# resolve conflicts deliberately
git push -u origin release/<version>
gh pr create --base main --head release/<version>
```

The release branch is a child of `develop` and also contains `main`, so the PR
is up to date and does not need "Update branch".

### Back-merge `main` into `develop`

After every promotion, `main` can contain merge commits that `develop` lacks.
Sync them back through a child of `develop`:

```bash
git checkout develop
git pull --ff-only origin develop
git checkout -b chore/sync-main-into-develop
git merge origin/main
# resolve conflicts
git push -u origin chore/sync-main-into-develop
gh pr create --base develop --head chore/sync-main-into-develop
```

This is the "child of `develop` → `develop`" PR. It keeps future promotions
clean. If an empty tree diff makes the PR awkward, merge the release branch back
into `develop` instead, or ask an admin to allow a direct sync.

### Hotfixes

```text
main → hotfix/<topic> → main
                       ↘ develop   (back-merge required)
```

- Cut `hotfix/*` from `main`.
- Open the PR to `main` with the minimum change.
- After merging, back-merge `main` into `develop` so the fix is not lost.

### Avoid "Update branch"

"Update branch" does not create another PR. It merges the base into the PR head
(or rebases it). It appears when the head is behind the base and the repository
requires up-to-date branches.

Avoid it by:

- syncing the source branch with its base before opening the PR,
- using a `release/*` branch cut from `develop` and merging `main` into it,
- keeping `develop` synced after every promotion.

If the head branch is protected and has conflicts, GitHub cannot update it.
Resolve the conflicts on a child branch and PR that child to the protected head
branch.

### Root repository exception

The root repository currently has only `master`, not `main`/`develop`. Treat
`master` as its stable branch. If the team adopts the full flow there, create
`develop` from `master` and either keep `master` as the stable branch or rename
it to `main` and update the default branch.

## 3. Make atomic commits

One commit = one logical change. Do not mix refactors, formatting, dependency
bumps, and behavior changes in the same commit.

Before staging, inspect:

```bash
git status --short
git diff
git diff --check
```

Stage intentionally:

```bash
git add <path> ...
git diff --cached
```

Never commit:

- `.env`, credentials, tokens, or private keys,
- `node_modules/`, `dist/`, coverage, or build caches,
- generated graph dumps unless the change is specifically about them,
- unrelated local changes or submodule dirt.

## 4. Write a conventional commit

Format:

```text
<type>(<scope>): <imperative subject>

<why the change is needed>

<optional footer: refs, breaking change, co-authors>
```

Rules:

- Subject in imperative mood, lowercase, no trailing period, <= 72 chars.
- Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`,
  `chore`, `style`.
- Scope is the affected area: `ai`, `compose`, `env`, `frontend`, `backend`,
  `docs`, `skills`.
- Body explains *why*, not *what*. The diff already shows what changed.
- Breaking changes: add `!` after the type/scope and a `BREAKING CHANGE:` footer.

Examples:

```text
refactor(ai)!: replace the legacy local provider with Gemini

The legacy provider required local compute and duplicated the provider chain.
Gemini is now the only remote provider; keyword classification remains the
offline fallback.

BREAKING CHANGE: GEMINI_API_KEY is now required at startup.
```

```text
build(compose): add a Redis healthcheck and align service env vars
```

## 5. Run quality gates

Run the checks that apply to the changed repo before committing:

```bash
npm run lint
npm run typecheck
npm test
npm run build        # when the change affects production output
docker compose config  # when docker-compose.yml changes
```

If a check cannot run, say so explicitly in the commit body or PR description.
Do not claim a check passed if it was skipped.

## 6. Handle submodules correctly

This root repo tracks backend and frontend as git submodules.

Order of operations:

1. Commit and push the change in the submodule.
2. Verify the submodule commit exists on its remote branch.
3. Update the root gitlink by staging the submodule path.
4. Commit the root with a message such as
   `chore: bump backend to the Gemini-only release`.
5. Merge the submodule PRs first, then the root PR. The root PR must point to
   commits that already exist on the remote.

Never point a parent commit at an unpushed submodule commit unless the user
understands the branch is local-only. Never commit a dirty submodule pointer by
accident: run `git submodule status` and `git diff --submodule=short`.

## 7. Open a reviewable PR

PR title follows the same conventional format as the main commit. Description:

```markdown
## Summary
One or two sentences on the problem and the solution.

## Changes
- Bullet list of the meaningful changes.
- Note breaking changes and migrations.

## Testing
- [ ] `npm run lint`
- [ ] `npm run typecheck`
- [ ] `npm test`
- [ ] Manual check: ...

## Risks and rollback
What can break, and how to revert safely.

## Related
Closes #...
```

Include screenshots or short recordings for UI changes. Keep PRs small enough
to review in one sitting. Link the issue and call out follow-up work.

## 8. Review your own diff

Before pushing:

```bash
git log --oneline -5
git diff origin/<base>...HEAD
git status --short
```

Check for debug logs, commented-out code, secrets, unrelated files, and
accidental formatting churn. Confirm CI is green after pushing.

## 9. Do not rewrite shared history

Do not force-push a branch under review without warning the reviewers. Do not
amend or rebase commits that others may have based work on.

## Quick checklist

- [ ] Branch created from `develop` (or `hotfix/*` from `main`).
- [ ] PR targets `develop`; promotion targets `main` from `develop` or a
      `release/*` cut from `develop`.
- [ ] `main` back-merged into `develop` after promotion.
- [ ] No "Update branch" needed because the head already contains the base.
- [ ] One logical change per commit.
- [ ] Conventional commit message with a why-focused body.
- [ ] No secrets, build artifacts, or unrelated files.
- [ ] Lint, typecheck, tests, and build run or explicitly waived.
- [ ] Submodule commits pushed before updating the parent gitlink.
- [ ] PR description complete and honest.
- [ ] Self-review done; CI green.
