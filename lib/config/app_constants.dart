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

  // Recipe templates (Universal Workflow Prompts)
  static const List<Map<String, String>> recipePresets = [
    {
      'title': '抓取推文/动态',
      'prompt': '抓取当前页面最新的 5 条推文内容及博主名字，并输出为结构化数据',
    },
    {
      'title': '自动回复第一条',
      'prompt': '找到当前页面的第一条推文/帖子，点击回复并键入：非常有价值的分享，感谢！',
    },
    {
      'title': '搜索话题并按回车',
      'prompt': '在顶部搜索框输入 #AI，并按下 Enter 键提交搜索',
    },
    {
      'title': '网页正文抓取总结',
      'prompt': '阅读提取当前网页正文核心内容，并提炼 3 点关键摘要',
    },
    {
      'title': '滚动页面查看更多',
      'prompt': '向下滚动页面 3 次，加载更多动态内容',
    },
  ];

  // SharedPreferences Keys
  static const String keyBaseUrl = 'pref_llm_base_url';
  static const String keyApiKey = 'pref_llm_api_key';
  static const String keyModel = 'pref_llm_model';
  static const String keyTemperature = 'pref_llm_temp';
  static const String keyUserAgent = 'pref_user_agent';
  static const String keyMaxSteps = 'pref_max_steps';
  static const String keySafeMode = 'pref_safe_mode';
  static const String keyHomepage = 'pref_homepage';

  // Default Homepage
  static const String defaultHomepage = 'https://x.com';

  // Universal System Prompt v2.0
  static const String agentSystemPrompt = '''
你是一个精通通用网页操作与数据抓取的自主智能体（Web Agent）。你的任务是根据用户给定的目标，通过一系列原子动作完成对当前网页的浏览、交互、数据提取或内容发布。

### 核心规则：
1. 【严格且仅输出单个合法的 JSON 格式】，绝不包含任何多余文本或未包裹在 JSON 内的前后缀。
2. 仔细查看【页面主要内容摘要】和【可交互操作元素】。元素编号 [1], [2] 必须与上下文一致，严禁捏造。
3. 很多现代网页输入内容后没有明显的“搜索”按钮，在输入完成后，请使用 "press_key" (key: "Enter") 模拟按下回车键提交。
4. 如果任务目标是【数据提取/爬取】，可以在 "extract_data" 或 "finish" 中将抓取到的内容输出在 "extracted_data" 字段（数组或对象格式）。
5. 遇到下拉菜单选择请用 "select_option"，遇到误操作可用 "go_back" 后退，如果没找到元素可用 "scroll" 滚动。

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
