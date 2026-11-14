# Operon (bbx) — agent notes

Shared instructions for every coding agent working in this repository.

## Flutter toolchain

- Use `/root/sdk347/flutter` (Flutter 3.47.9 / Dart 3.13.7). `/root/sdk` (3.35.3) is too old for `pubspec.lock`.
- It is already on PATH via `~/.bashrc` and `/usr/local/bin` symlinks, so plain `flutter` / `dart` should work.
- If a shell does not inherit it:

```bash
export PATH=/root/sdk347/flutter/bin:$PATH
```

## Building the APK

Gradle lives outside the project and the default JDK is too old, so a bare
`flutter build apk` fails. This is the working recipe (Windows Git Bash):

```bash
export JAVA_HOME=/d/dev/Java/ms-21.0.7          # PATH 里默认是 java8，AGP 8 要 17+
export GRADLE_USER_HOME=/d/dev/gradle-home      # 已缓存 gradle-8.12-all，代理配置也在这里
export PATH="$JAVA_HOME/bin:/d/dev/flutter-sdk/bin:/d/dev/android-sdk/platform-tools:$PATH"

flutter build apk --debug                       # 首次约 7 分钟，之后增量 1-2 分钟
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Notes:

- `android/gradlew` 与 `gradle/wrapper/gradle-wrapper.jar` 已入库（Gradle 8.12，
  与本机缓存的发行版对应）。改 `distributionUrl` 前先确认本地有对应缓存，
  否则会走网络下载。
- 本机 Flutter 是 **3.35.5**（AGENTS 提到的 3.47.9 路径只存在于另一台机器）。
  它会自动把 `minSdkVersion 21` 改写成 `flutter.minSdkVersion`，而 3.35 的默认
  值是 **24**，所以实际 APK 的 minSdk 是 24（Android 7+）。要改回 21 需要写成
  `minSdk = 21` 并自担引擎支持风险。
- 构建产物在 `build/`（已 gitignore）。

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

**一个功能只验证一次，在最后。** 不要每改几行就跑 `analyze` / `test`。
把「一个功能」当成一批改动：先把这批全改完，再跑一次 `flutter analyze --no-pub`
和一次测试。理由是验证本身不慢，但它在每一步都会打断思路、把一次改动
切成十几轮；一个小功能的墙钟时间主要花在这里，不花在编译上。

具体到操作：

- 中途发现语法或类型错误，凭阅读修，不要用工具去确认；
- 不用「先跑一次看看有没有错」当探路手段，先把设计想清楚；
- 功能做完了才跑验证；失败了只重跑那个文件（`--plain-name` 定位单例），
  不要为了「看得更清楚」重跑整个套件；
- 提交/推送前跑一次全量。
