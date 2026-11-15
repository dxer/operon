import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../config/app_tokens.dart';
import '../../services/favicon_service.dart';

/// A site's mark: its favicon, or its first letter when there is none.
///
/// The letter is a fallback, not a design choice — a monogram is what you show
/// while you wait, and what you keep showing for the sites that ship no icon.
/// It is tinted with the theme ink rather than a brand colour: four letters in
/// four brand colours is how a start page starts looking memorised.
class SiteIcon extends StatefulWidget {
  const SiteIcon({
    super.key,
    required this.host,
    this.size = 46,
    this.label,
  });

  final String host;

  /// Square edge, in logical pixels.
  final double size;

  /// What to draw if there is no icon; defaults to the host.
  final String? label;

  @override
  State<SiteIcon> createState() => _SiteIconState();
}

class _SiteIconState extends State<SiteIcon> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = FaviconService.cached(widget.host);
    if (_bytes == null) _load();
  }

  @override
  void didUpdateWidget(covariant SiteIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _bytes = FaviconService.cached(widget.host);
      if (_bytes == null) _load();
    }
  }

  Future<void> _load() async {
    final bytes = await FaviconService.load(widget.host);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(
      widget.size >= 32 ? AppRadius.icon : AppRadius.chip,
    );
    final bytes = _bytes;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppInk.sunken(isDark),
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: bytes != null
              ? Image.memory(
                  bytes,
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) => _letter(isDark),
                )
              : _letter(isDark),
        ),
      ),
    );
  }

  Widget _letter(bool isDark) {
    final label = widget.label?.trim() ?? '';
    final source = label.isNotEmpty ? label : widget.host;
    final letter = source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
    final big = widget.size >= 32;
    return Center(
      child: Text(
        letter,
        style: (big ? AppType.headline : AppType.caption).copyWith(
          color: AppInk.secondary(isDark),
        ),
      ),
    );
  }
}
