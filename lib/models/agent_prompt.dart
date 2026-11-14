/// A sentence the user asks often, saved so they do not have to type it again.
///
/// Deliberately not a macro: there is no recording, no replay, no steps. It is
/// a prompt with a name. The moment it grows into "and then it clicks here",
/// it stops being something the user can trust — the agent decides the steps,
/// every time, from the page as it is now.
class AgentPrompt {
  const AgentPrompt({
    required this.id,
    required this.title,
    required this.goal,
  });

  final String id;
  final String title;
  final String goal;

  AgentPrompt copyWith({String? title, String? goal}) => AgentPrompt(
        id: id,
        title: title ?? this.title,
        goal: goal ?? this.goal,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'goal': goal};

  factory AgentPrompt.fromJson(Map<String, dynamic> json) => AgentPrompt(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        goal: json['goal']?.toString() ?? '',
      );

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return title.toLowerCase().contains(needle) ||
        goal.toLowerCase().contains(needle);
  }

  /// What the settings list calls it when the title was left blank.
  String get displayTitle => title.trim().isEmpty ? goal : title;
}
