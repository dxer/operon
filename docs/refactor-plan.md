# Operon 重构方案（对标 Nanobrowser v0.3）

> 状态：方案草案，待决策
> 范围：agent 执行链路 + 页面控制层 + agent 面板 UI。技能/宏放到最后。
> 前置结论：**可以重构，而且不必推翻 Flutter。** 需要推翻的是「用 JS 模拟输入」和「每步重建一段提示词」这两件事。

---

## 0. TL;DR

1. **"效果不好"的头号原因不是模型不行，是"手"不行。** Operon 的点击是用页面内 `dispatchEvent(PointerEvent/MouseEvent)` + `el.click()` 合成的，`event.isTrusted === false`。真实站点（React 受控组件、Cloudflare、Google、飞书、大部分后台）会检查、会忽略。Nanobrowser 的做法是用 CDP `Input.dispatchMouseEvent` 发**真事件**。
2. **第二原因是"眼睛"不行。** 现在是 CSS 选择器 + innerText 拼出来的 ≤65 项文本清单，没有 role/state/value/几何，不进 iframe，不报截断，没有 diff。Nanobrowser 用 CDP 无障碍树 + ref + diff。
3. **第三原因是"记忆"不行。** `prompt_builder.dart` 每步只发 system + user 两条消息，历史被压成 `- 步骤 3: 点击 登录（失败：…）`。模型看不到自己上一步的推理和参数，等于每步都在重新认识现场。且没有原生 tool calling、没有上下文压缩、默认 15 步封顶。
4. 可行性：Android WebView **有完整 CDP agent**，同进程可直接连抽象 socket，`Input` 域可用 → Nanobrowser 的整套不变量都能搬。唯一要自己造的是 frame manager（它用 puppeteer，Android 没有等价物）。

---

## 1. 现状诊断

### 1.1 证据表

| # | 问题 | 证据 | 后果 |
|---|---|---|---|
| 1 | **输入是合成事件** | `assets/js/agent_dom.js:1571-1611`：手搓 `pointerdown/mousedown/pointerup/mouseup`，再调 `el.click()` | `isTrusted=false`。受控组件不更新 state、框架不认、风控直接拦。**这是"点了没反应"的根因** |
| 2 | **导航靠 JS 改 location 兜底** | `agent_dom.js:1615-1621`：点击 A 标签后 300ms 判 `location.href !== el.href` 就硬跳 | 打开新标签被劫持、SPA 路由被打断、双次导航 |
| 3 | **感知是启发式清单** | `agent_dom.js:1309-1535`。CSS 选择器白名单 → 视口内过滤 → 按 priority 排序 → `TARGET_BUDGET = 65` 裁剪 | 模型只看到 `[3] BUTTON: 登录`。无 role/state/checked/value/几何；超出 65 项**静默丢弃**，模型不知道自己看到的是删过的 |
| 4 | **ref 生命周期不安全** | id 写进 `data-operon-id` 属性 + JS `elementsMap` 持元素引用，每步 `nextElementId=1` 重编号（`agent_dom.js:1476-1480`） | SPA 重渲染后：要么 `isConnected=false` 报错白走一步，要么更糟——命中了**同属性名的新元素**（点错东西） |
| 5 | **不进 iframe** | `querySelectorAllDeep`（`:336-360`）只递归 `shadowRoot`；全文 `contentDocument` 出现 0 次 | 支付、登录三方、嵌入式后台完全瞎 |
| 6 | **没有对话，每步重建 2 条消息** | `lib/utils/prompt_builder.dart:22-110` | 模型看不到自己的历史动作/参数/返回原文，靠 160/200 字符截断的自然语言摘要重建现场。多步任务必飘 |
| 7 | **无原生 tool calling** | `lib/services/llm_service.dart:289-297`：body 只有 `model/messages/temperature/response_format` | 全靠 5154 字符的中文规则（`app_constants.dart:53-103`）+ 宽容 JSON 解析纠错。现代模型的 function calling 准确率明显更高，还能用 schema 约束参数 |
| 8 | **无上下文管理** | `maxSteps = 15`，无 compaction / elision | 长任务直接撞顶；也没有"用户消息永久保留"的概念 |
| 9 | **缺关键原语** | 无 `find`（按文本找元素）、无 `wait` 到具体元素状态、无 `ask_user`、无 `screenshot`、无 `handle_dialog` | 只能在文本清单里"猜"元素；弹窗（`window.prompt/confirm`）会冻住页面让 agent 死等 |
| 10 | **UI 与执行纠缠** | `browser_page.dart` 2159 行、`agent_bottom_sheet.dart` 2139 行，`setState` + Stream，一次 run 的状态散在 6+ 个字段 | 重执行层收益会被这层吃掉；也没法做流式/结构化步骤卡 |
| 11 | **两套定位机制并存** | agent 用 `data-operon-id`；技能流程用 JS 里的候选链 `buildLocatorForElement / resolveLocatorInternal`（`agent_dom.js:759-1060`） | 同一件事两种实现两倍 bug，长期不可维护 |

### 1.2 为什么"加规则"救不回来

`app_constants.dart` 的系统提示词已经从 1 条规则长到 17 条（"不要机械重复"、"保存草稿不算提交"、"重复内容已拦截"…），`agent_runner.dart` 也加了 loop detector、side-effect ledger、finish verifier、batch limit。

这些都是在**用提示词和事后校验，弥补底层能力的缺口**。方向的代价是：每加一条规则，模型的可用上下文就少一点，泛化差一点，且只在被想到的失败模式上生效。Nanobrowser 的做法相反——**在层里让错误不可能发生**（ref 失效就报 typed error，事件一定是可信的，弹窗一定要人处理），提示词只有 60 行。

---

## 2. Nanobrowser 到底强在哪（机制级对照）

| 维度 | Nanobrowser v0.3 | Operon 现在 | 能搬吗 |
|---|---|---|---|
| 触页通道 | `chrome.debugger` 裸 CDP | 页内 JS `dispatchEvent` | ✅ 换通道即可，见 §3 |
| 元素身份 | CDP `backendDOMNodeId`，注册表在宿主持有；ref 只对"被展示过的那个文档"有效，失效即 typed error | DOM 属性 + JS Map，每步重编号 | ✅ |
| 感知 | Accessibility 树 → outline（role/name/value/states/几何，敏感值打码，frame 缝合，**每处省略都写明**） | CSS 选择器 + innerText | ✅ 且收益最大 |
| 变更感知 | 每次动作返回 receipt：`已派发 / 页面有反应 / 达到预期状态` + diff | `_pageSignature` 粗比 + 700ms 重试一次 | ✅ |
| 输入 | `Input.dispatchMouseEvent` / `dispatchKeyEvent`（trusted） | 合成事件 + `el.click()` + 硬跳 | ✅ 最大单点收益 |
| 循环 | 单循环，6 个 hook，策略全在 hook 里 | `run()` 里 1265 行的 while + 内联策略 | ✅ |
| 提示词 | 60 行稳定前缀（利于缓存）+ 每轮只变 `<browser-state>` | 5154 字符规则 + 每步重建 | ✅ |
| 模型协议 | 原生 tool calling（`ai` SDK + zod schema） | JSON 文本 + 宽容解析 | ✅ |
| 长任务 | compaction + elision，用户消息全文保留 | 无，15 步封顶 | ✅ |
| 人在环 | Ask/Auto + 站点三态 + 支付/密钥永不由 agent 做 | 全局 Safe Mode + 意图分类 | ✅（Operon 的 captcha 接管更完整，保留） |
| 测试 | 499 单测 + 55 checks + 27 scenarios 在**真 Chrome 里**跑 | 253 单测，无真机行为验证 | ✅ 基建可搬 |

**不要照搬的部分**：MV3 service worker 生命周期（App 进程常驻，我们反而简单）、puppeteer frame manager（Android 无等价物，要自己写）、i18n/analytics/商店卡片。

---

## 3. 可行性

### 3.1 三个关键事实（已验证）

1. **Android WebView 内置完整 CDP agent。** `WebView.setWebContentsDebuggingEnabled(true)` 会在**应用进程内**起 DevTools server，监听抽象 unix socket `webview_devtools_remote_<pid>`。它是 Chromium content 层的标准 devtools agent，`Accessibility` / `DOM` / `DOMSnapshot` / `Runtime` / `Page` / `Input` / `Target` 这些**页面级域都在**（content-level protocol）。开源实证：Moch、readest、so7o 的 WebView CDP、mobilebridge 都是这条路。
2. **自己的 App 连自己的 socket 是允许的。** 授权检查走 `SO_PEERCRED`，只放行 root / adb / **同 UID** 进程。我们同进程同 UID → 通过。**不需要 adb、不需要 root、不需要外部端口**（这点和 Nanobrowser "不许外部 CDP"的约束完全一致）。
3. **`Input.dispatchMouseEvent` / `dispatchTouchEvent` 产生 `isTrusted: true` 的事件。** 它不是 JS 合成，是送进 Blink 的输入管线。这是整个重构的收益来源。

### 3.2 唯一需要自研的部分：frame manager

Nanobrowser 用 puppeteer 做帧发现与会话管理。Android 上没有 puppeteer，需要自己实现：

- `Target.setAutoAttach { autoAttach: true, waitForDebuggerOnStart: true, flatten: true }` 拿 OOPIF；
- 自己维护 `frameId → sessionId`，`Page.frameAttached / frameNavigated / frameDetached` 同步；
- 元素命令发到"所属 frame 的 session"。

工作量约 400-600 行 Dart。风险中等，但这是纯粹的机械活，没有未知。

### 3.3 连接拓扑（两条路，推荐 A）

```
A（推荐）：Kotlin 只做转发，层逻辑全在 Dart
  WebView ── abstract unix socket ──> Kotlin LocalSocket relay ──> 127.0.0.1:<port> (WebSocket)
                                                                        │
                                          Dart: package:universal_browser_cdp 或自研 CdpConnection
  优点：层可用纯 Dart 写，能 unit test（喂录制的 CDP payload），迭代快，可复用现成包
  代价：多一跳 localhost（AX 树几百 KB，实测应在毫秒级）

B：层逻辑也在 Kotlin，Dart 只收 typed JSON
  优点：少一次序列化，大页面 AX 抓取快
  代价：核心逻辑落在 Kotlin，单测/迭代成本翻倍
```

`pub.dev/packages/universal_browser_cdp` 已经是纯 Dart 的 CDP 客户端，含 AX 快照、hit-checked `Input.dispatchMouseEvent`、截图、auto-wait（attached→visible→stable→hittable）、flat 多 tab session、`FakeCdpServer` 测试替身。**建议 P1 先拿它当加速器**，把不可控的部分（连接、AX 解析、命中检测）外包，我们只写协议适配和 ref 注册表。

### 3.4 P0 Spike 验收清单（跑不通就不动工）

| # | 验证项 | 通过标准 |
|---|---|---|
| 1 | 拿到 abstract socket + `/json/list` | 返回当前 WebView 的 target |
| 2 | WebSocket 升级 + `Runtime.evaluate` | 返回 `document.title` |
| 3 | `Accessibility.getFullAXTree` | 能拿到某个 button 的 `backendDOMNodeId` + role + name |
| 4 | **`Input.dispatchMouseEvent` 点 React 按钮** | 页面 state 真的变；页面内打点确认 `event.isTrusted === true` |
| 5 | `Page.captureScreenshot` | 出 PNG，可传给视觉模型 |
| 6 | `Target.setAutoAttach` | 能拿到子 frame 的 session 并在其中执行命令 |
| 7 | 稳定性 | 连续 50 步不崩；单步 observe p95 < 400ms（中端机） |
| 8 | 降级路径 | 若 `Input` 域在某些 WebView 版本不可用 → 用 AccessibilityService `dispatchGesture` 按坐标注入（同样 trusted），层次设计不变 |

---

## 4. 目标架构

### 4.1 分层

```
lib/
├── control/                    # 【新】确定性层。不 import 模型、不 import Flutter UI
│   ├── control.dart            # 唯一对外入口
│   ├── protocol/               # 工具目录、参数 zod-like schema、typed results、错误码
│   ├── transport/              # CdpConnection / CdpSession / frame registry / relay 客户端
│   ├── perception/             # ax 树 → outline、几何、masking、read(内容分块)、diff
│   ├── interaction/            # hit-test、指针/键盘派发、fill、select、upload、dialog
│   └── refs/                   # ref 注册表（fail-closed）
├── agent/                      # 【重写】单循环
│   ├── loop.dart               # 一次模型调用 + 一批工具
│   ├── hooks.dart              # 6 个策略钩子（预算/压缩/守卫/权限/接管/收尾）
│   ├── tools.dart              # 层的工具 → 模型 tool schema
│   ├── guards.dart             # 重复、无效果、连续错误
│   └── context/                # compaction、elision、page-content 边界
├── runtime/                    # 【新】相当于 nanobrowser 的 src/extension
│   ├── run_manager.dart        # 一次 run 的归属、并发、取消
│   ├── permissions.dart        # Ask/Auto + 站点三态
│   ├── tab_scope.dart          # run 绑定到哪些标签
│   └── notify.dart / download.dart
└── ui/                         # 【拆】只消费 typed events
    ├── panel/                  # 聊天流 + 步骤卡（带 receipt/diff/截图缩略图）
    └── browser/                # 地址栏、标签、菜单（从 browser_page.dart 拆出来）

android/app/src/main/kotlin/.../cdp/
└── DevToolsRelay.kt            # LocalSocket ⇄ localhost，WebView 生命周期绑定
```

### 4.2 层的不变量（Nanobrowser 11 条 → 移动端 12 条）

直接沿用，加一条 Operon 特有的：

1. 一个身份：动作只作用于被展示过的那个节点（backend node id）。
2. ref 保守失败：ref 只对它被看到时的那个文档有效，否则返回 typed error，不猜。
3. 重试发生在派发之前：一旦发出输入事件，层不再自己补发。
4. 不做隐藏替换：换节点或换机制必须按规则在派发前决定，并写进 receipt。
5. 三种结果分开报：已派发 / 页面有反应 / 达到预期状态。
6. 观察只读。
7. 降级要吵：截断、部分抓取、打码，都在结果里写明。
8. 一切有预算：每条命令、每次等待、每个列表都有上限。唯一的无时钟等待是"等人处理"（验证码/支付），它仍然会被 Stop、标签关闭、会话结束终止。
9. 状态可丢弃：WebView 重建、调试器断开、导航，都干净失效。
10. 层里没有模型。
11. 有后果的动作要人批（默认），agent 无法关闭。
12. **【Operon 新增】手势可见**：Ghost Cursor / 触控波纹的坐标由层在派发前决定，动画时长计入该动作的耗时，不能为了好看在派发后再补画。

### 4.3 工具面（对齐 Nanobrowser 17 个 + Operon 现有的）

| 组 | 工具 | 说明 |
|---|---|---|
| 读 | `snapshot` `find` `read` `screenshot` | snapshot 返回 outline + ref + 省略说明；find 按文本/role 找；read 读内容块 |
| 写 | `click` `set` `fill_form` `type` `press` `hover` `scroll` `upload` | 全部 trusted 派发；`handle_dialog` 处理 `window.prompt/confirm` |
| 导航 | `navigate` `tabs` `wait` | `wait` 支持"等到元素可见/隐藏/附件" |
| 工作 | `done` `ask_user` | `done` 带 `outcome: success/partial/failed`；`ask_user` 交接给用户 |
| 保留 | `ai.generate` `ai.extract` `notify` | Operon 已有，属于 agent 自有的工具，不走层 |

**永不提供**：`eval`（页面任意脚本）、`devtools`、坐标与 selector。跟 Nanobrowser 一致——这是防注入的主要手段。

### 4.4 提示词

- 稳定前缀约 60-80 行：身份、"如何工作"、page-content 边界契约、`done` 语义。
- 每轮只变 `<browser-state>`（URL/标题/标签/滚动位置）+ 本次 observation。
- **不再用规则列表兜底失败模式**：重复点击由 guards 拦、草稿按钮由层的分类拦、截断由层的"写明省略"表达。

### 4.5 上下文

- 真对话：`assistant(tool_calls)` + `tool(result)` 成对保留，模型能看到自己的历史。
- 触发阈值：估算 token 过 window 的 60% → 老 page payload 换成 stub（elision）；过硬上限 → 换更狠的压缩；**用户消息永不压缩**。
- `maxSteps` 从 15 提到 60（配预算而非步数封顶）。

---

## 5. 分阶段计划

每期都能独立上线，用 feature flag 与旧引擎并存。

| 期 | 内容 | 产出验收 | 人天 |
|---|---|---|---|
| **P0** | CDP Spike（§3.4 八项） | go/no-go 报告；一个能点 React 按钮的最小 demo | 4-6 |
| **P1** | 层骨架：relay + connection + session + ref 注册表 + `snapshot/read/click/type/scroll/navigate/wait` + receipt | 12 个 fixture 场景里，读+点 6 个通过；ref 失效返回 typed error | 8-12 |
| **P2** | 层补全：AX outline 完整化、masking、diff、auto-wait（attached→visible→stable→hittable）、`find/screenshot/tabs/upload/handle_dialog`、iframe 缝合 | 全部 fixture 场景通过；敏感字段打码有测试 | 8-12 |
| **P3** | agent 重写：tool calling + 单循环 + 6 hooks + guards + `done/ask_user` + compaction | 20 个真实任务回归集，完成率对比旧引擎 | 8-12 |
| **P4** | 权限与接管：Ask/Auto + 站点三态 + 支付/密钥/验证码 handoff（复用现有 captcha 检测与通知） | 支付/密码场景一律交接；Auto 模式下写操作不问 | 4-6 |
| **P5** | UI 重做：聊天流 + 步骤卡（receipt/diff/截图）+ 拆 `browser_page.dart` | 面板文件 < 400 行/个；无 `setState` 穿透到执行层 | 8-12 |
| **P6** | 技能/宏迁移（可延后、可砍）：录制 = 记录 ref 解析规则 + 输入序列；重放走层 | 旧技能包仍能导入；宏重放 1-2 秒完成 | 6-10 |

合计 **46-70 人天**（单人 2.5-3.5 个月；P5 可与 P2/P3 并行）。

### 迁移策略：旁路共存

1. **不删任何东西就开工**。`agent_dom.js` 继续服务旧引擎。
2. 引入接口 `AgentEngine`（`run(goal) → Stream<AgentEvent>`），旧 `AgentRunner` 与新 `AgentLoop` 各实现一份。
3. 设置里加隐藏开关：`引擎 = 经典 / 新版`，默认经典；内部人先切。
4. P3 完成、回归集达标后默认切新版；P5 完成后再删旧代码。

### 删除清单（P5 之后）

- `assets/js/agent_dom.js` 中：`extractPrunedDOM`、`executeAction`、`buildLocator*`、`resolveLocator*`、`extractOutsideActions`、badge/radar/macro 页面状态 → 保留 Ghost Cursor 动画（改成由层驱动）。
- `lib/services/agent_runner.dart`（1553）、`prompt_builder.dart`、`tool_registry.dart` 的 `page.*` 实现、`llm_service.dart` 的 JSON 模式协商。
- `lib/config/app_constants.dart` 的 5154 字符系统提示词 → 换成 80 行新提示词。

---

## 6. 关键设计决策

| 决策 | 选项 | 建议 |
|---|---|---|
| 平台路径 | (a) Flutter UI + Kotlin relay + Dart 层 (b) 全 Kotlin 重写 | **(a)**。UI 资产别扔；层用 Dart 好测好改 |
| 层逻辑放哪 | (a) Dart (b) Kotlin | **(a)**，除非 spike 显示 AX 抓取成为瓶颈 |
| 输入通道降级链 | CDP Input → accessibility gesture → 失败 | 三条都 trusted。降级必须写进 receipt（不变量 4） |
| 是否复用 `universal_browser_cdp` | (a) 复用它 (b) 自研 | **(a) 起步**，把 ref 注册表和协议适配握在自己手里；它不满足的部分再自研 |
| 技能/宏 | (a) P6 迁移 (b) 1.0 砍掉 | 先 (a) 排期，若 P3 拖期则 (b)。它们是 Operon 相对 Nanobrowser 的差异化，别轻易丢 |
| release 是否开调试口 | 必开 | 同 UID socket 外部不可达，属可接受；在设置 → 关于里明说 |

---

## 7. 风险与缓解

| 风险 | 概率 | 缓解 |
|---|---|---|
| 某些 WebView 版本 `Input` 域不可用 | 中 | 降级到 accessibility `dispatchGesture`（坐标注入，trusted）。P0 就要在两个 API 级别上测 |
| WebView CDP 是私有接口，未来可能变 | 低 | 版本容错 + 能力探测（启动时探 `Input.dispatchMouseEvent` 是否 200） |
| AX 树在大页面上几百 KB，传输/解析慢 | 中 | 只抓 `interactive` 模式的子树 + 几何按需；必要时切到 Kotlin 侧解析 |
| OOPIF frame manager 自研出 bug | 中 | P2 先只支持主 frame + 同进程 iframe；OOPIF 单独一个 fixture 场景兜 |
| 真实站点风控识别自动化 | 中 | 保留 Operon 现有的 stealth + captcha 接管；CDP 会话不挂 `Emulation.setAutomationOverride`，UA/指纹维持现状 |
| 重写期间旧版继续迭代导致分叉 | 中 | 分支隔离 + feature flag；P1-P2 期间冻结 `agent_dom.js` |
| 你一个人做，周期长 | 高 | P1/P3 是价值最高的两期，先做这两期就能体感变好；P5/P6 可延后 |

---

## 8. 回归与验收基建（照抄 Nanobrowser 的 autorun 思路）

1. `tool/fixtures/server.dart`（或 node 脚本）：静态测试页 + **假 OpenAI 兼容模型**（剧本化返回工具调用）。
2. 12 个场景 fixture：受控 React 输入、下拉、文件上传、iframe 支付、隐藏/禁用元素、分页列表、无限滚动、`window.confirm` 弹窗、SPA 路由、晚加载元素、敏感字段打码、ref 失效。
3. 断言口径就是三条 receipt：`dispatched` / `pageReacted` / `expectedStateReached`，外加 `isTrusted === true`。
4. 跑法：`flutter test`（层的纯逻辑 + 录制的 CDP payload）+ 一个 Android instrumentation runner（真机/模拟器跑场景）。
5. CI 只跑前三项和 `flutter analyze`；真机场景手动跑，发版前必跑（和 Nanobrowser 一致）。

---

## 9. 不做什么（scope fence）

- 不做 iOS / Firefox / 其它 Chromium。
- 不做 MCP bridge。
- 不做 planner + navigator 多 agent。
- 不开放除本进程 socket 之外的任何 CDP 入口（不许 adb forward 成为依赖）。
- 1.0 不做站点笔记、长期记忆、定时任务、多 agent 协作。
- 层里永远不放模型调用。

---

## 10. 下一步（P0 具体任务）

1. `android/app/src/main/kotlin/.../DevToolsRelay.kt`：`LocalSocket("webview_devtools_remote_<pid>")` → 本地 WebSocket 服务；`setWebContentsDebuggingEnabled(true)` 挂在 WebView 创建处。
2. Dart 侧：用一个临时页面把 `/json/list`、`Runtime.evaluate`、`Accessibility.getFullAXTree`、`Input.dispatchMouseEvent`、`Page.captureScreenshot` 依次打通，打印耗时。
3. 造一个"React 受控输入 + 受控按钮"的本地页，验证 old vs new：旧 JS 合成 vs CDP 派发，对比 `isTrusted` 与 state 是否更新。
4. 结论写回本文档 §3.4 表。

---

## 11. 进度：P0 + P1 骨架（已提交代码）

### 11.1 已完成

```
android/app/src/main/kotlin/com/operon/browser/
├── MainActivity.kt                  # onCreate 里先开调试口，再挂 operon/cdp 通道
└── cdp/
    ├── DevToolsRelay.kt             # LocalSocket("webview_devtools_remote_<pid>") ⇄ 127.0.0.1 端口
    └── CdpChannel.kt                # enable / start / stop / status / findSocket

lib/control/                         # 3400 行，纯 Dart，无 Flutter 依赖（除 relay 通道）
├── control.dart                     # 工具目录 + execute(tool, args) → ToolResult
├── session.dart                     # 附加、观察、动作、receipt、settle
├── refs.dart                        # fail-closed 的 ref 注册表
├── diagnostics.dart                 # 自检（7 项只读 + 真实输入 A/B）
├── protocol/{errors,results}.dart    # 错误码 / Receipt / OutlineLine
├── transport/{relay,endpoint,websocket,cdp_connection}.dart
├── perception/{ax,outline,diff}.dart
└── interaction/{geometry,input}.dart

lib/views/settings/control_diagnostics_page.dart   # 关于 → 控制层自检
test/control_{refs,outline,diff,transport}_test.dart  # 26 个用例
```

关键点，逐条对应本方案的不变量：

- **真实输入**：`Input.dispatchTouchEvent` / `dispatchMouseEvent` / `dispatchKeyEvent`，不是 `dispatchEvent(new MouseEvent(...))`。
- **ref fail-closed**：ref 绑 `backendDOMNodeId` + 文档代次；跨文档、未被展示、节点被替换，一律 typed error，绝不回退到"按属性名找一个"。
- **三结果分开报**：`Receipt{delivery, pageReacted, expectedStateReached, changes, urlBefore/After}`。
- **降级要吵**：Outline 带 `omitted`（截断、不可寻址控件、iframe），超出预算会明说。
- **ref 编号单调递增**（不因导航重置），避免旧 ref 撞上新节点。
- **手势可见**：`onGesture(x, y, label)` 在派发前回调，坐标由层决定。
- **掩码**：密码/验证码/卡号类字段的 value 一律 `•••`。
- **chunked 响应**：`/json/list` 用 chunked 传输，已按字节解码。

### 11.2 已验证（开发机，Flutter 3.35.5）

- `flutter analyze --no-pub`：只剩 2 个**既有**错误（`skills_page.dart` 的 `onReorder`/`onReorderItem` 是本机 SDK 比项目目标 3.47 旧所致，与本改动无关）。
- `flutter test --no-pub`：276 通过 / 2 失败，两个失败同上（`settings_page_test`、`skills_page_test` 因该 API 无法编译）。
- 新增 26 个用例覆盖：ref 失效语义、outline 折叠/打码/截断/iframe、diff 上限、**真实 TCP + WebSocket 升级 + JSON-RPC 关联 + 出错映射 + 超时**（假 DevTools 服务器跑在 host 上，不是 mock）。

### 11.3 还没验证：Kotlin 与真机链路

本机没有 Android SDK 构建缓存（无 gradle 发行版、无 `gradlew`），所以 **`DevToolsRelay.kt` / `CdpChannel.kt` 未编译验证**，只做了逐行复核。请按下面步骤在真机上确认。

### 11.4 设备上的验证步骤

1. `flutter build apk --debug`（或 Android Studio 直接跑）。首次启动后打开任意网页。
2. 设置 → 关于 → **控制层自检** → **运行自检（只读）**。期望：

| 检查项 | 期望 |
|---|---|
| 调试通道 | 本地端口 > 0，socket 形如 `webview_devtools_remote_<pid>` |
| 页面发现 | ≥1 个页面，URL 与当前标签一致 |
| 运行时通道 | `document.readyState` 有返回值 |
| 无障碍树 | 可操作元素 > 0（真实站点通常几十到上百） |
| 几何与命中 | ≥1 个四边形 |
| 输入域 | 无副作用通过 |
| 截图 | PNG base64 有大小 |
| 子 frame | 无 iframe 时显示 0 |

3. 在**空白页或测试页**上点 **测试真实输入**。期望：`CDP 派发的事件 isTrusted=true；页面脚本合成的是 false`。这一项通过，重写的核心收益就成立。
4. 若「调试通道」失败：多为 `/proc/net/unix` 里还没有 socket → 先打开一个网页再试；仍失败则为 WebView 版本过旧，需更新 Android System WebView。

### 11.5 P1 有意没做的部分

- 工具：`find` / `screenshot` / `upload` / `tabs` 尚未暴露（层的 `Page.captureScreenshot` 已在自检里验通）。
- 没接 agent：`Control.execute` 还没有被任何界面调用；旧 `AgentRunner` 仍在跑。
- 没动 UI：`browser_page.dart` / `agent_bottom_sheet.dart` 原样保留（P5）。
- 没动技能/宏：按决策，1.0 直接移除，待新链路稳定后一并删除。

### 11.6 下一步（P2）

1. 真机跑 11.4，把结果写回 §3.4。
2. 补 `find`（按文本/role 找）、`screenshot` 工具、`wait` 的元素状态。
3. actionability 等待：attached → visible → stable → hittable（目前已做 hittable 检查，缺 stable 轮询）。
4. OOPIF 单独 fixture 场景（隐藏支付 frame）。
5. fixtures：受控 React 输入页 + 12 场景集，跑法接到 `flutter test` 与一个 instrumentation runner。

---

## 12. 进度：P2 + 旧代码删除

### 12.1 P2（层能力）

| 新增 | 说明 |
|---|---|
| `find` 工具 | 按名称/role 在**新快照**里找控件，返回可用 ref。80 个相似行不再靠猜。`matchEntries` 是纯函数，7 个用例 |
| actionability | 派发前依次验证四件事：attached → 有面积 → 两次读到的 box 一致（未在动画/自动滚动中）→ 该点未被遮挡。1800ms 预算内轮询，失败时报**没通过的那一项**，且一个事件都不派发 |
| `disabled` / `notEditable` 拦截 | 禁用按钮和不可输入节点在派发前被拒，不再"点了没反应" |
| `notStable` 错误码 | 元素在移动时明确告知，而不是超时 |
| `screenshot` 工具 | PNG（可选整页），给视觉模型与步骤卡 |
| ref 携带 `disabled` / `editable` | 同一节点重复出现时刷新状态，ref 不变 |

### 12.2 删除（已定砍掉的技能/宏子系统）

`lib` 从 **29682 行降到 21106 行**（-8576）。删除 33 个文件 + 18 个测试文件。

- 模型/服务：`skill.dart`、`skill_run.dart`、`macro_workflow.dart`、`skill_service`、`skill_runner`、`skill_validator`(1062)、`skill_authoring_service`、`skill_creator_service`、`skill_from_macro`、`skill_from_task`、`skill_inputs`、`skill_package_codec`(620)、`skill_package_store`、`skill_precheck_service`、`skill_recording_session`、`skill_repair_service`、`macro_service`、`macro_precondition`
- 配置/工具：3 个 `skill_*_prompt`、`skill_execution`、`skill_placeholder_inputs`、`skill_template`
- 界面：`skills_page`、`skill_editor_page`、`skill_runs_page`、`skill_ai_create_sheet`、`skill_recording_sheet`、`skill_run_sheet`、`skill_run_timeline`、`macro_dialog`
- 连带清理：`AgentState.recordedMacroSteps`、`AgentTaskRecord.recordedMacroSteps`、`StorageService` 的技能运行历史、`ToolCatalog` 的 `macro.run`、`RunKind` 收敛为 `agent`、`AgentRunner.run()` 的 `policy` / `recorder` 参数、`RunBudget.fromPolicy`、设置页的「技能」「快捷宏工作流」两项、agent 面板的「存为技能 / 存为宏 / 管理技能」入口与技能条、任务历史页的「存为技能」。

### 12.3 行为变化（有意为之）

- 内容去重（`uniqueContent`）与目标去重（`uniqueTarget`）原先由技能策略开关，现在**始终生效**：它们本来就是安全网。
- 写操作确认只看全局 Safe Mode 与站点允许列表，不再读策略里的 `confirmWrites`。
- 任务历史里「存为技能」消失；`AgentTaskRecord` 读取旧记录时忽略已不存在的字段。
- **没删**：`agent_runner.dart`、`tool_registry.dart`、`agent_dom.js` —— 它们是当前唯一能用的 agent。删了 App 就没有 agent 了，要等 P3 新引擎接上、P5 面板重写后一并删除（§5 删除清单不变）。

### 12.4 状态

- `flutter analyze --no-pub`：**No issues found**（原先那 2 个 `onReorder` 错误随 `skills_page.dart` 一起消失）。
- `flutter test --no-pub`：**164 通过 / 0 失败**（26 个测试文件）。
- 仍需真机确认：Kotlin 编译、§11.4 的自检 8 项、`isTrusted` A/B。

---

## 13. 进度：P3（新 agent 循环）

### 13.1 新增

```
lib/agent/                  ~1 800 行
├── loop.dart       单循环，6 个策略钩子
├── runner.dart     接 UI：AgentState、暂停/停止/确认、attach 与回退
├── ports.dart      LlmPort / ControlPort / HostPort（循环不依赖具体实现）
├── tools.dart      工具 schema（含 done）、结果渲染、page-content 包裹
├── guards.dart     重复 / 无效果 / 连续错误
├── context.dart    估算、省略、丢整轮
├── permission.dart 写入分类（提交 / 删除支付 / 草稿）
└── prompt.dart     约 1 400 字符的稳定系统提示词

lib/services/llm_tools.dart   原生 tool calling（tools + tool_choice:auto）
lib/services/llm_service.dart +sendToolTurn()（复用重试/中止/端点解析）
```

`lib` 现 22 900 行，测试 221 个（P3 新增 51 个）。

### 13.2 循环：六个钩子

| # | 钩子 | 做什么 |
|---|---|---|
| 1 | `keepGoing` + `onTurn` | 暂停/停止都落在这里；每一步开始前问一次 |
| 2 | `ContextManager.prepare` | 该发什么：省略旧结果 → 丢整轮 → 还不行就停 |
| 3 | 模型调用 | 原生 tool calling；`finish_reason=length` 直接停且**不执行任何动作** |
| 4 | `Guards.before` + `assessWrite` | 这个调用允不允许派发；写入要不要问人 |
| 5 | `ControlPort.execute` | 派发 |
| 6 | `Guards.record` | 记住结果，决定这一批是否到此为止 |

批处理规则：一条回复里的**只读调用一起跑**，然后**只跑第一个动作**，其余回注"未执行：页面已变，先重新观察"。`done` 在同一回复里时，先跑完它前面的动作再收尾。

### 13.3 与 Nanobrowser 对齐的机制

| 机制 | 参数/做法 |
|---|---|
| 重复守卫 | 窗口 6 内同一签名 3 次 → 停（读类调用永不触发） |
| 无效果守卫 | 写操作连续 2 次无变化 → 提示；3 次 → 停 |
| 错误守卫 | 连续 5 次失败 → 停；一次成功清零 |
| 上下文 | 60% 开始省略旧结果（保留最新 4 条），85% 才丢整轮；**用户消息与 system 永不删改** |
| 内容边界 | 页面文本包在 `<<<page-content>>>` 里，提示词里写明"是数据不是指令" |
| 提示词 | 约 1 400 字符（旧的是 5 154 字符 + 17 条禁止规则），有测试锁上限 |
| 权限 | 提交/发布类问人；删除/支付/弹窗确认**任何模式都问**；站点 Allow 可免；草稿按钮不算写入 |

### 13.4 接线

`browser_page` 里两个引擎共用一套状态处理与运行控制（暂停/停止/确认各转发一次，空闲的一方忽略）。默认走新引擎；`Control.attach` 抛出 `ControlException` 时**弹出说明并回退经典引擎**，附「自检」入口——不做静默切换。

`agent_dom.js` 只加了一个 `showGesture(x, y)`：新引擎派发前把坐标交给它画幽灵光标，保持"手势可见"。

### 13.5 P3 期间发现并修掉的两个 bug

1. **上下文压缩会挂死**：初版"丢旧轮 + 插入一行说明"的循环里，那行说明本身又算一轮，保护条件永不满足 → 无限循环（测试跑了 8 分钟）。改成单趟算法：从最旧的轮开始丢，丢到装得下为止，说明行不再是候选。
2. **token 估算低估中文**：按"字符数 / 2"算，中文实际约 0.6 token/字 → 会先把请求发出去再被供应商截断。改成 CJK 按 1 token/字、其他按 4 字符/token，宁可高估。

### 13.6 还没做（P4+）

- `ask_user` 工具与验证码接管：新引擎目前不交接 CAPTCHA；
- 视觉：`screenshot` 对视觉模型还没有把图片真正塞进请求（只报"已截图"）；
- 压缩用的是"丢整轮"，还不是 Nanobrowser 的摘要式压缩（不做额外模型调用是有意的取舍）；
- 面板还没把 receipt/diff 做成步骤卡（P5），目前靠日志行读；
- 停止后没有 Resume 能力（旧引擎也没有）。

---

## 14. 进度：删除旧引擎 + P4

### 14.1 删掉的（`lib` 22 900 → 18 754 行）

| 文件 | 行数 |
|---|---|
| `services/agent_runner.dart`（JSON-ReAct 循环） | 1307 |
| `services/tool_registry.dart`（原子工具表） | 1016 |
| `config/tool_catalog.dart` + `models/tool_descriptor.dart`（旧工具目录/结果类型） | 748 |
| `models/agent_action.dart` + `agent_action_result.dart` | 395 |
| `services/execution_guard.dart` · `side_effect_ledger.dart` · `finish_verifier.dart` · `run_budget.dart` · `action_loop_detector.dart` | 647 |
| `utils/prompt_builder.dart` · `agent_text.dart` · `json_parser.dart` · `extracted_data.dart` · `models/page_signature.dart` | ~350 |
| 旧引擎的 13 个测试文件 | ~1 400 |
| `assets/js/agent_dom.js` | 2797 → **423** |

`agent_dom.js` 只留四件事：指纹伪装（浏览器本身要的）、手势覆盖层（`showGesture`）、阅读模式（`cleanPageMode` / `extractReadableContent`）、划词信息。DOM 感知、动作执行、定位器生成、宏选择器、验证码探测、徽标全部移除——那些现在要么属于控制层（CDP），要么属于新的权限模型。

连带清掉的 UI 耦合：`AgentState.currentAction`、`agentActionLabel`、定位器拾取器（`_pickLocator` + 底栏入口 + `onPickLocator`）、旧验证码自检（`_confirmCaptchaSolved`）、经典引擎回退路径与它的双份运行控制。

`WebViewControllerWrapper` 从 468 行降到 170：只保留注入脚本、手势、阅读模式、划词、`getUrl/getTitle/reload`。`evaluateJavascript` 只服务阅读模式与划词。

**「测试连接」改成了工具调用探测**：旧版让模型输出一个 JSON 动作，只能证明 key 有效；新版给模型一个 `ping` 工具，看它是否真的发起工具调用——那才是智能体需要的能力。没有工具调用时会明确提示换模型。

### 14.2 P4

| 能力 | 做法 |
|---|---|
| **验证码交接** | 检测搬进层：`control/perception/captcha.dart` 从无障碍树识别 Turnstile / reCAPTCHA / Arkose / Geetest / 滑块 / 通用人机验证。判定只看 dialog / iframe / checkbox / image 这类"角色可信"节点，**登录表单里的「验证码」输入框不算**（有测试锁住）。命中即交给用户，`AgentStatus.waitingCaptcha` + 系统通知 + 等待；用户取消则停止本次运行 |
| **ask_user** | 新工具。问题进 `HostPort.askPerson`，回答作为该次调用的 tool 结果回给模型；用户取消则停止。面板里是真对话框（输入框 + 取消/回答）。`done` 与 `ask_user` 都会终止本条回复的后续调用 |
| **视觉** | `screenshot` 的结果若带图且模型能看图，就在 tool 消息之后补一条 **user** 消息，内容是 `image_url`（data URI）——OpenAI 兼容端点上 tool 消息不能带图，这是各家都接受的形式。模型能不能看图由 `modelSupportsVision(model)` 猜（gpt-4o/4.1/5、claude-3/4、gemini、*-vl、glm-4v…） |
| **结构化结果** | `done` 增加可选 `data`：抓到的东西放进 `AgentState.extractedData`，面板原有的结果卡与「复制」重新可达 |

### 14.3 状态

- `flutter analyze --no-pub`：**No issues found**
- `flutter test --no-pub`：**173 通过 / 0 失败**（25 个测试文件）
- 相对起点：`lib` 29 682 → **18 754 行**；`assets/js/agent_dom.js` 2 797 → **423 行**

### 14.4 下一步（P5）

面板重写：把 receipt / diff / 截图缩略图做成步骤卡，把「AI 思路」与日志合成一条时间线，把 2 000 行的 `browser_page` 拆成 browser / panel 两部分。之后再做 fixtures 场景集（§8）与真机回归。

---

## 15. 页内脚本的边界：手势用 Flutter，阅读模式用 JS

### 15.1 判定规则

一条线把页内脚本该做的事划开：**要么在改页面，要么在画东西。**

| | 用什么 | 为什么 |
|---|---|---|
| 手势光标 / 触控波纹 | **Flutter 覆盖层** | 它是绘制，不是操作。层已经在派发前算好视口坐标，Flutter 直接画。往页面里插节点有三个代价：① 节点本身是可检测的自动化信号；② 污染 `document.querySelectorAll('*')` 和 DOM，而 agent 本来就在读这个页面；③ 动画质量受页面合成器影响 |
| 阅读模式（清横幅、去遮罩、展开正文） | **页内 JS** | 必须 `el.remove()`、改 `maxHeight`、跳过 iframe——Flutter 做不到，只能通过 `Runtime.evaluate` 把这些代码换个地方写，没有收益 |
| 页面摘要（正文+元数据） | **页内 JS** | 同上：要读 `innerText`、按候选容器比长度 |
| 划词信息 | **页内 JS** | `window.getSelection()` 与 `Range.getBoundingClientRect()` 只在页内有 |
| 指纹伪装 | **页内 JS** | 必须在页面脚本运行前改写 `navigator.webdriver` 等 |

### 15.2 落地

`assets/js/agent_dom.js` → **`assets/js/page_helpers.js`**，2797 → **206 行**，只留指纹伪装 + 三个阅读模式函数。手势相关的 ~120 行（`ensureGhostCursor` / `moveGhostCursor` / `playTouchRipple` / 注入 CSS / `z-index: 2147483647`）全部删除。

新增 `lib/views/widgets/gesture_overlay.dart`（约 230 行）：光标 22px 圆点 + 蓝色辉光 + 触控波纹，滑动到位后停住，随标签淡出；`IgnorePointer` 保证永不吞触摸。坐标换算用 `InAppWebViewController.getZoomScale()`：CSS 像素 × 页面缩放 = Flutter 逻辑像素（缩放为 1 时两者相等，捏合缩放时同时生效）。它叠在 WebView 之上、浏览器控件之下。

### 15.3 期间修掉的一个真 bug

手势 widget 的 `AnimationController` 原本写成 `late final ... = AnimationController(...)`。如果一次动画都没跑过，`dispose()` 里第一次访问它会在已失活的 element 上注册 Ticker 并抛异常（"Looking up a deactivated widget's ancestor is unsafe"）。改为在 `initState` 里创建。这个 bug 只在"打开面板但从未触发手势"时出现，手测很容易漏，是 widget 测试抓到的。

### 15.4 状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**176 通过 / 0 失败**
- `assets/js/page_helpers.js`：206 行（起点 2797 行）

---

## 16. 阅读 / 划词 / 摘要：三个开关

### 16.1 做法

设置 → 浏览与隐私保护 → 新增「阅读与摘要」分组，三个独立开关，默认全开：

| 开关 | 关闭后 |
|---|---|
| 纯净阅读 | 菜单里不再出现该入口；页面加载时的自动清理也跳过 |
| 划词操作 | 选中文字后**不再调用** `getSelectedTextInfo`（省掉一次页内往返），也不弹任何面板 |
| 页面总结 | 菜单与悬浮球的快捷入口都消失；`_quickSummarize` 里还有兜底提示 + 「去设置」直达 |

实现要点：三个偏好独立存 `SharedPreferences`（`pref_reading_mode` / `pref_selection_menu` / `pref_page_summary`），读取在 `StorageService`；入口的**隐藏**和行为的**短路**都做——只藏入口不短路会在别的路径上继续跑，只短路不藏入口会让用户点到一个没反应的东西。

`StorageService` 增加 `resetForTest()`，让测试能在同一进程里模拟两次「应用启动」。

### 16.2 顺手修掉一个真 bug（既有的）

给设置页写 widget 测试时在 400dp 宽度下溢出 103px：**「常用设备预设」下拉框没有 `isExpanded: true`**，选中项 `Android Chrome (Pixel 8) [推荐]` 的固有宽度撑破了 360–412 dp 的手机屏。这是这次改动之前就存在的问题（该页面此前没有任何 widget 测试），已修。

### 16.3 状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**180 通过 / 0 失败**（新增 4 个：三个开关的默认值/独立持久化/重启后读回，以及设置页三项渲染与写穿）

---

## 17. 不需要 Kotlin：控制层改成纯 Dart

### 17.1 结论

原来的判断（"Android 的 DevTools 只有抽象 unix socket，Dart 连不了，所以要一段 Kotlin 转发"）**是错的**。

Dart 从 **2.9.0（2020-08-05）** 起支持抽象 unix socket：

> Abstract Unix Domain Socket is supported on Linux/Android now. Using an `InternetAddress` with `address` starting with `'@'` and type being `InternetAddressType.Unix` will create an abstract Unix Domain Socket.

而 WebView 的服务端正好叫 `@webview_devtools_remote_<pid>`。所以那一层转发可以整段删掉。

### 17.2 删掉的

| 删除 | 行数 |
|---|---|
| `android/.../cdp/DevToolsRelay.kt`（LocalSocket ⇄ TCP 字节转发、线程泵） | 190 |
| `android/.../cdp/CdpChannel.kt`（MethodChannel） | 43 |
| `lib/control/transport/relay.dart`（平台通道客户端） | 117 |
| `MainActivity` 的通道注册与 `onCreate` 覆写 | 12 |
| **合计** | **362** |

新增 `lib/control/transport/devtools_socket.dart`（约 180 行）：解析地址（优先 `@webview_devtools_remote_<pid>`，连不上再扫 `/proc/net/unix`）、`Socket.connect(InternetAddress('@…', type: unix), 0)`、HTTP 读取与 chunked 解码。

### 17.3 收益

1. **「Kotlin 从未编译过」这个最大风险消失了**——现在控制层一行原生代码都没有，全部是 Dart，本机 `flutter analyze` + `flutter test` 就能验证到。
2. 少一个平台通道：没有 `MissingPluginException` 分支，没有 `MethodChannel` 在测试里打桩。
3. 传输层更薄：不再有"本地端口 ↔ 抽象 socket"这一段字节搬运，也不再有它自己的线程和缓冲区。

### 17.4 现在的形态

```
WebView.setWebContentsDebuggingEnabled(true)   ← Dart（main.dart 里，runApp 之前）
        │
        ▼
@webview_devtools_remote_<pid>                 ← 抽象 unix socket（同进程、同 UID）
        │  Socket.connect(InternetAddress('@…', type: unix), 0)
        ▼
GET /json/list  →  WS 升级  →  JSON-RPC        ← 全部在 Dart 里
```

`flutter_inappwebview` 的 `callDevToolsProtocolMethod` 帮不上忙：它在 Android 侧没有实现，只在 Windows/WebView2 上有。

### 17.5 验证状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**187 通过 / 0 失败**（新增 7 个：地址格式、chunked 解码、`httpGetOverSocket` 的成功与失败、连不上时报出 socket 名）
- 仍待真机确认的只剩一条：`Socket.connect` 到抽象 socket 在具体设备/WebView 版本上是否成立。失败时会抛出带 socket 名的 `ControlException`，自检页第一项就能看到。

---

## 18. P5：步骤卡片、合成的思路与日志、假 DevTools 服务端

### 18.1 面板：一次调用就是一张卡

以前失败会追加第二行日志，用户得用眼睛把「动作」和「结果」配起来；成功的调用则只有一行描述，回执根本不到面板。

现在 `AgentLogItem` 带 `kind` 和 `evidence`：动作开始时建行，结果回来时**原地补齐**（`completeWith`），保持原始时间戳和动作自己的措辞。卡片折叠时是一行（动作 + 三个结论 + 耗时），展开后是 URL 变化、增删的页面行、备注、截图。

「派发 / 页面反应 / 是否达到预期」三个结论永远是三个独立的 chip，不合并成一个勾：点到了、页面动了、做成了是三件不同的事，合并之后就看不到真正出错的那一步。

`LogKind.thought` 让模型的思考进入同一条时间线（以前它只在顶部的「AI 思路」卡里），面板标签也从「日志 N」改成「步骤 N」，只数真正的动作。

### 18.2 补上两个能力缺口

| 工具 | 为什么需要 | 关键取舍 |
|---|---|---|
| `select` | 原生下拉弹的是系统层窗口，输入事件永远点不到里面的选项 | 选项由 Dart 选（`chooseOption`，可单测），页面只被告知 index；回执如实写 `派发未知` + 备注「由脚本设置」，不谎称派发成功 |
| `hover` | 只在悬停时展开的菜单，`click` 会先 hover 再点，顺序上就点不到菜单项 | 指针停住不动，回执报告页面是否因此变化 |

`ControlErrorCode.badArguments` 替代了原来用 `internal` 表示「参数不对」的地方。

### 18.3 假 DevTools 服务端（计划 §8 的落地）

`test/support/fake_devtools.dart`：一个 TCP 服务端，说 `/json/list`（**分块传输**，故意分两段写）和 WebSocket 上的 JSON-RPC，页面部分是可编程的假页面（无障碍树、方框、下拉选项、弹窗、子 frame、点击后做什么）。

因为传输层接收的是「一个返回 `Socket` 的函数」，测试把连接器换成 `127.0.0.1` 即可，**socket 之上的代码一行没改**：HTTP 发现、WS 升级与帧、JSON-RPC、无障碍大纲、ref 注册表、几何与遮挡判定、diff、回执，全部真跑。

14 个场景（`test/control_scenarios_test.dart`）：快照生成 ref、点击落在元素中心、点击无变化如实报告、被遮挡时**一个事件都不派发**、禁用控件报 typed error、旧 ref 失效后不误点、输入走编辑管线、往按钮里输入被拒、下拉选中并如实报告、下拉用在非下拉上给出出路、hover 停住指针、弹窗冻结页面、截图返回 base64、iframe 成为独立 session 且内容可读。

### 18.4 场景测试立刻抓到的一个真 bug

`handleDialog` 开头调用的是 `_ensureUsable()`，而它会在「有弹窗」时抛错——也就是说**弹窗永远无法被关闭**：唯一能处理弹窗的调用被弹窗本身挡住了。改成只检查连接的 `_ensureConnected()`。

这个 bug 在真机上表现为「任务卡死在有弹窗的页面上」，靠读代码很难发现，因为它看起来完全合理。

### 18.5 状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**218 通过 / 0 失败**（+14 场景，+10 下拉匹配，+7 步骤卡片）
- 控制层现在有三层测试：纯函数（大纲/匹配/diff/ref）、传输（HTTP/WS 帧）、端到端（假服务端）

---

## 19. 入口改成 Edge Copilot 形态

### 19.1 之前

一个会自吸附的悬浮球浮在页面右下角，压在网页内容上；设置页里另有一个「AI 思路」入口。悬浮球既遮挡内容，又和页面自己的浮动按钮打架。

### 19.2 现在

```
[ ✦ AI ]  [ 🔒 example.com/…            ⌫  ✦ ]
   ↑ 入口在地址左侧，位置固定
```

- `AgentEntryButton`（`browser_controls.dart`）：30×30 的渐变标记，44×44 触摸目标；任务运行时套一圈进度环，并且**不隐藏**（跑任务时最需要它）。
- 点击从下方滑出面板（`showModalBottomSheet`）：上方是时间线（思考 + 步骤卡片），下方是固定的输入框和示例胶囊。键盘弹起时面板整体上移，输入框始终可见。
- 面板头部新增 **✕**：面板盖在页面上，没有自己的退出按钮就只能靠点遮罩去猜。
- 起始页也放了同一个 `AgentEntryButton`（在搜索框左侧），否则空标签页上再也没有任何入口。
- 悬浮球删除（`floating_agent_ball.dart` + 其测试，433 行），入口只剩一个，所有页面位置一致。

### 19.3 一个顺带的取舍

不在输入时，地址栏的清除按钮不再显示：它占 44dp，而用户在阅读页面时并不需要它。360dp 宽度实测地址区域从 165dp 回到 210dp 以上（`browser_controls_test.dart` 有断言）。

### 19.4 状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**219 通过 / 0 失败**（新增 5 个：入口在地址左侧、点击打开面板而不是总结、无入口时不显示、任务运行时显示进度环、360dp 不溢出）

---

## 20. 层补全：滚动到可视区、前进后退、标签页、上传；界面自动隐藏 chrome

### 20.1 最要紧的一个：先滚到可视区

`_measure` 之前只把内容坐标换算成视口坐标，**不判断是否在视口内**。点一个首屏之外的元素，`Input.dispatchTouchEvent` 带着 y=2400 发出去，页面永远收不到：没人处理、没有变化，而回执写的是「已派发」。

这是最坏的一类失败——模型只能靠"重试"去猜，最后被护栏掐死，用户看到的是"AI 点了但页面没反应"。

现在：
- `ScrollOffset` 带视口宽高与 `contains()`；
- `_measure` 返回 `inViewport`；
- `_actionablePoint` 发现不在视口内 → 先 `DOM.scrollIntoViewIfNeeded`（一次）→ 重新测量（稳定性检查重置）→ 仍在外则报 `notVisible`「不在可见区域内」，**一个事件都不派发**。

### 20.2 前进 / 后退

`back` / `forward` 走 `Page.getNavigationHistory` + `Page.navigateToHistoryEntry`：只有历史项能恢复 POST 结果、SPA 路由和滚动位置，重新 `navigate` 同一个地址做不到。没有历史可走时返回 `expectedStateReached: false` 和一句说明，而不是假装走了一步。

### 20.3 标签页

- `ControlSession.listTabs()` 从同一个 socket 读 `/json/list`，看到的是应用真实打开的页面。
- `tabs` 工具列出全部标签并标出 `←当前`。
- `switch_tab` 换的是**连接**不是变量：每个页面是独立 target，先 detach 旧会话再 attach 新的，`onGesture` 一起搬过去。切换后旧 ref 全部作废。

### 20.4 上传

`upload` 先用 `Runtime.callFunctionOn` 确认节点真是 `<input type=file>`（否则 `notEditable` 并提示用 find 找 file input），再 `DOM.setFileInputFiles` 交接，最后再读一次控件确认文件数。回执如实写 `派发未知`：文件选择框是系统弹层，没有任何输入事件；模型不知道路径时应当先 `ask_user`，prompt 里已写明。

### 20.5 界面：阅读时自动收起

- `ChromeVisibility`（纯 Dart，109 行）：向下滚超过阈值收起，向上滚超过阈值放回，接近顶部无条件显示；6px 以内视为手指抖动，方向一变累计清零；首个位置只作基准（页面恢复到上次滚动位置不算用户滚动）。
- 地址栏与底部工具栏各自 `SizeTransition`（上/下对齐），200ms 进、160ms 出。
- **按住不放的情况**：地址栏获得焦点（正在输入）、任务运行中、面板打开——这三种情况下页面滚动不允许收走 chrome，并且立即把它显示出来。
- 重新显示：新文档开始加载、提交地址、切换标签、回起始页、打开面板。

### 20.6 状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**238 通过 / 0 失败**（+19：滚动到可视区/在外不派发/back 两例/tabs 两例/tabs 切换两例/upload 两例 + 11 个 chrome 策略）
- 假服务端同时补上：多 target、历史项、`Page.loadEventFired`（不再让每次导航空等），滚动偏移与视口换算

---

## 21. C3：模型 → 循环 → 层 → 页面，一条链跑通

### 21.1 为什么需要它

层有 24 个场景测试，循环有单元测试，但两者之间从来没在同一个测试里见过面。那意味着下面这些问题一个都抓不到：

- 系统提示词和工具的 JSON Schema 对不上；
- 工具结果模型读不懂（或读起来像指令）；
- 回执到不了面板；
- 循环跑起来了但永远不结束。

### 21.2 两个假服务端

`test/support/fake_openai.dart`：真的 HTTP 服务端，按 OpenAI 的 `chat/completions` 协议回包，支持脚本化 `content` / `tool_calls`，并记录**每一个请求体**和 Authorization 头。测试因此能断言模型实际看到了什么。

`test/support/fake_devtools.dart`（上一批就有）：真的 WebSocket + JSON-RPC 假页面。

`AgentLoopRunner.run` 新增 `controlConnect` 参数，把连接器注入进去；生产路径不传，行为不变。

### 21.3 九个场景（`test/agent_end_to_end_test.dart`）

| 场景 | 断言的重点 |
|---|---|
| 读一页并回答 | 状态 completed、`extractedData` 落地、第二次请求里带 `<page-content>` 包裹、Authorization 正确 |
| 输入并发送 | 页面真的收到 `期待`（`insertText` 到了假页面）、三个动作三张卡、卡上有回执 |
| 旧 ref 失效后恢复 | 卡片 detail 是让人看懂的中文；模型那侧收到 `unknownRef` 这个类型化错误 |
| 一直点死按钮 | 护栏在 4 次之内停下，日志里有「重复」，请求数 < 8 |
| 纯文字回答 | 不碰页面、不调工具、答案进时间线 |
| 参数是坏 JSON | 不崩；退化成「缺少 ref」的可读错误；模型能改 |
| ask_user 往返 | 问题送到面板、答案传回模型（否则提问毫无意义） |
| 端点拒绝请求 | `AgentStatus.error`，消息里能看出是工具不支持 |
| 安全模式下写入 | 停下等确认 → 拒绝 → 记为「跳过」，任务继续收尾 |

### 21.4 这批测试改掉的三个错误假设

1. 以为 `snapshot` 重复会触发护栏——不会，重读是恢复手段，护栏明确豁免它。死按钮才会。
2. 以为「点链接」需要确认——不需要。安全模式拦的是写入类动作，链接点击不算。
3. 以为 ref 顺序按无障碍树编号——只有可交互角色才占 ref，`heading` 不占。测试里改用角色可推断的 ref。

### 21.5 模型配置：只保留 OpenAI 兼容模式

按决定去掉了「服务商快速套用」和 `LlmConfig.presets`（两处重复的 6 家供应商列表）。设置页现在只有三个字段：Base URL、API Key、Model，加一句说明「任意 OpenAI 兼容端点，末尾自动补 `/chat/completions`」。

### 21.6 状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**247 通过 / 0 失败**（+9 端到端）

---

## 22. 模型列表、思考级别、输出上限

### 22.1 获取并选取模型

设置页的 Model 一栏变成「输入框 + 获取列表」：`GET {base}/models`，把 `data[].id` 摊成一排 chip，点一个就填进 Model 并存盘。

- URL 推导和 `/chat/completions` 同一套规则：`https://x/v1`、`https://x/v1/`、`…/v1/models`、甚至直接贴完整 `…/chat/completions` 都能落到同一个地方。
- 兼容两种响应形状：`{"data":[{"id":…}]}` 和裸数组；`id` 或 `name` 都认（自建服务常这么写）。
- 失败不当致命：列表拉不到，用户照样能手填；错误消息直接用服务端原话（`invalid api key`）。

为什么要有这一步：模型名凭记忆打错，是"配置看起来全对但就是不工作"的头号原因。

### 22.2 思考级别

三档，命名用用户的词而不是厂商的：

| 档位 | `reasoning_effort` | 说明 |
|---|---|---|
| 自动（默认） | **不发任何字段** | 由模型自己决定 |
| 快速响应 | `low` | 读一页、点一下 |
| 深度思考 | `high` | 多步任务，更慢更贵 |

「自动」刻意什么都不发：`reasoning_effort` 并非所有 OpenAI 兼容端点都认，一个能跑通的配置不能因为一个偏好突然开始报 400。

### 22.3 输出上限

可选填，留空则不下发。字段名跟着模型家族走：`o1*` / `o3*` / `o4*` / `gpt-5*` 用 `max_completion_tokens`，其余用 `max_tokens` —— 发错了就是 400，这是 OpenAI 兼容世界里最常见的一处分裂。

### 22.4 配置项

`LlmConfig` 新增 `thinking` 与 `maxOutputTokens`，JSON 向后兼容（旧配置读出来是 auto + null）。`defaultConfig()` 改成**空**：这类应用不该猜用户用哪家，`isValid` 为 false 时界面会明说要填三项。

### 22.5 状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**261 通过 / 0 失败**（+14：模型列表 4、请求体 5、配置 5）

---

## 23. 自查：上一批里找到的七个问题

上一批交得急，回头逐行看，有七个真问题，都已修。

| # | 问题 | 后果 | 修法 |
|---|---|---|---|
| 1 | `_saveConfig` 挂在每个 `onChanged` 上，而它自己弹 SnackBar | **每敲一个字弹一次「已保存」**，还顺带每字写 5 次磁盘 | 拆成 `_persist()`（静默）+ `_saveConfig()`（只有保存按钮说话）；输入走 400ms 防抖 |
| 2 | 防抖一旦启动，用户马上返回就丢字 | 最后几百毫秒的输入没写进去 | `dispose` 里先取快照再写：写完不需要页面 |
| 3 | `int.tryParse` 直接当上限 | 填 `0` 或负数会被原样发出去，端点返回 400 | `_parsedMaxTokens` 只接受 > 0 |
| 4 | 模型列表用 `Wrap` 平铺 | OpenRouter 那种几百个模型会把设置页撑爆 | 限高 148 + 内层滚动 + 「N 个可用模型」 |
| 5 | 改了 Base URL，旧列表还留着 | 点一个别的端点的模型名，静默存下一个不存在的模型 | `_modelsFor` 记住列表对应的 URL，不匹配就不显示 |
| 6 | 端点重复返回同一个 id | 两个一样的 chip，用户还得猜 | 用 `Set` 去重 |
| 7 | 摘要/选词走 `_complete`，不认思考级别和上限 | 「深度思考」只对智能体生效，对页面摘要静默失效 | `_complete` 和 `chatWithTools` 共用同一套附加字段 |

### 23.1 顺带补的一处健壮性

`reasoning_effort` 不是所有兼容端点都认，用户选了「深度思考」可能直接换来一个 400。现在：

- 400 / 422 且**服务端原话里提到 reasoning** 时，去掉该字段重发一次，并记住这个端点（`baseUrl|model`），本次会话不再白跑那一趟；
- 其它 400（比如 `messages is required`）**不重试**，原样报错——把无关的失败重发一遍只会让错误更难查；
- 降级不是静默的：运行中在步骤面板记一条「端点不支持「深度思考」」，「测试连通性」的对话框也会写明。

这条规则来自一个已有的模式：`response_format` 的 400 回退。同一个世界，同一种坑。

### 23.2 状态

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：**264 通过 / 0 失败**（+3：降级重试、无关 400 不重试、端到端降级播报）
