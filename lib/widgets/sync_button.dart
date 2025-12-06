import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/sync_controller.dart';

class SyncButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();

    if (sync.isSyncing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return IconButton(
      icon: const Icon(Icons.sync),
      tooltip: "Sync Now",
      onPressed: () => sync.syncNow(),
    );
  }
}
