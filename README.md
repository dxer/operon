# Operon - 轻量级通用 AI 智能体安卓浏览器 (Operon Agentic Browser)

> *"Don't just browse. Operate."* —— 不仅是浏览，更是操控。

基于 **Flutter** 与 **Android 原生 WebView (`flutter_inappwebview`)** 构建的轻量级 AI 智能体浏览器。
控制层通过纯 Dart 直连 WebView 的 DevTools 抽象 Unix Socket（CDP），以**无障碍树（Accessibility Tree `ref`）+ 浏览器真实输入事件 + 真人协同（Human-in-the-loop）**完成网页浏览、表单填写、多标签切换、文件上传与结构化数据抽取。

---

## 🌟 核心特性

1. **Via 式极简交互**：
   * 顶部单行胶囊地址栏 + 底部操作栏，单手即可完成浏览与 AI 调度。
   * 全屏 edge-to-edge 画布、停靠式 AI 状态条、克制的动效与触感反馈。
2. **纯 Dart CDP 控制层 (`lib/control/`)**：
   * 基于 Android 原生 Chromium WebView，直连本进程 `@webview_devtools_remote_<pid>` 抽象 Socket，无需额外打包浏览器内核。
   * 通过 `Accessibility.getFullAXTree` 生成稳定的交互 `ref`，支持 Shadow DOM 与 IFrame 穿透。
   * 点击、输入、悬停、按键、滚动均派发真实浏览器输入事件（`Input.dispatchMouseEvent` / `TouchEvent` / `KeyEvent`），兼容 React/Vue 等受控组件，并返回动作回执（`Receipt`：`delivery`、`pageReacted`、`changes`）。
3. **“替身”虚拟光标与触控波纹（Ghost Cursor）**：
   * AI 操作页面元素时，在真实落点坐标上呈现移动光标与扩散触控波纹，过程全程可见。
   * 派发前用描边框出**即将操作的那个元素**：落点与目标框都由控制层在发事件前算好，不是事后补画。
4. **真人协同与安全边界（Human-in-the-loop）**：
   * **写操作分级**：普通提交/发布在 Safe Mode 下弹出授权卡片并展示目标站点与发送正文；删除/弹窗操作强制确认；密码、验证码、支付类动作强制交由用户亲自完成（Handoff）。
   * **人机验证检测与接管**：通过无障碍树识别 Cloudflare Turnstile、Geetest、Arkose Labs、reCAPTCHA 等验证挑战，自动暂停并推送通知，用户滑块通过后无缝继续。
   * **站点信任与禁用列表**：支持按域名配置“始终允许”与“禁止访问”。
   * **文件选择交接**：模型调用 `upload` 时可直接唤起系统文件选择器由用户选取文件，无需手输设备路径。
5. **通用 ReAct 循环与上下文管理 (`lib/agent/`)**：
   * 支持标准 OpenAI Function Calling 工具协议（`snapshot`、`read`、`find`、`screenshot`、`click`、`type`、`clear`、`select`、`hover`、`press`、`scroll`、`navigate`、`back`、`forward`、`tabs`、`switch_tab`、`close_tab`、`upload`、`wait`、`handle_dialog`、`ask_user`、`done`）。
   * 自动上下文裁剪（省略早期工具大结果与旧截图，保留最近轮次与用户指令）、循环防呆守卫（重复无反应/连续失败保护）。
   * 支持图片与文本文件作为任务附件、多轮对话历史持久化（`ConversationStore`）与快捷指令（`/` 触发）。
   * 结构化结果可以拿走：面板里的字段表格、一键导出 CSV（带 BOM，Excel 直接打开）、复制 JSON、分享 Markdown 表格；缺字段会明说，不留下没解释的空格。
6. **通用大模型配置与多预设切换**：
   * 支持 DeepSeek、OpenAI、通义千问、智谱 GLM、Moonshot、本地 Ollama 等任何 OpenAI 兼容协议。
   * 支持保存多个模型配置预设一键切换，并为不同模型单独记忆 `ModelProfile`（上下文窗口、图片输入、思考参数、工具调用能力）。
7. **日常浏览增强**：
   * 多标签总览、书签/历史记录、页内正文阅读模式与 AI 速读摘要、划词翻译/解释、下载管理、页内查找、地址栏联想、系统分享与外部链接 Intent 接管。

---

## 📂 项目结构

```text
operon/
├── .github/workflows/build-apk.yml   # CI：analyze + test + 打包 + 发布 APK
├── assets/
│   ├── icon/                         # 应用图标
│   └── js/page_helpers.js            # 页内助手：阅读模式 / 划词信息 / 伪装辅助
├── lib/
│   ├── main.dart                     # 入口：edge-to-edge、WebView DevTools 开启、主题
│   ├── config/                       # 主题、Token 规范与基础常量
│   ├── agent/                        # 通用 Agent 循环、上下文裁剪、防呆守卫、权限分级、工具协议
│   ├── control/                      # 纯 Dart CDP 控制层：transport / perception / interaction / protocol
│   ├── models/                       # AgentState / Conversation / LlmConfig & LlmPreset / ModelProfile / WebTab
│   ├── services/                     # OpenAI 兼容客户端、存储、通知、对话持久化、下载、Intent
│   ├── utils/                        # URL 规范化、取消令牌
│   └── views/                        # 浏览器主页、设置页、诊断页与底部 AI 对话面板
├── test/                             # 单元测试与 FakeDevTools / FakeOpenAi 端到端测试
├── android/                          # 原生 Android 权限、图标资源与 Gradle 配置
└── pubspec.yaml
```

---

## 📦 在 GitHub 上自动编译并下载 APK

项目内置 GitHub Actions 工作流 [`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml)，CI 会先执行 `flutter analyze` 与 `flutter test`，通过后再编译并发布纯 `.apk` 至 **GitHub Releases**：

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

---

## 💻 本地编译与运行

```bash
# 1. 获取依赖
flutter pub get

# 2. 静态检查与单元测试
flutter analyze --no-pub
flutter test --no-pub

# 3. 连接 Android 手机或模拟器调试
flutter run

# 4. 本地打包 Release APK
flutter build apk --release
# 生成路径：build/app/outputs/flutter-apk/app-release.apk
```

---

## 🔐 安全提示

* API Key 保存在本机 `SharedPreferences` 中，请勿在公共设备上使用。
* AI 生成的动作会在你已登录的网页上下文中派发，建议保持 **Safe Mode** 开启。
* 发布正式版前，请将 `android/app/operon.jks` 与签名密码迁移到 CI Secrets，避免仓库泄露签名材料。
