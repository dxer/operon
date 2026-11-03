# Operon (bbx) — agent notes

Shared instructions for every coding agent working in this repository.

## Flutter toolchain

- Use `/root/sdk347/flutter` (Flutter 3.47.9 / Dart 3.13.7). `/root/sdk` (3.35.3) is too old for `pubspec.lock`.
- It is already on PATH via `~/.bashrc` and `/usr/local/bin` symlinks, so plain `flutter` / `dart` should work.
- If a shell does not inherit it:

```bash
export PATH=/root/sdk347/flutter/bin:$PATH
```

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
