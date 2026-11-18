// ============================================================================
// Shared phone-layout helpers (screens narrower than the breakpoints below).
// Every helper behaves exactly like the old desktop layout at 768 px and wider,
// so adding one to a screen never changes the desktop / tablet look.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Phone: narrower than 600 px.
bool isPhone(BuildContext context) => MediaQuery.of(context).size.width < 600;

/// Compact: narrower than 768 px (same breakpoint the client shell uses).
bool isCompact(BuildContext context) => MediaQuery.of(context).size.width < 768;

/// Dialog width that never exceeds the screen: min(desired, screenWidth - 32).
/// At 600 px and wider it returns [desired] unchanged.
double phoneDialogWidth(BuildContext context, double desired) {
  final w = MediaQuery.of(context).size.width;
  return w < 600 ? math.min(desired, w - 32) : desired;
}

/// A title with action buttons.
/// - width >= 768: one Row, title on the left, actions on the right (as before)
/// - width <  768: title on the first line, actions wrap onto the next line(s)
///   so none of them is cut off at the screen edge.
class PhoneHeaderRow extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  final double spacing;

  const PhoneHeaderRow({
    super.key,
    required this.title,
    this.actions = const [],
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCompact(context)) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: title),
          if (actions.isNotEmpty)
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        if (actions.isNotEmpty) ...[
          SizedBox(height: spacing),
          Wrap(
            spacing: spacing,
            runSpacing: spacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ],
    );
  }
}

/// Text that shrinks to fit its space instead of overflowing (money, counts).
class FitText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Alignment alignment;

  const FitText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(text, style: style, textAlign: textAlign, maxLines: 1),
    );
  }
}

/// Number of grid columns for stat / summary cards:
/// phone 2, tablet-ish (under 1024) 3, otherwise [desktop].
int adaptiveColumns(BuildContext context, {int desktop = 4}) {
  final w = MediaQuery.of(context).size.width;
  if (w < 600) return 2;
  if (w < 1024) return math.min(3, desktop);
  return desktop;
}
