import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

class DiffCounts extends StatelessWidget {
  const DiffCounts(this.session, {super.key, this.size = 12});
  final SessionInfo session;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = session.shownChanges;
    if (c == null || (c.added == 0 && c.removed == 0)) {
      return const SizedBox.shrink();
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('+${c.added}', style: sans(size, color: AppColors.ok, tabular: true)),
      const SizedBox(width: 5),
      Text('-${c.removed}',
          style: sans(size, color: AppColors.danger, tabular: true)),
    ]);
  }
}
