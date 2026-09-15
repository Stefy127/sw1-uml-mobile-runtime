import 'package:flutter/foundation.dart';

import 'sync_service.dart';

enum SyncState { offline, online, syncing, syncError }

class SyncCoordinator extends ChangeNotifier {
  static final shared = SyncCoordinator();

  SyncService service;
  SyncState _state = SyncState.offline;
  int _pendingCount = 0;
  String? _error;

  SyncCoordinator({SyncService? service}) : service = service ?? SyncService();

  SyncState get state => _state;
  int get pendingCount => _pendingCount;
  String? get error => _error;

  void configure(SyncService value) {
    service = value;
  }

  void markOffline() {
    _state = SyncState.offline;
    notifyListeners();
  }

  void markOnline() {
    _state = SyncState.online;
    _error = null;
    notifyListeners();
  }

  Future<int> refreshPendingCount() async {
    _pendingCount = (await service.pendingOperations()).length;
    notifyListeners();
    return _pendingCount;
  }

  Future<int> flush() async {
    await refreshPendingCount();
    if (_pendingCount == 0) {
      _state = SyncState.online;
      notifyListeners();
      return 0;
    }

    _state = SyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      final completed = await service.flush();
      _pendingCount = (await service.pendingOperations()).length;
      _state = _pendingCount == 0 ? SyncState.online : SyncState.syncError;
      notifyListeners();
      return completed;
    } catch (error) {
      _error = error.toString();
      _state = SyncState.syncError;
      await refreshPendingCount();
      notifyListeners();
      return 0;
    }
  }

  Future<T> flushThen<T>(Future<T> Function() refresh) async {
    await flush();
    return refresh();
  }
}