# Operon - 轻量级通用 AI 智能体安卓浏览器 (Operon Agentic Browser)

> *"Don't just browse. Operate."* —— 不仅是浏览，更是操控。

基于 **Flutter** 与 **Android 原生 WebView (`flutter_inappwebview`)** 构建的高性能、全网自适应的通用 AI 智能体浏览器。
支持**任意现代网页的自主导航、复杂 SPA 交互、结构化数据采集（Scraping）、表单填写、自动发帖与回帖**。

---

## 🌟 v2.0 通用性重大升级

1. **深度 Shadow DOM 与 IFrame 穿透**：
   * 采用递归穿透算法，能够识别包含 Web Components、Shadow Root、嵌套 IFrame 的复杂现代前端架构（如 Shopify、YouTube、后台管理系统等）。
2. **全能键盘模拟与原子动作扩充**：
   * **`press_key`**：支持模拟真实按键（`Enter`、`Escape`、`Backspace`、`Tab`）。完美解决很多网站**输入关键词后没有搜索按钮、必须敲回车提交**的顽疾。
   * **`select_option`**：原生支持网页 `<select>` 下拉菜单的值匹配与切换。
   * **`hover`**：支持鼠标悬停动作，触发展开二级折叠菜单。
   * **`go_back`**：智能体若误触链接，具备“浏览器后退一步”的自愈纠错能力。
3. **双通道感知（交互打标 + 内容语义抽取）**：
   * 自动分离**【页面主要内容摘要】**与**【可交互操作元素】**。
   * 既能看懂按钮、输入框进行操作，也能看懂标题、正文、推文内容，专为**数据抓取与长文总结**深度优化。
4. **智能 DOM 稳定度检测（MutationObserver Debounce）**：
   * 抛弃死板固定的 `sleep(1500)`。
   * 通过监听页面 DOM 节点增删和属性变化，**350ms 内无新变动即判定渲染平稳**，渲染快时瞬间进入下一步，加载慢时自动等待，兼顾极速与抗卡死。
5. **一键结构化数据采集与复制（Data Scraper）**：
   * 支持通过自然语言指令抓取表格、帖子、商品、推文并输出格式化 JSON。
   * 控制台内置**“一键复制数据”**功能，直接充当移动端无代码爬虫工具。
6. **通用自动化工作流配方（Universal Recipes）**：
   * 内置社媒互动、全网搜索、正文总结、列表数据采集等多套通用任务模版，一键即用。

---

## 📂 项目结构

```
bbx/
├── assets/
│   └── js/
│       └── agent_dom.js              # v2.0 通用引擎（Shadow DOM 穿透、键盘仿真、数据提取、DOM 平稳检测）
├── lib/
│   ├── main.dart                     # 应用程序入口
│   ├── config/
│   │   ├── app_constants.dart        # 默认 UA、工作流配方（Recipes）、v2.0 系统 Prompt
│   │   └── app_theme.dart            # 科技暗黑风格主题定义
│   ├── models/
│   │   ├── agent_action.dart         # 泛化动作模型（click, type, pressKey, selectOption, hover, extractData, finish）
│   │   ├── agent_state.dart          # 智能体状态机模型与抓取数据存储
│   │   └── llm_config.dart           # 大模型连接配置与预设服务商（DeepSeek / OpenAI / Ollama 等）
│   ├── services/
│   │   ├── agent_runner.dart         # 核心 ReAct 调度、动态平稳等待、敏感确认与数据持久
│   │   ├── llm_service.dart          # OpenAI 规范的 HTTP 客户端与异常重试
│   │   ├── storage_service.dart      # SharedPreferences 持久化封装
│   │   └── webview_controller_wrapper.dart # 原生 WebView 适配与 JS 桥接
│   ├── utils/
│   │   ├── json_parser.dart          # 容错提取模型 Markdown 响应中的 JSON
│   │   └── prompt_builder.dart       # 滑动窗口 Prompt 构造器（省略历史 DOM 防爆 Token）
│   └── views/
│       ├── browser_page.dart         # 主浏览器视图（集成导航栏、WebView 与 AI 悬浮底栏）
│       ├── settings/
│       │   └── settings_page.dart    # 模型配置、UA 切换、连通性测试、清除 Cookie
│       └── widgets/
│           ├── agent_bottom_sheet.dart # AI 控制台（指令输入、数据抓取展示、一键复制、配方卡片）
│           ├── browser_controls.dart   # 地址栏、前进后退、刷新、进度指示条
│           └── step_log_view.dart      # 执行步骤历史时间线
├── android/                          # 原生 Android 权限与 Gradle 配置
└── pubspec.yaml                      # Flutter 依赖清单
```

---

## 🚀 常用通用指令示例

你可以直接在底部输入框输入如下指令，或者点击内置的工作流卡片：

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
