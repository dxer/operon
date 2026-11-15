import '../models/llm_config.dart';
import '../models/model_profile.dart';
import 'llm_service.dart';
import 'llm_tools.dart';

/// What one model probe found out.
///
/// A plain text answer proves the key works, but says nothing about whether the
/// model can drive a page. The agent needs function calling, so the probe asks
/// the model to call one trivial tool and reports whether it did.
class ModelProbeResult {
  const ModelProbeResult({
    required this.calledTool,
    this.content,
    this.effortDropped = false,
  });

  final bool calledTool;

  /// What the model said around the tool call, if anything.
  final String? content;

  /// The endpoint refused `reasoning_effort` and the request was retried
  /// without it. The caller can mention this once, where the user is choosing
  /// a model.
  final bool effortDropped;
}

/// The smallest request that still tests the one capability the agent needs.
///
/// Shared by first-run setup and the engine settings page so the two cannot
/// disagree about what "works" means.
Future<ModelProbeResult> probeModel({
  required LlmConfig config,
  ModelProfile profile = const ModelProfile(),
  LlmService? service,
}) async {
  final ownsService = service == null;
  final client = service ?? LlmService();
  try {
    final probe = await client.chatWithTools(
      config: config,
      profile: profile,
      messages: const [
        {
          'role': 'user',
          'content': '调用 ping 工具，把 name 设为 "ok"。只调用工具，不要解释。',
        },
      ],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'ping',
            'description': '连通性探测',
            'parameters': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string', 'description': '固定填 ok'},
              },
              'required': ['name'],
              'additionalProperties': false,
            },
          },
        },
      ],
    );

    final calls = probe.message['tool_calls'];
    final calledTool = calls is List &&
        calls.any((call) =>
            call is Map &&
            call['function'] is Map &&
            (call['function'] as Map)['name'] == 'ping');

    return ModelProbeResult(
      calledTool: calledTool,
      content: probe.content,
      effortDropped: probe.effortDropped,
    );
  } finally {
    if (ownsService) client.dispose();
  }
}
