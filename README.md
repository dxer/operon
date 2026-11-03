# Operon - 轻量级通用 AI 智能体安卓浏览器 (Operon Agentic Browser)

> *"Don't just browse. Operate."* —— 不仅是浏览，更是操控。

基于 **Flutter** 与 **Android 原生 WebView (`flutter_inappwebview`)** 构建的高性能、全网自适应的通用 AI 智能体浏览器。
支持**任意现代网页的自主导航、复杂 SPA 交互、结构化数据采集（Scraping）、表单填写、自动发帖与回帖**。

---

## 🌟 核心特性

1. **Via 式极简交互**：
   * 顶部单行胶囊地址栏 + 底部五指操作栏，单手即可完成浏览与 AI 调度。
   * 地址栏首次聚焦自动全选 URL，输入即走；页面下拉即可刷新。
   * 全屏 edge-to-edge 画布、停靠式 AI 状态条、克制的动效与触感反馈。
2. **轻量级原生内核**：
   * 基于 Android 系统的原生 Chromium WebView，安装包极小（无需打包冗余浏览器内核），内存占用低。
   * 支持硬件加速与现代化 HTML5 / WebGL / 单页应用（SPA）渲染。
3. **多标签浏览**：
   * 底部标签计数一键呼出标签总览，支持新开、切换、单独关闭、全部关闭。
   * `onCreateWindow` 自动接管网页弹窗，SPA 前进/后退状态实时同步。
4. **“替身”虚拟光标与真实手势动画（Ghost Cursor & Touch Ripple）**：
   * AI 点击网页元素时，屏幕上浮现半透明微光光标，平滑滑动定位到目标坐标，并触发扩散触控波纹。
5. **深度防反爬指纹（Stealth Mode）与 CAPTCHA 人机盾智能接管**：
   * 自动抹除 `navigator.webdriver` 自动化标识，伪装 Chrome Runtime 与多语言环境。
   * 实时侦测 Cloudflare Turnstile、极验（Geetest）、Arkose Labs、reCAPTCHA 等验证码弹窗；一旦拦截自动暂停并震动/推送提醒用户手动滑块通过，通过后 AI 自动无缝继续任务。
6. **宏录制与零 Token 极速重放（Macro Record & Zero-Token Replay）**：
   * 任何通过大模型成功执行的任务，都可以一键 **“存为快捷宏”**。
   * 下次遇到高频固定需求（如每日签到、固定发推、定期抓取），直接通过宏在 **1-2 秒内瞬间完成**，**大模型调用费用为 0**。
7. **后台挂起与系统级推送（Background Runner & Push Notification）**：
   * 任务在手机后台静默运行时，一旦任务达成、抓取到数据、或需要人工安全授权时，第一时间发送 Android 原生系统通知唤醒。
8. **深度 Shadow DOM 与 IFrame 穿透**：
   * 采用递归穿透算法，能够识别包含 Web Components、Shadow Root、嵌套 IFrame 的复杂现代前端架构（如 Shopify、YouTube、后台管理系统等）。
9. **全能键盘模拟与原子动作扩充**：
   * **`press_key`**：支持模拟真实按键（`Enter`、`Escape`、`Backspace`、`Tab`）。
   * **`select_option`**：原生支持网页 `<select>` 下拉菜单的值匹配与切换。
   * **`hover`**：支持鼠标悬停动作，触发展开二级折叠菜单。
   * **`go_back`**：智能体若误触链接，具备“浏览器后退一步”的自愈纠错能力。
10. **双通道感知（交互打标 + 内容语义抽取）**：
    * 自动分离**【页面主要内容摘要】**与**【可交互操作元素】**。
    * 既能看懂按钮、输入框进行操作，也能看懂标题、正文、推文内容，专为**数据抓取与长文总结**深度优化。
11. **智能 DOM 稳定度检测（MutationObserver Debounce）**：
    * 抛弃死板固定的 `sleep(1500)`。
    * 通过监听页面 DOM 节点增删和属性变化，**350ms 内无新变动即判定渲染平稳**，渲染快时瞬间进入下一步，加载慢时自动等待。
12. **一键结构化数据采集与复制（Data Scraper）**：
    * 支持通过自然语言指令抓取表格、帖子、商品、推文并输出格式化 JSON，控制台一键复制。
13. **账号登录态自动持久化**：
    * 依赖 Android 原生 `CookieManager` 与 `LocalStorage`，登录一次，重启 App 不丢失登录态。
14. **通用大模型自由配置**：
    * 支持接入 DeepSeek、OpenAI、通义千问、智谱 GLM、Moonshot、本地 Ollama 等任何 OpenAI 兼容协议。
15. **可编辑技能（Skills）与 AI 创建**：
    * 技能分为“指令型”（交给 Agent 自主执行）与“流程型”（按原子工具步骤执行）。
    * 支持 AI 用自然语言创建技能草案、本地校验、自动修复、预览与手动编辑。
    * 流程型技能支持参数、数据流、定位器候选链、失败重试、Agent 兜底和逐步骤运行时间线。
    * 写入步骤统一确认；支持重复目标/重复内容拦截，授权时展示准备发送的正文。
    * 内置“只读试运行”，执行到第一个写入步骤前停止，方便检查定位器与数据流。
    * 浏览器菜单提供定位器拾取器：点选页面元素即可得到候选链并复制到技能编辑器。
    * 支持回放宏片段（`macro.run`）与本地通知（`notify`）工具。
    * 任务完成后可一键存为可编辑技能；没有录制动作的读取/抽取任务会生成指令型技能。
    * 流程技能执行失败时，可让 AI 根据当前页面生成候选定位器，确认后保存并重跑。
    * 内置「当前页列表抽取」只读配方，按条数上限直接读取列表并结构化抽取。
    * 旧快捷指令会自动迁移为指令型技能，可导入/导出 JSON，并从录制宏或任务历史生成可编辑技能。

---

## 📂 项目结构

```
operon/
├── .github/workflows/build-apk.yml   # CI：analyze + test + 打包 + 发布 APK
├── assets/
│   ├── icon/                         # 应用图标与设计变体
│   └── js/agent_dom.js               # DOM 感知 / 动作执行 / Ghost Cursor / 宏选择器
├── lib/
│   ├── main.dart                     # 入口：edge-to-edge、主题与首页
│   ├── config/
│   │   ├── app_constants.dart        # UA、搜索引擎、工作流配方、系统 Prompt
│   │   └── app_theme.dart            # Material 3 亮/暗主题、转场、组件样式
│   ├── models/                       # AgentAction / AgentState / WebTab / 宏 / 书签 / 历史
│   ├── services/
│   │   ├── agent_runner.dart         # ReAct 循环、DOM 防抖、验证码与敏感操作接管
│   │   ├── skill_runner.dart         # 流程型技能线性执行、预算与失败策略
│   │   ├── tool_registry.dart        # 原子工具注册与执行（页面/读写/AI/子 Agent）
│   │   ├── skill_authoring_service.dart # AI 生成技能草案、校验与自动修复
│   │   ├── llm_service.dart          # OpenAI 兼容客户端（含 response_format 降级）
│   │   ├── webview_controller_wrapper.dart # JS 注入、异步 DOM 等待、页面能力封装
│   │   ├── macro_service.dart        # 宏持久化与零 Token 重放
│   │   ├── notification_service.dart # Android 系统通知
│   │   ├── storage_service.dart      # SharedPreferences 持久化
│   │   ├── theme_service.dart        # 主题切换与系统栏样式
│   │   └── user_script_service.dart  # UserScript 管理
│   ├── utils/                        # Prompt 构造、容错 JSON 提取
│   └── views/
│       ├── browser_page.dart         # 多标签容器、WebView、AI 胶囊与底部栏
│       ├── settings/                 # 通用 / 外观 / 浏览 / AI 引擎 / AI 策略 / 脚本 / 关于
│       └── widgets/                  # 地址栏、底栏、标签页、AI 面板、速读、划词、宏
├── test/                             # JsonParser 与 AgentAction 单元测试
├── android/                          # 原生 Android 权限、图标资源与 Gradle 配置
└── pubspec.yaml
```

---

## 📦 如何在 GitHub 上自动编译并直接下载 APK（非 ZIP，直接安装）

项目已内置 GitHub Actions 工作流 [`.github/workflows/build-apk.yml`](file:///root/workspace/bbx/.github/workflows/build-apk.yml)。
CI 会先执行 `flutter analyze` 与 `flutter test`，通过后再编译并发布 APK。

> **⚠️ 为什么有些人在 GitHub 下载到的是 ZIP 文件？**
> * GitHub Actions 页面底部的 **Artifacts** 是 GitHub 官方平台强制打包为 `.zip` 的归档；
> * 为了让你在手机上**直接下载纯 `.apk` 文件（点击即可唤起安卓安装，无需解压）**，本工作流会自动将编译出的原生安装包发布至 **GitHub Releases** 资源区。

### 📲 获取纯 APK 的两种方式：

#### 方式一：发布新版本 Tag（推荐 ⭐️）
```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```
GitHub 会自动编译并在仓库右侧 **Releases** 中生成发布包，直接附带原生 **`operon-vX.Y.Z.apk`**。

> **版本号只改一处**：修改 `pubspec.yaml` 的 `version: x.y.z+build` 即可。
> 设置页/关于页通过 `package_info_plus` 读取 APK 实际版本，CI 也会从 `pubspec.yaml` 自动推导 tag，无需再改其他文件。

#### 方式二：在 GitHub 网页上一键手动构建
1. 打开仓库主页，点击顶部 **Actions**；
2. 左侧选择 **Build & Release Android APK**；
3. 点击 **Run workflow**；
4. 完成后前往 **Releases** 下载 `operon-vX.Y.Z.apk`。

---

## 💻 本地编译与运行

```bash
# 1. 获取依赖
flutter pub get

# 2. 静态检查与单元测试
flutter analyze
flutter test

# 3. 连接 Android 手机或模拟器调试
flutter run

# 4. 本地打包 Release APK
flutter build apk --release
# 生成路径：build/app/outputs/flutter-apk/app-release.apk
```

> 环境要求：Flutter stable（>= 3.16）与 Java 17。Android `minSdk 21 / targetSdk 36`。

---

## 🚀 常用通用指令示例

直接在底栏 AI 胶囊或控制台输入自然语言：

1. **电商/列表数据提取**：
   * *“抓取当前页面前 5 件商品的标题与价格，并输出为结构化数据”*
2. **搜索与回车导航**：
   * *“在顶部搜索框输入 #DeepSeek，并按下 Enter 键进行搜索”*
3. **社交媒体自动回帖**：
   * *“在推特找到第一条推文，点击回复并输入：讲得太透彻了，学习了！”*
4. **文章精读与信息归纳**：
   * *“阅读当前技术博客正文，提炼出 3 个核心技术要点”*
5. **翻页与深层探索**：
   * *“向下滚动页面 2 次，寻找‘查看更多评论’按钮并点击”*

---

## 🔐 安全提示

* API Key 保存在本机 `SharedPreferences` 中，请勿在公共设备上使用。
* AI 生成的动作与 UserScript 会在网页上下文中执行，建议保持 **Safe Mode** 开启。
* 发布正式版前，请将 `android/app/operon.jks` 与签名密码迁移到 CI Secrets，避免仓库泄露签名材料。
