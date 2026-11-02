enum ActionType {
  click,
  type,
  pressKey,
  selectOption,
  hover,
  scroll,
  navigate,
  goBack,
  wait,
  extractData,
  finish,
  unknown,
}

class AgentAction {
  final String thought;
  final ActionType action;
  final int? elementId;
  final String? text;
  final String? key; // For press_key (Enter, Escape, Tab, Backspace)
  final String? selectValue; // For select_option
  final String? direction; // For scroll: 'down' or 'up'
  final String? url;
  final int? duration; // milliseconds
  final String? summary;
  final dynamic
      extractedData; // Structured data extracted from page (JSON list or map)
  final Map<String, dynamic> rawParams;

  const AgentAction({
    required this.thought,
    required this.action,
    this.elementId,
    this.text,
    this.key,
    this.selectValue,
    this.direction,
    this.url,
    this.duration,
    this.summary,
    this.extractedData,
    this.rawParams = const {},
  });

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    final thought = json['thought'] as String? ?? '';
    final actionStr = (json['action'] as String? ?? '').toLowerCase().trim();
    final params = (json['params'] as Map<String, dynamic>?) ?? {};

    ActionType act;
    switch (actionStr) {
      case 'click':
        act = ActionType.click;
        break;
      case 'type':
        act = ActionType.type;
        break;
      case 'press_key':
      case 'presskey':
      case 'key':
        act = ActionType.pressKey;
        break;
      case 'select_option':
      case 'select':
        act = ActionType.selectOption;
        break;
      case 'hover':
        act = ActionType.hover;
        break;
      case 'scroll':
        act = ActionType.scroll;
        break;
      case 'navigate':
        act = ActionType.navigate;
        break;
      case 'go_back':
      case 'back':
        act = ActionType.goBack;
        break;
      case 'wait':
        act = ActionType.wait;
        break;
      case 'extract_data':
      case 'extract':
        act = ActionType.extractData;
        break;
      case 'finish':
        act = ActionType.finish;
        break;
      default:
        act = ActionType.unknown;
    }

    // Parse element_id safely
    int? elementId;
    if (params.containsKey('element_id')) {
      final val = params['element_id'];
      if (val is int) {
        elementId = val;
      } else if (val is String) {
        elementId = int.tryParse(val);
      }
    }

    // Check extracted data in params or root
    final extractedData =
        params['extracted_data'] ?? params['data'] ?? json['extracted_data'];

    return AgentAction(
      thought: thought,
      action: act,
      elementId: elementId,
      text: params['text'] as String?,
      key: params['key'] as String?,
      selectValue: params['value'] as String?,
      direction: params['direction'] as String?,
      url: params['url'] as String?,
      duration: params['duration'] is int ? params['duration'] as int : null,
      summary: params['summary'] as String?,
      extractedData: extractedData,
      rawParams: params,
    );
  }

  Map<String, dynamic> toJsPayload() {
    String jsAction = action.name;
    if (action == ActionType.pressKey) jsAction = 'press_key';
    if (action == ActionType.selectOption) jsAction = 'select_option';
    if (action == ActionType.goBack) jsAction = 'go_back';
    if (action == ActionType.extractData) jsAction = 'extract_data';

    return {
      'action': jsAction,
      'params': {
        if (elementId != null) 'element_id': elementId,
        if (text != null) 'text': text,
        if (key != null) 'key': key,
        if (selectValue != null) 'value': selectValue,
        if (direction != null) 'direction': direction,
        if (url != null) 'url': url,
        if (duration != null) 'duration': duration,
        if (summary != null) 'summary': summary,
        ...rawParams,
      },
    };
  }

  String get description {
    switch (action) {
      case ActionType.click:
        return '点击元素 [$elementId]';
      case ActionType.type:
        return '在 [$elementId] 输入 "$text"';
      case ActionType.pressKey:
        return '按键 [$key]';
      case ActionType.selectOption:
        return '在 [$elementId] 选择下拉项 "$selectValue"';
      case ActionType.hover:
        return '悬停鼠标在 [$elementId]';
      case ActionType.scroll:
        return '向${direction == "up" ? "上" : "下"}滚动页面';
      case ActionType.navigate:
        return '跳转至 $url';
      case ActionType.goBack:
        return '网页后退一步';
      case ActionType.wait:
        return '等待 ${duration ?? 1500}ms';
      case ActionType.extractData:
        return '提取结构化数据';
      case ActionType.finish:
        return '任务达成: ${summary ?? "已完成"}';
      case ActionType.unknown:
        return '未知操作';
    }
  }

  bool isSensitive(String currentElementText) {
    if (action != ActionType.click && action != ActionType.pressKey) {
      return false;
    }
    final lower =
        '$currentElementText ${text ?? ''} ${url ?? ''} $thought'.toLowerCase();
    const sensitiveWords = [
      'tweet',
      'post',
      'publish',
      'send',
      'submit',
      '发推',
      '发布',
      '发送',
      '提交',
      '评论',
      '回复',
      '转发',
      '关注',
      'pay',
      'payment',
      'purchase',
      'buy',
      'checkout',
      '支付',
      '付款',
      '购买',
      '下单',
      '结算',
      '转账',
      'delete',
      'remove',
      'unfollow',
      'logout',
      '删除',
      '注销',
      '退出登录',
      '解绑',
    ];
    return sensitiveWords.any(lower.contains);
  }
}
