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
| `fork-updater` | The app updates from this fork's builds; the workflow that makes them. Fork only | You, rarely |
| `rob` | Upstream `main` + every branch in `fork-fixes.txt` | Only the script (it rebuilds and force-pushes it) |

Run the fork's build of `rob` (below). Open upstream PRs from the fix branches only, never from `fork-tools` or
`fork-updater`: `gh pr create --repo fillinthe/phosphor --head rdysell:<branch>`.

## Pulling an upstream update

From any clone of Phosphor:

```bash
scripts/fork/update-fork.sh          # dry run: what moves, which fixes merge, which are upstream already
scripts/fork/update-fork.sh --push   # moves the fork's main forward and pushes the rebuilt rob
```

The push of `rob` starts the fork's build (below), and running fork builds update to it. The script works in a
temporary worktree, so your checkout isn't touched.

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

## The fork's builds and the app's updater

Upstream's app updates from **fillinthe/phosphor**'s releases. Installing one of those over a build of `rob` swaps in
upstream's app, and every fix upstream hasn't merged is gone. So `fork-updater` (merged into `rob`) changes two things:

- **Check for Updates reads this fork's releases only** (`crates/phosphor/src/update.rs`), and only ever installs a
  fork build: a version ending in `-rob.<build>`. Order: `0.5.19 < 0.5.19-rob.1 < 0.5.19-rob.2 < 0.5.20 <
  0.5.20-rob.3` (a fork build is upstream's release plus the fixes). It sends no update count to upstream's counter.
- **`.github/workflows/fork-mac.yml` builds `rob` on GitHub** on every push of `rob`: the Apple Silicon app, version
  `<upstream version>-rob.<run number>`, published as release `v<that version>` with `Phosphor-mac.zip`. A running
  fork build installs it within the hour or when it next opens, as upstream's builds do (never mid-show; "Install
  updates by themselves" in the Update window turns that off). The workflow runs only in `rdysell/phosphor-fork`.

The first time, install by hand: download `Phosphor-mac.zip` from the fork's
[latest release](https://github.com/rdysell/phosphor-fork/releases/latest), quit Phosphor, drag the app into
Applications and choose Replace. Settings, projects and shaders stay (same app id as upstream's).

Signing: with no secrets set, the build is signed ad-hoc. macOS blocks its first open once (System Settings › Privacy &
Security › Open Anyway); updates the app installs itself aren't blocked, but macOS may ask again for camera,
microphone and screen recording access after each one. With a Developer ID certificate and a notary login in the
fork's secrets (listed at the top of `fork-mac.yml`) it's signed and notarized instead. Fork builds have no virtual
camera (it needs upstream's signing).

Once, before the first build: turn on Actions in the fork (forks start with them off). Upstream's own workflows
(`windows.yml`, `linux.yml`, `mac-intel.yml`) would then also run on every push to the fork's `main`; turn them off
with `gh workflow disable <file> -R rdysell/phosphor-fork`.

A build of `rob` made on your own Mac (`scripts/bundle-mac.sh` on the `rob` branch) calls itself plain `0.5.19`, is
marked as a test build, and offers the fork's newer builds without installing them by itself.
