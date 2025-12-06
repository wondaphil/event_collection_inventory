// lib/utils/sync_controller.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'sync_service.dart';

class SyncController extends ChangeNotifier {
  bool _isSyncing = false;
  String? _errorMessage;

  bool get isSyncing => _isSyncing;
  String? get errorMessage => _errorMessage;

  // Optional — used only for displaying in UI
  String statusText = "Idle";

  Timer? _refreshTimer;

  Future<void> syncNow() async {
    if (_isSyncing) return;

    _isSyncing = true;
    _errorMessage = null;
    statusText = "Syncing…";
    notifyListeners();

    // refresh UI every second (spinner, timestamp, etc.)
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());

    try {
      await SyncService.instance.syncAll();
      statusText = "Sync completed";
    } catch (e) {
      _errorMessage = e.toString();
      statusText = "Sync failed";
    }

    _refreshTimer?.cancel();
    _refreshTimer = null;

    _isSyncing = false;
    notifyListeners();
  }

  /// For delete actions (items / transactions)
  Future<void> forceSync() async => syncNow();
}