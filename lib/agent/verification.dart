import '../control/protocol/results.dart';

/// Verification debt: what the run asked the page to do and never saw happen.
///
/// The control layer already reports three separate facts per action —
/// dispatched, page reacted, expected state reached — and the guards already
/// count failures. Neither answers the one question a summary has to answer:
/// 「这一步真的成了吗？」
///
/// So the run keeps its own small ledger. An action whose result does not show
/// its own outcome owes evidence; a later look at the page pays it off; a step
/// that is never paid off is printed in the answer as 未证实, instead of being
/// covered by the model's optimism. The model is optimistic by construction —
/// it writes 「已完成」 from its own intent — and an agent browser whose success
/// claims are worth nothing is not worth running.
///
/// Detection is best effort; the enforcement is one place: `done` may not say
/// `success` while debt is open.

/// The tools whose own outcome can go unseen.
///
/// Deliberately a list rather than `toolMutates`, because "was this seen" and
/// "did this change the page" are different questions:
///
/// - `scroll` rarely changes a line of the outline, so every scroll would owe
///   evidence it can never produce;
/// - `hover` is a pointer position, not a change;
/// - `switch_tab` and `close_tab` change what the run is looking at, not the
///   page — what they do to the ledger is retire debt, not create it.
const Set<String> debtTools = {
  'click',
  'type',
  'fill_form',
  'clear',
  'select',
  'press',
  'navigate',
  'back',
  'forward',
  'handle_dialog',
  'upload',
};

/// The tools whose success *is* a look at the page, so it pays off any debt.
const Set<String> evidenceTools = {
  'snapshot',
  'find',
  'read',
  'screenshot',
};

/// Moving the page is not evidence about it.
///
/// A click that lands somewhere else and an observation of the page it left
/// are different things: after a navigation the old page is gone, so whatever
/// was owed there can only be admitted, never checked. Treating the move as
/// evidence would quietly pay the debt off with a page that no longer exists.
const Set<String> navigationTools = {
  'navigate',
  'back',
  'forward',
  'switch_tab',
  'close_tab',
};

/// Whether this call's result leaves its own outcome unseen.
bool createsDebt(String tool, ToolResult result) {
  if (!debtTools.contains(tool)) return false;

  final receipt = result.receipt;
  if (!result.ok) {
    // A typed failure before dispatch (stale ref, covered target, blocked
    // site) did nothing, so nothing is owed. A failure that may have reached
    // the page is exactly the case this ledger exists for.
    if (receipt == null) return false;
    return receipt.delivery != Delivery.notDelivered;
  }

  if (receipt == null) return true;
  if (receipt.delivery == Delivery.unknown) return true;
  if (receipt.expectedStateReached == false) return true;
  // Dispatched and the page did not move: the model asked for something and
  // has no idea whether it happened.
  if (receipt.pageReacted == false) return true;
  return false;
}

/// Whether this result proves the state of the page it was read on.
bool clearsDebt(String tool, ToolResult result) {
  if (!result.ok) return false;
  if (evidenceTools.contains(tool)) return true;
  if (navigationTools.contains(tool)) return false;
  if (!debtTools.contains(tool)) return false;

  final receipt = result.receipt;
  if (receipt == null) return false;
  // An action that visibly changed this page showed its own effect.
  return receipt.pageReacted == true || receipt.changes.isNotEmpty;
}

/// One step the run owes evidence for.
class DebtItem {
  DebtItem({required this.tool, required this.label, this.url});

  final String tool;

  /// 「点击「提交」」 — what the user reads if it is never verified.
  final String label;

  /// The page it happened on, so a later page cannot pay it off by accident.
  final String? url;

  /// The run left that page: nothing can verify it now, so the answer must
  /// state it instead.
  bool lost = false;

  @override
  String toString() => '$label${lost ? ' (lost)' : ''}';
}

/// The steps one run owes evidence for, in the order they happened.
class DebtLedger {
  final List<DebtItem> _items = [];

  List<DebtItem> get all => List.unmodifiable(_items);

  /// Still checkable: the run could go and look.
  List<DebtItem> get open =>
      _items.where((item) => !item.lost).toList(growable: false);

  bool get isEmpty => _items.isEmpty;

  /// One uncertain step is one item, however many times it was repeated.
  ///
  /// A model that clicks the same submit button three times has one unknown,
  /// not three, and the user should not read the same line three times.
  void add(DebtItem item) {
    final index =
        _items.indexWhere((existing) => existing.label == item.label);
    if (index >= 0) {
      _items[index] = item;
    } else {
      _items.add(item);
    }
  }

  /// A fresh look at the page pays off everything still checkable.
  void clear() => _items.removeWhere((item) => !item.lost);

  /// The run moved away from the page an item was owed on.
  void retireElsewhere(String? url) {
    if (url == null) return;
    for (final item in _items) {
      if (item.lost) continue;
      if (item.url != null && item.url != url) item.lost = true;
    }
  }

  /// What the model reads when it tries to claim success.
  String refusal() {
    final labels = open.map((item) => item.label).join('、');
    return '还不能说成功：$labels 的结果你还没看到。'
        '先 snapshot（或 find、read）确认页面现在的状态，再调用 done；'
        '如果这一步本来就无法确认，用 done 的 outcome=partial 说明，不要写成 success。';
  }

  /// The lines an answer gains for steps that were never confirmed.
  List<String> unverifiedLines() => [
        for (final item in _items)
          item.lost
              ? '- ${item.label}：未证实（已经离开那个页面，没法回头确认结果）'
              : '- ${item.label}：未证实（动作发出去了，但没有回头看过页面现在的状态）',
      ];
}
