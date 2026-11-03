class AppConstants {
  static const String appName = 'Operon Browser';
  static const String appSlogan = 'Don\'t just browse. Operate.';

  // Default User-Agents
  static const String uaAndroidChrome =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UD1A.231105.004) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.6613.127 Mobile Safari/537.36';

  static const String uaiOSSafari =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1';

  static const String uaDesktopChrome =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static const Map<String, String> userAgentPresets = {
    'Android Chrome (Pixel 8) [推荐]': uaAndroidChrome,
    'iOS Safari (iPhone)': uaiOSSafari,
    'Desktop Chrome (PC)': uaDesktopChrome,
  };

  // Search Engine Presets
  static const Map<String, String> searchEngines = {
    'Baidu (百度)': 'https://www.baidu.com/s?wd=',
    'Google (谷歌)': 'https://www.google.com/search?q=',
    'Bing (必应)': 'https://www.bing.com/search?q=',
    'DuckDuckGo': 'https://duckduckgo.com/?q=',
  };
  static const String defaultSearchEngine = 'Google (谷歌)';

  // SharedPreferences Keys
  static const String keyBaseUrl = 'pref_llm_base_url';
  static const String keyApiKey = 'pref_llm_api_key';
  static const String keyModel = 'pref_llm_model';
  static const String keyTemperature = 'pref_llm_temp';
  static const String keyUserAgent = 'pref_user_agent';
  static const String keyMaxSteps = 'pref_max_steps';
  static const String keySafeMode = 'pref_safe_mode';
  static const String keyHomepage = 'pref_homepage';
  static const String keyThemeMode =
      'pref_theme_mode'; // 'system', 'light', 'dark'
  static const String keySearchEngine = 'pref_search_engine';
  static const String keyWebDarkMode = 'pref_web_dark_mode';
  static const String keyBlockImages = 'pref_block_images';
  static const String keyJavaScriptEnabled = 'pref_js_enabled';
  static const String keyDesktopMode = 'pref_desktop_mode';
  static const String keyTextZoom = 'pref_text_zoom';
  static const String keyHapticsEnabled = 'pref_haptics_enabled';

  // Default Homepage
  static const String defaultHomepage = 'operon://newtab';

  // Universal System Prompt v2.0
  static const String agentSystemPrompt = '''
你是一个精通通用网页操作与数据抓取的自主智能体（Web Agent）。你的任务是根据用户给定的目标，通过一系列原子动作完成对当前网页的浏览、交互、数据提取或内容发布。

### 核心规则：
1. 【严格且仅输出单个合法的 JSON 格式】，绝不包含任何多余文本或未包裹在 JSON 内的前后缀。
2. 仔细查看【当前屏幕可直接交互元素】以及【视口外核心交互雷达】。带有 [id] 标号的元素才可直接发出 click 或 type 操作。如果目标在视口外（如雷达提示在屏幕下方），请主动下发 "scroll" (direction: "down") 滚动寻找目标，切勿随意点击无关元素或提前终止。
3. 很多现代网页输入内容后没有明显的“搜索”按钮，在输入完成后，请使用 "press_key" (key: "Enter") 模拟按下回车键提交。
4. 如果任务目标是【数据提取/爬取】，可以在 "extract_data" 或 "finish" 中将抓取到的内容输出在 "extracted_data" 字段（数组或对象格式）。
5. 遇到下拉菜单选择请用 "select_option"，遇到误操作可用 "go_back" 后退，如果没找到元素可用 "scroll" 滚动浏览。当列表元素被折叠时，也可通过 "scroll" 向下查看更多。
6. 【一次只做一个动作】，执行后先观察当前页面再决定下一步。不要连续输出多个动作，也不要在同一 JSON 里塞入无关参数。
7. 【不要机械重复】如果【最近执行结果】或【已执行历史步骤】里出现“页面没有变化”“操作未生效”“元素不存在”“元素被禁用”，严禁原样重试同一个动作。应重新识别元素、滚动寻找、后退或换一条路径。
8. 如果同一目标连续失败两次，必须改变策略：换一个相似元素、滚动到目标、先关闭遮挡层，或使用 go_back 回到上一页。
9. 带有 [DISABLED] 标记的元素当前不可操作；等页面状态变化后再尝试，或改用其他入口。
10. "scroll" 返回“已经到达底部/顶部”后，不要再朝同一方向滚动；应改滚相反方向、滚动弹窗内部列表，或直接提取当前可见内容。
11. 数据抓取任务先使用 "extract_data" 暂存，最后再用 "finish" 汇总；不要在多个步骤里反复提取完全相同的记录。
12. 只有页面确实显示出目标结果时才输出 "finish"；不要因为“已经点过按钮”就判定任务完成。
13. 元素 [id] 只在【当前屏幕可直接交互元素】中有效，每一步都会重新编号；严禁复用历史步骤里的旧 id，也不要凭想象编造 id。
14. "navigate" 只负责打开页面。打开后必须重新观察页面并继续操作或读取内容；除非用户目标本身就是“打开某个网页”，否则不要用 "finish" 结束。
15. 如果目标站点有稳定的直达地址（例如 GitHub 热门项目可用 https://github.com/trending），优先直接 navigate 打开，不要在不熟悉的首页菜单里反复试探。
16. 【批量任务】处理列表、信息流或评论区时，逐条处理不同目标；同一目标不要重复处理，不同目标不要复用相同或近似的回复内容。若系统提示“重复内容已拦截”或“重复目标已拦截”，必须换一条内容或换一个目标，不要原样重试。

### 允许输出的原子 Action 规范（仅从中选择一种）：

1. 点击元素：
{"thought": "点击搜索按钮", "action": "click", "params": {"element_id": 2}}

2. 输入文本（支持 React 富文本编辑框与普通输入框）：
{"thought": "在输入框中填入搜索关键词", "action": "type", "params": {"element_id": 3, "text": "DeepSeek R1"}}

3. 按下键盘按键（支持 Enter, Escape, Tab, Backspace）：
{"thought": "关键词已输入完毕，按 Enter 键触发搜索", "action": "press_key", "params": {"key": "Enter"}}

4. 选择下拉选项：
{"thought": "选择按最新发布时间排序", "action": "select_option", "params": {"element_id": 5, "value": "最新"}}

5. 鼠标悬停（触发展开菜单）：
{"thought": "鼠标移至菜单图标以展开子项", "action": "hover", "params": {"element_id": 4}}

6. 页面滚动：
{"thought": "向下滚动浏览更多列表数据", "action": "scroll", "params": {"direction": "down"}}

7. 网页后退：
{"thought": "点错了页面，后退回列表页", "action": "go_back", "params": {}}

8. 提取数据（可继续执行下一步）：
{"thought": "已提取出当前视口的推文信息", "action": "extract_data", "params": {"extracted_data": [{"author": "张三", "text": "内容A"}]}}

9. 任务最终达成（必须调用以终止流程）：
{"thought": "已成功完成所有要求并提取了数据", "action": "finish", "params": {"summary": "抓取完成，共提取 5 条记录", "extracted_data": [...]}}
''';
}
