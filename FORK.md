# Rob's Phosphor fork

`rdysell/phosphor-fork` is a GitHub fork of [fillinthe/phosphor](https://github.com/fillinthe/phosphor) (Greg
Petersen's). We send fixes upstream as pull requests and run our own build with every fix, even ones upstream
hasn't merged yet. Pulling an upstream update never loses a fix: no fix lives on `main`, and the `rob` branch is
rebuilt from upstream plus every fix after each update.

## Branches

| Branch | What it is | Who changes it |
| --- | --- | --- |
| `main` | Upstream `main`, exactly | Only `scripts/fork/update-fork.sh` (never commit here) |
| one branch per fix (`fix-open-comp`, `isf-render-example`, …) | One fix, branched from upstream `main`; also an upstream PR | You, while working on that fix |
| `fork-tools` | This file, `fork-fixes.txt`, `scripts/fork/update-fork.sh` | You, to add or drop a fix |
| `rob` | Upstream `main` + `fork-tools` + every fix in `fork-fixes.txt` | Only the script (it rebuilds and force-pushes it) |

Build and run `rob`. Open upstream PRs from the fix branches:
`gh pr create --repo fillinthe/phosphor --head rdysell:<branch>`.

## Pulling an upstream update

From any clone of Phosphor:

```bash
scripts/fork/update-fork.sh          # dry run: what moves, which fixes merge, which are upstream already
scripts/fork/update-fork.sh --push   # moves the fork's main forward and pushes the rebuilt rob
```

Then build `rob` again. The script works in a temporary worktree, so your checkout isn't touched.

It stops without pushing if:

- **A fix no longer merges** (upstream changed the same lines). Rebase that fix branch onto upstream `main`, push it,
  and run the script again.
- **The fork's `main` has commits upstream doesn't.** Either upstream rewrote its history (it did on 2026-11-22) or
  someone committed on the fork's `main`. Check, then run it with `--push --force-main`. Fix branches made before a
  rewrite need `git rebase --onto <new upstream main> <old base> <branch>`.

It also reports the fixes upstream has merged (also when squash-merged). Take those off `fork-fixes.txt`.

## Adding a fix

1. `git worktree add -b fix-something ../fix-something <upstream main>`, make the fix, commit.
2. Push it: `git push https://github.com/rdysell/phosphor-fork.git fix-something`.
3. Add `fix-something` to `fork-fixes.txt` on `fork-tools` and push that.
4. Run `scripts/fork/update-fork.sh --push`.

## The app's own updater

Phosphor's Help › Check for Updates looks only at **fillinthe/phosphor** releases (`crates/phosphor/src/update.rs`).
On a build of `rob`, installing an upstream update swaps in upstream's app. Any fix upstream hasn't merged is then
gone until you build `rob` again. Until the fork makes its own builds, update by running the script and building
`rob`, not with Check for Updates.
