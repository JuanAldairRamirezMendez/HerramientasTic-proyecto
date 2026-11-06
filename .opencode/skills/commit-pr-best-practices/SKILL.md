---
name: Commit and PR Best Practices
description: Use before creating or reviewing any commit, branch, or pull request in this project. Enforces conventional commits, atomic changes, quality gates, honest PR descriptions, and safe submodule handling.
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
```

Examples: `chore/cleanup-legacy-provider`, `fix/job-timeout`, `feat/gemini-classifier`.

Create the branch from the correct base (`develop` for backend/frontend,
`origin/master` for the root repo unless told otherwise).

## 2. Make atomic commits

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

## 3. Write a conventional commit

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

## 4. Run quality gates

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

## 5. Handle submodules correctly

This root repo tracks backend and frontend as git submodules.

Order of operations:

1. Commit and push the change in the submodule.
2. Verify the submodule commit exists on its remote branch.
3. Update the root gitlink by staging the submodule path.
4. Commit the root with a message such as
   `chore: bump backend to the Gemini-only release`.

Never point a parent commit at an unpushed submodule commit unless the user
understands the branch is local-only. Never commit a dirty submodule pointer by
accident: run `git submodule status` and `git diff --submodule=short`.

## 6. Open a reviewable PR

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

## 7. Review your own diff

Before pushing:

```bash
git log --oneline -5
git diff origin/<base>...HEAD
git status --short
```

Check for debug logs, commented-out code, secrets, unrelated files, and
accidental formatting churn. Confirm CI is green after pushing.

## 8. Do not rewrite shared history

Do not force-push a branch under review without warning the reviewers. Do not
amend or rebase commits that others may have based work on.

## Quick checklist

- [ ] Branch created from the right base.
- [ ] One logical change per commit.
- [ ] Conventional commit message with a why-focused body.
- [ ] No secrets, build artifacts, or unrelated files.
- [ ] Lint, typecheck, tests, and build run or explicitly waived.
- [ ] Submodule commits pushed before updating the parent gitlink.
- [ ] PR description complete and honest.
- [ ] Self-review done; CI green.
