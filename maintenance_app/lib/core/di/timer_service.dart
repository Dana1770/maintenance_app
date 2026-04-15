import 'dart:async';
import 'package:flutter/foundation.dart';

typedef OdooSyncCallback = Future<int?> Function(int taskId, int localSeconds);

/// Global singleton timer service.
/// 
/// State machine per taskId:
///   STOPPED  → neither _started nor _paused
///   RUNNING  → _started=true,  _paused=false, ticker active
///   PAUSED   → _started=true,  _paused=true,  ticker cancelled
///
/// _userPaused[id] = true  → user tapped Pause in app; sync MUST NOT restart ticker.
/// _pausedAt[id]           → UTC moment the app recorded the pause.
///                           Used to reject stale Odoo timer_start values that
///                           predate our pause (i.e. Odoo DB hasn't caught up yet).
class TimerService extends ChangeNotifier {
  TimerService._();
  static final TimerService instance = TimerService._();

  final Map<int, int>      _seconds    = {};
  final Map<int, DateTime> _startedAt  = {};
  final Map<int, bool>     _paused     = {};
  final Map<int, bool>     _userPaused = {};
  final Map<int, DateTime> _pausedAt   = {}; // when user-pause was recorded (UTC)
  final Map<int, Timer>    _timers     = {};
  final Map<int, Timer>    _syncTimers = {};
  final Set<int>           _started    = {};

  OdooSyncCallback? _odooSyncCallback;

  DateTime? _lastVisitStartedAt;
  int       _lastVisitSeconds = 0;
  DateTime? get lastVisitStartedAt => _lastVisitStartedAt;
  int       get lastVisitSeconds   => _lastVisitSeconds;
  Duration? get lastCompletedDuration =>
      _lastVisitSeconds > 0 ? Duration(seconds: _lastVisitSeconds) : null;

  void registerOdooSync(OdooSyncCallback? cb) => _odooSyncCallback = cb;

  bool      isStarted(int id)    => _started.contains(id);
  bool      isPaused(int id)     => _paused[id] ?? false;
  bool      isUserPaused(int id) => _userPaused[id] ?? false;
  /// UTC moment the user-pause was recorded. Null when not user-paused.
  DateTime? pausedAt(int id)     => _pausedAt[id];
  int       seconds(int id)      => _seconds[id] ?? 0;
  DateTime? startedAt(int id)    => _startedAt[id];

  void resetTaskState(int taskId) {
    _timers[taskId]?.cancel();
    _timers.remove(taskId);
    _syncTimers[taskId]?.cancel();
    _syncTimers.remove(taskId);
    _seconds.remove(taskId);
    _startedAt.remove(taskId);
    _paused.remove(taskId);
    _userPaused.remove(taskId);
    _pausedAt.remove(taskId);
    _started.remove(taskId);
    notifyListeners();
  }
  /// Check if a task is completed (stage is done/closed)
  bool isTaskCompleted(int taskId, Map<String, dynamic>? taskInfo) {
    if (taskInfo == null) return false;
    final stage = taskInfo['stage_id'];
    if (stage is List && stage.length > 1) {
      final stageName = stage[1].toString().toLowerCase();
      return stageName.contains('done') ||
          stageName.contains('complet') ||
          stageName.contains('closed');
    }
    return false;
  }
  // ── Poll-only (no ticker) ────────────────────────────────────────────────
  void startPollingOnly(int taskId) {
    if (_syncTimers.containsKey(taskId)) return;
    _launchSyncTimerUnguarded(taskId);
  }


  void _launchSyncTimerUnguarded(int taskId) {
    _syncTimers[taskId]?.cancel();
    _syncTimers[taskId] = Timer.periodic(const Duration(seconds: 30), (_) async {
      final cb = _odooSyncCallback;
      if (cb == null) return;
      try {
        final odooSecs = await cb(taskId, _seconds[taskId] ?? 0);
        if (odooSecs != null && !(_paused[taskId] ?? false)) {
          final drift = (odooSecs - (_seconds[taskId] ?? 0)).abs();
          if (drift > 10) {
            _seconds[taskId]   = odooSecs;
            _startedAt[taskId] = DateTime.now().subtract(Duration(seconds: odooSecs));
            notifyListeners();
          }
        }
      } catch (_) {}
    });
  }

  // ── Start (running) ──────────────────────────────────────────────────────
  void startTimer(int taskId, {int seedSeconds = 0, DateTime? startedAt, bool forceReseed = false}) {
    if (_started.contains(taskId) && !forceReseed) return;
    _started.add(taskId);
    _seconds[taskId]    = seedSeconds;
    _startedAt[taskId]  = startedAt ?? DateTime.now().subtract(Duration(seconds: seedSeconds));
    _paused[taskId]     = false;
    _userPaused[taskId] = false;
    _pausedAt.remove(taskId);
    _launchTicker(taskId);
    _launchSyncTimer(taskId);
    notifyListeners();
  }

  // ── Restore paused state from Odoo on screen open (NO ticker) ───────────
  void startTimerPaused(int taskId, {required int seedSeconds}) {
    _started.add(taskId);
    _seconds[taskId]    = seedSeconds;
    _startedAt[taskId]  = DateTime.now().subtract(Duration(seconds: seedSeconds));
    _paused[taskId]     = true;
    _userPaused[taskId] = false; // Odoo-sourced, not user-initiated
    _pausedAt.remove(taskId);
    // Kill any stale ticker.
    _timers[taskId]?.cancel();
    _timers.remove(taskId);
    _launchSyncTimer(taskId);
    notifyListeners();
  }

  // ── Apply a running Odoo timer (sync / init) ─────────────────────────────
  // SAFE: will NOT override a user-initiated pause, and will NOT start the
  // ticker when Odoo's timer_start predates the moment the user paused
  // (stale DB state).
  //
  // odooTimerStart: the DateTime parsed from Odoo's timer_start field (UTC→local).
  // seedSeconds:    elapsed seconds computed from that timer_start.
  void forceApplyOdooTimer(int taskId,
      {required int seedSeconds, required DateTime startedAt,
       DateTime? odooTimerStart}) {

    // Guard 1: user deliberately paused — check if Odoo's timer_start is stale.
    if (_userPaused[taskId] == true) {
      final pt = _pausedAt[taskId];
      // If we have a pause timestamp AND Odoo's start is BEFORE we paused,
      // it's the old session still visible in DB → ignore completely.
      if (pt != null && odooTimerStart != null && odooTimerStart.isBefore(pt)) {
        return; // stale — Odoo DB hasn't cleared timer_start yet
      }
      // If Odoo's start is AFTER our pause, someone resumed from the web UI
      // → honour it and lift the user-pause flag.
      if (pt != null && odooTimerStart != null && !odooTimerStart.isBefore(pt)) {
        // Fall through — allow resync below.
      } else {
        // No timestamps to compare — stay paused to be safe.
        return;
      }
    }

    final wasRunning = _started.contains(taskId);
    final isTicking  = wasRunning && !(_paused[taskId] ?? false) && _timers.containsKey(taskId);

    if (isTicking) {
      final drift = (seedSeconds - (_seconds[taskId] ?? 0)).abs();
      if (drift > 5) {
        _seconds[taskId]   = seedSeconds;
        _startedAt[taskId] = startedAt;
      }
      notifyListeners();
      return;
    }

    _started.add(taskId);
    _seconds[taskId]    = seedSeconds;
    _startedAt[taskId]  = startedAt;
    _paused[taskId]     = false;
    _userPaused[taskId] = false;
    _pausedAt.remove(taskId);
    _launchTicker(taskId);
    _launchSyncTimer(taskId);
    notifyListeners();
  }

  void _launchSyncTimer(int taskId) {
    _syncTimers[taskId]?.cancel();
    _syncTimers[taskId] = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_started.contains(taskId)) return;
      final cb = _odooSyncCallback;
      if (cb == null) return;
      try {
        final odooSecs = await cb(taskId, _seconds[taskId] ?? 0);
        // Drift correction only while actively ticking.
        if (odooSecs != null && !(_paused[taskId] ?? false)) {
          final drift = (odooSecs - (_seconds[taskId] ?? 0)).abs();
          if (drift > 10) {
            _seconds[taskId]   = odooSecs;
            _startedAt[taskId] = DateTime.now().subtract(Duration(seconds: odooSecs));
            notifyListeners();
          }
        }
      } catch (_) {}
    });
  }

  void recordCompletedVisit(int taskId) {
    final s = _seconds[taskId] ?? 0;
    if (s > 0) {
      _lastVisitSeconds   = s;
      _lastVisitStartedAt = _startedAt[taskId];
    }
  }

  void _launchTicker(int taskId) {
    _timers[taskId]?.cancel();
    _timers[taskId] = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!(_paused[taskId] ?? false)) {
        _seconds[taskId] = (_seconds[taskId] ?? 0) + 1;
        notifyListeners();
      }
    });
  }

  /// Clear the user-pause flag (called only when Odoo confirms a new timer_start
  /// that is AFTER the pause moment — meaning someone resumed from the web UI,
  /// or the user pressed Resume in the app).
  void clearUserPaused(int taskId) {
    _userPaused[taskId] = false;
    _pausedAt.remove(taskId);
  }

  /// User tapped Pause in the app UI.
  void pause(int taskId) {
    _paused[taskId]     = true;
    _userPaused[taskId] = true;
    _pausedAt[taskId]   = DateTime.now().toUtc(); // record exact pause moment
    // Kill the ticker immediately so it cannot add more seconds.
    _timers[taskId]?.cancel();
    _timers.remove(taskId);
    // Keep sync timer alive to detect external Odoo resumes.
    notifyListeners();
  }

  /// User tapped Resume in the app UI.
  void resume(int taskId) {
    _paused[taskId]     = false;
    _userPaused[taskId] = false;
    _pausedAt.remove(taskId);
    _launchTicker(taskId);
    if (!_syncTimers.containsKey(taskId)) _launchSyncTimer(taskId);
    notifyListeners();
  }

  /// Zero out seconds after an external Odoo-stop is detected.
  void resetSeconds(int taskId) {
    _seconds[taskId]   = 0;
    _startedAt[taskId] = DateTime.now();
    _userPaused[taskId] = false;
    _pausedAt.remove(taskId);
    notifyListeners();
  }

  void stopTimer(int taskId) {
    _timers[taskId]?.cancel();     _timers.remove(taskId);
    _syncTimers[taskId]?.cancel(); _syncTimers.remove(taskId);
    _seconds.remove(taskId);
    _startedAt.remove(taskId);
    _paused.remove(taskId);
    _userPaused.remove(taskId);
    _pausedAt.remove(taskId);
    _started.remove(taskId);
    notifyListeners();
  }

  String display(int taskId) {
    final s   = seconds(taskId);
    final h   = s ~/ 3600;
    final m   = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  double hoursElapsed(int taskId) => seconds(taskId) / 3600.0;
}
