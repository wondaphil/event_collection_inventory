// lib/screens/sync_logs_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/sync_controller.dart';

class SyncLogsScreen extends StatelessWidget {
  const SyncLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();

    return Scaffold(
      appBar: AppBar(title: const Text("Sync Status")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text("Sync Status:",
                style: Theme.of(context).textTheme.titleMedium),
            Text(sync.statusText,
                style: const TextStyle(color: Colors.teal)),
            const SizedBox(height: 16),

            Text("Notes:",
                style: Theme.of(context).textTheme.titleMedium),
            const Text(
              "• This version uses incremental syncing.\n"
              "• Timestamps are stored in millis.\n"
              "• Device ID and last sync timestamps are no longer used.",
              style: TextStyle(height: 1.4),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => sync.syncNow(),
                  icon: const Icon(Icons.sync),
                  label: const Text("Force Sync"),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text("Close"),
                )
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),

            const Expanded(
              child: Center(
                child: Text("No logs available"),
              ),
            )
          ],
        ),
      ),
    );
  }
}