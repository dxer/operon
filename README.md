# Operon v0.1.0 - 轻量级通用 AI 智能体安卓浏览器 (Operon Agentic Browser)

> *"Don't just browse. Operate."* —— 不仅是浏览，更是操控。

基于 **Flutter** 与 **Android 原生 WebView (`flutter_inappwebview`)** 构建的高性能、全网自适应的通用 AI 智能体浏览器。
支持**任意现代网页的自主导航、复杂 SPA 交互、结构化数据采集（Scraping）、表单填写、自动发帖与回帖**。

---

## 🌟 核心特性 (v0.1.0)

1. **轻量级原生内核**：
   * 基于 Android 系统的原生 Chromium WebView，安装包极小（无需打包冗余浏览器内核），内存占用低。
   * 支持硬件加速与现代化 HTML5 / WebGL / 单页应用（SPA）渲染。
2. **“替身”虚拟光标与真实手势动画（Ghost Cursor & Touch Ripple）**：
   * AI 点击网页元素时，屏幕上浮现半透明微光光标，平滑滑动定位到目标坐标，并触发扩散触控波纹。
   * 让用户以第一视角直观目睹 AI 真实操作轨迹，极客科技感拉满！
3. **深度防反爬指纹（Stealth Mode）与 CAPTCHA 人机盾智能接管**：
   * 自动抹除 `navigator.webdriver` 自动化标识，伪装 Chrome Runtime 与多语言环境。
   * 实时侦测 Cloudflare Turnstile、极验（Geetest）、Arkose Labs、reCAPTCHA 等验证码弹窗；一旦拦截自动暂停并震动/推送提醒用户手动滑块通过，通过后 AI 自动无缝继续任务。
4. **宏录制与零 Token 极速重放（Macro Record & Zero-Token Replay）**：
   * 任何通过大模型成功执行的任务，都可以一键 **“存为快捷宏”**。
   * 下次遇到高频固定需求（如每日签到、固定发推、定期抓取），直接通过宏在 **1-2 秒内瞬间完成**，**大模型调用费用为 0**！
5. **后台挂起与系统级推送（Background Runner & Push Notification）**：
   * 任务在手机后台静默运行时，一旦任务达成、抓取到数据、或需要人工安全授权时，第一时间发送 Android 原生系统通知唤醒。
6. **深度 Shadow DOM 与 IFrame 穿透**：
   * 采用递归穿透算法，能够识别包含 Web Components、Shadow Root、嵌套 IFrame 的复杂现代前端架构（如 Shopify、YouTube、后台管理系统等）。
7. **全能键盘模拟与原子动作扩充**：
   * **`press_key`**：支持模拟真实按键（`Enter`、`Escape`、`Backspace`、`Tab`）。完美解决很多网站**输入关键词后没有搜索按钮、必须敲回车提交**的顽疾。
   * **`select_option`**：原生支持网页 `<select>` 下拉菜单的值匹配与切换。
   * **`hover`**：支持鼠标悬停动作，触发展开二级折叠菜单。
   * **`go_back`**：智能体若误触链接，具备“浏览器后退一步”的自愈纠错能力。
8. **双通道感知（交互打标 + 内容语义抽取）**：
   * 自动分离**【页面主要内容摘要】**与**【可交互操作元素】**。
   * 既能看懂按钮、输入框进行操作，也能看懂标题、正文、推文内容，专为**数据抓取与长文总结**深度优化。
9. **智能 DOM 稳定度检测（MutationObserver Debounce）**：
   * 抛弃死板固定的 `sleep(1500)`。
   * 通过监听页面 DOM 节点增删和属性变化，**350ms 内无新变动即判定渲染平稳**，渲染快时瞬间进入下一步，加载慢时自动等待，兼顾极速与抗卡死。
10. **一键结构化数据采集与复制（Data Scraper）**：
    * 支持通过自然语言指令抓取表格、帖子、商品、推文并输出格式化 JSON。
    * 控制台内置**“一键复制数据”**功能，直接充当移动端无代码爬虫工具。
11. **账号登录态自动持久化**：
    * 依赖 Android 原生 `CookieManager` 与 `LocalStorage`，用户登录一次推特/X 或其他站点后，Session 永久保存，重启 App 不丢失登录态。
12. **通用大模型自由配置**：
    * 支持接入 DeepSeek、OpenAI (GPT-4o / GPT-4o-mini)、SiliconFlow、本地 Ollama 等任何 OpenAI 兼容协议。

---

## 📂 项目结构

```
operon/
├── .github/
│   └── workflows/
│       └── build-apk.yml             # GitHub Actions 自动化编译打包 CI/CD 脚本
├── assets/
│   ├── icon/
│   │   ├── app_icon.png              # 1024x1024 旗舰应用高清图标
│   │   └── app_icon_variant_*.png    # 备选设计变体
│   └── js/
│       └── agent_dom.js              # v0.1.0 引擎（Stealth、Ghost Cursor、Shadow DOM、宏选择器）
├── lib/
│   ├── main.dart                     # 应用程序入口
│   ├── config/
│   │   ├── app_constants.dart        # 默认 UA、工作流配方、系统 Prompt
│   │   └── app_theme.dart            # 暗黑科技风格主题
│   ├── models/
│   │   ├── agent_action.dart         # 动作模型（click, type, pressKey, selectOption, hover, etc.）
│   │   ├── agent_state.dart          # 智能体状态机与宏步骤累积
│   │   ├── macro_workflow.dart       # 确定性宏工作流模型
│   │   └── llm_config.dart           # 大模型连接与预设配置
│   ├── services/
│   │   ├── agent_runner.dart         # 核心 ReAct 调度、DOM 动态防抖、验证码接管
│   │   ├── macro_service.dart        # 宏持久化与零 Token 重放引擎
│   │   ├── notification_service.dart # Android 系统通知服务
│   │   ├── llm_service.dart          # 大模型 HTTP 客户端与智能降级容错
│   │   ├── storage_service.dart      # SharedPreferences 持久化
│   │   └── webview_controller_wrapper.dart # 原生 WebView 适配与 JS 桥接
│   ├── utils/
│   │   ├── json_parser.dart          # 容错提取模型 Markdown 响应中的 JSON
│   │   └── prompt_builder.dart       # 滑动窗口 Prompt 构造器
│   └── views/
│       ├── browser_page.dart         # 主浏览器视图（集成导航栏、WebView 与 AI 面板）
│       ├── settings/
│       │   └── settings_page.dart    # 模型配置、UA 切换、连通性测试
│       └── widgets/
│           ├── agent_bottom_sheet.dart # AI 控制台（指令输入、数据抓取展示、宏录制）
│           ├── macro_dialog.dart       # 快捷宏任务库弹窗
│           ├── browser_controls.dart   # 地址栏与导航条
│           └── step_log_view.dart      # 执行步骤历史时间线
├── android/                          # 原生 Android 权限、图标资源与 Gradle 配置
└── pubspec.yaml                      # Flutter 依赖清单与图标配置
```

---

## 📦 如何在 GitHub 上自动编译并直接下载 APK（非 ZIP，直接安装）

项目已内置了 GitHub Actions 自动化编译工作流 [`.github/workflows/build-apk.yml`](file:///root/workspace/bbx/.github/workflows/build-apk.yml)。

> **⚠️ 为什么有些人在 GitHub 下载到的是 ZIP 文件？**
> * GitHub Actions 页面底部的 **Artifacts** 是 GitHub 官方平台强制打包为 `.zip` 的归档；
> * 为了让你在手机上**直接下载纯 `.apk` 文件（点击即可唤起安卓安装，无需解压）**，本工作流会自动将编译出的原生安装包发布至 **GitHub Releases** 资源区！

---

### 📲 获取纯 APK 的两种方式：

#### 方式一：发布新版本 Tag（推荐 ⭐️）
在本地推送版本标签：
```bash
git tag v0.1.0
git push origin v0.1.0
```
GitHub 会自动编译并在你的仓库右侧 **Releases** 中生成一个发布包，里面直接附带原生的 **`operon-v0.1.0.apk`** 文件，手机浏览器点击即可直接下载安装！

#### 方式二：在 GitHub 网页上一键手动构建
1. 打开你的 GitHub 仓库主页，点击顶部的 **Actions** 选项卡；
2. 在左侧选择 **Build & Release Android APK** 工作流；
3. 点击右侧的 **Run workflow** 绿色按钮触发编译；
4. 编译完成后，直接前往仓库主页右侧的 **Releases** 区域，在 `Operon Latest Build` 下直接下载纯原生的 **`operon-v0.1.0.apk`**！

---

## 💻 本地编译与运行 (可选)

如果你本地电脑已经安装好了 Flutter 开发环境：

```bash
# 1. 获取依赖
flutter pub get

# 2. 连接 Android 手机或模拟器调试
flutter run

# 3. 本地打包 Release APK
flutter build apk --release
# 生成路径：build/app/outputs/flutter-apk/app-release.apk
```

---

## 🚀 常用通用指令示例

直接在底栏输入框键入自然语言，或点击内置的快捷配方：

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
