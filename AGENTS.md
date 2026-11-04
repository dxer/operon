# Operon (bbx) — agent notes

Shared instructions for every coding agent working in this repository.

## Flutter toolchain

- Use `/root/sdk347/flutter` (Flutter 3.47.9 / Dart 3.13.7). `/root/sdk` (3.35.3) is too old for `pubspec.lock`.
- It is already on PATH via `~/.bashrc` and `/usr/local/bin` symlinks, so plain `flutter` / `dart` should work.
- If a shell does not inherit it:

```bash
export PATH=/root/sdk347/flutter/bin:$PATH
```

## Navigating the code

The repo is indexed by CodeGraph (`.codegraph/`, git-ignored). Prefer it over
chained `grep` when you need relationships rather than text.

- Before changing a shared symbol, list everything it touches:

```bash
codegraph impact SkillPolicy        # 29 affected symbols, grouped by file
codegraph callers effective         # every call site of a method
codegraph callees SkillRunner.run   # what a method calls
```

- Find a symbol or read one node with its caller/callee trail:

```bash
codegraph query "SkillInputs"
codegraph node SkillInputs.effective
codegraph explore "how skill inputs reach the run sheet"
```

- After editing source, list the tests that need to run:

```bash
codegraph affected $(git diff --name-only)
```

Notes:

- The index is Dart-aware but not Dart-perfect: a private constructor written
  as `Foo._()` shows up as a method named `_`, and widget-tree expressions are
  not symbols. Relationships are reliable; treat "symbol not found" as a hint
  to fall back to `grep`, not as proof the symbol is unused.
- Run `codegraph sync` after large refactors; `codegraph status` shows file and
  node counts. A stale index silently misses call sites.

## Checks and tests

Always pass `--no-pub` unless `pubspec.yaml` changed. It skips dependency
resolution and saves several seconds on every run.

- Static analysis (whole project, ~5s):

```bash
flutter analyze --no-pub
```

- Only the affected tests (~10–20s):

```bash
flutter test --no-pub test/<name>_test.dart
```

- A single test case:

```bash
flutter test --no-pub test/<name>_test.dart --plain-name "keyword"
```

- Full suite before commit/push (~50s):

```bash
flutter test --no-pub
```

Run `flutter pub get` only after changing `pubspec.yaml`; afterwards
`--no-pub` is safe again.

CI (`.github/workflows/build-apk.yml`) already runs analyze plus the full test
suite, so a local full run is mainly for pre-commit confidence.

**Test once, at the end.** Run the suite when the change is complete, not after
each batch or intermediate edit. A full run takes 70–90s and `flutter analyze`
can take two minutes cold; repeating them per step dominates the wall clock on
a small change. If a test fails, debug that single file — do not re-run the
whole suite to get a clearer listing.
