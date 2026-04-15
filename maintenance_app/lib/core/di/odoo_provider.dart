import 'dart:async';
import 'package:flutter/material.dart';
import './odoo_service.dart';
import './timer_service.dart';

enum LoadState { idle, loading, loaded, error }

class OdooProvider extends ChangeNotifier {
  OdooService? _service;
  int?         _loggedUid;
  Timer?       _refreshTimer;

  // Auto-refresh every 30 seconds so type changes in Odoo reflect immediately
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_service != null && _loggedUid != null) fetchMyTasks();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  LoadState tasksState        = LoadState.idle;
  LoadState customersState    = LoadState.idle;
  LoadState sparePartsState   = LoadState.idle;
  LoadState surveyState       = LoadState.idle;
  LoadState requestsState     = LoadState.idle;

  String? tasksError;
  String? customersError;
  String? sparePartsError;
  String? surveyError;
  String? requestsError;

  // ── All tasks ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> myTasks         = [];
  List<Map<String, dynamic>> periodicTasks   = [];
  List<Map<String, dynamic>> emergencyTasks  = [];
  List<Map<String, dynamic>> surveyTasks     = [];
  List<Map<String, dynamic>> sparePartsTasks = [];

  // ── Customers + equipment ─────────────────────────────────────────────
  List<Map<String, dynamic>> customers  = [];
  List<Map<String, dynamic>> equipment  = [];

  // ── Spare parts ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> spareParts = [];

  // ── Maintenance requests ──────────────────────────────────────────────
  List<Map<String, dynamic>> maintenanceRequests = [];

  // ── Today timesheets ──────────────────────────────────────────────────
  List<Map<String, dynamic>> todayTimesheets = [];

  double get todayHoursSpent {
    // Hours from Odoo timesheets logged today
    double timesheetHours = 0;
    for (final t in todayTimesheets) {
      timesheetHours += (t['unit_amount'] as num? ?? 0).toDouble();
    }
    // Add hours from any currently running timers today
    double timerHours = 0;
    final ts = TimerService.instance;
    for (final taskId in myTasks.map((t) => t['id'] as int)) {
      if (ts.isStarted(taskId)) {
        final startedAt = ts.startedAt(taskId);
        if (startedAt != null) {
          final today = DateTime.now();
          final isToday = startedAt.year == today.year &&
              startedAt.month == today.month &&
              startedAt.day == today.day;
          if (isToday) {
            // Only count seconds elapsed today (not from previous days)
            timerHours += ts.seconds(taskId) / 3600.0;
          }
        }
      }
    }
    return timesheetHours + timerHours;
  }

  /// Response time display logic (priority order):
  /// 1. Live running timer today → shows current elapsed as HH:MM:SS
  /// 2. Last completed visit duration → the duration of the most recently finished task
  /// 3. Today's timesheet hours → fallback from Odoo logged hours
  String get responseTimeDisplay {
    final ts    = TimerService.instance;
    final today = DateTime.now();

    // 1. Show currently running timer (visit in progress today)
    for (final task in myTasks) {
      final taskId = task['id'] as int;
      if (ts.isStarted(taskId) && !ts.isPaused(taskId)) {
        final startedAt = ts.startedAt(taskId);
        if (startedAt != null) {
          final isToday = startedAt.year == today.year &&
              startedAt.month == today.month &&
              startedAt.day == today.day;
          if (isToday) return ts.display(taskId); // live HH:MM:SS
        }
      }
    }

    // 2. Last completed visit duration
    final lastSecs = ts.lastVisitSeconds;
    if (lastSecs > 0) {
      final h = lastSecs ~/ 3600;
      final m = (lastSecs % 3600) ~/ 60;
      final s = lastSecs % 60;
      if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
      if (m > 0) return s > 0 ? '${m}m ${s}s' : '${m}m';
      return '${s}s';
    }

    // 3. Fallback: today's timesheet hours logged in Odoo
    final mins = (todayHoursSpentTimesheetOnly * 60).round();
    if (mins == 0) return '0m';
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  double get todayHoursSpentTimesheetOnly {
    double total = 0;
    for (final t in todayTimesheets) {
      total += (t['unit_amount'] as num? ?? 0).toDouble();
    }
    return total;
  }

  // ── Tasks contributed to response time today ────────────────────────────
  List<Map<String, dynamic>> get tasksWorkedToday {
    final Set<int> workedIds = {};
    
    for (final t in todayTimesheets) {
      final taskField = t['task_id'];
      if (taskField is List && taskField.isNotEmpty) {
        workedIds.add(taskField[0] as int);
      } else if (taskField is int) {
        workedIds.add(taskField);
      }
    }
    
    final ts = TimerService.instance;
    final today = DateTime.now();
    for (final task in myTasks) {
      final taskId = task['id'] as int;
      if (ts.isStarted(taskId)) {
        final startedAt = ts.startedAt(taskId);
        if (startedAt != null) {
          final isToday = startedAt.year == today.year &&
                          startedAt.month == today.month &&
                          startedAt.day == today.day;
          if (isToday) workedIds.add(taskId);
        }
      }
    }
    
    final filtered = myTasks.where((t) => workedIds.contains(t['id'] as int)).toList();
    filtered.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return filtered;
  }

  // ── Derived ───────────────────────────────────────────────────────────
  int get totalTasks => myTasks.length;

  int get doneTasks => myTasks.where((t) {
    final stage = t['stage_id'];
    if (stage == null || stage == false) return false;
    final name = (stage is List ? stage[1] : stage).toString().toLowerCase();
    return name.contains('done') || name.contains('complet') ||
           name.contains('closed') || name.contains('validated');
  }).length;

  bool isPortalUser    = false;
  String debugLastFetch = ''; // tracks what strategy worked
  int? get loggedUid => _loggedUid;
  OdooService? get service => _service;

  // ── Init ─────────────────────────────────────────────────────────────
  Future<int> initAndAuth({
    required String serverUrl,
    required String login,
    required String password,
  }) async {
    final svc  = OdooService(serverUrl);
    await svc.detectDatabase();
    final uid  = await svc.authenticate(login: login, password: password);
    _service   = svc;
    _loggedUid = uid;
    _startAutoRefresh();
    notifyListeners();
    return uid;
  }

  // ── Fetch tasks ───────────────────────────────────────────────────────
  Future<void> fetchMyTasks() async {
    if (_service == null || _loggedUid == null) return;
    tasksState = LoadState.loading;
    tasksError = null;
    notifyListeners();
    try {
      // Detect portal user flag (for UI info + strategy selection)
      isPortalUser = await _service!.checkIsPortalUser(_loggedUid!);

      debugLastFetch = 'portal=$isPortalUser';
      myTasks = await _service!.fetchMyTasks(_loggedUid!);
      debugLastFetch += ' → ${myTasks.length} tasks';

      // Classify tasks by fs_task_type_id.name (Many2one to fs.task.type).
      // _injectTaskTypes in odoo_service ensures this field is populated even
      // for portal users by traversing the relation server-side via dot-notation.
      periodicTasks   = myTasks.where((t) => _isType(t, 'periodic')).toList();
      emergencyTasks  = myTasks.where((t) =>
          _isType(t, 'urgent') || _isType(t, 'emergency')).toList();
      sparePartsTasks = myTasks.where((t) => _isType(t, 'spare')).toList();
      surveyTasks     = myTasks.where((t) => _isType(t, 'survey')).toList();

      // Debug: log the resolved type name for every task so mis-classification is visible
      for (final t in myTasks) {
        debugPrint('[classify] task ${t["id"]} → fs_task_type_id="${_typeName(t)}"');
      }

      final categorisedIds = {
        ...periodicTasks.map((t) => t['id']),
        ...emergencyTasks.map((t) => t['id']),
        ...sparePartsTasks.map((t) => t['id']),
        ...surveyTasks.map((t) => t['id']),
      };
      final uncategorised = myTasks
          .where((t) => !categorisedIds.contains(t['id'])).toList();

      // Uncategorised = tasks where fs_task_type_id is still null/false after inject.
      // Log them clearly — if this list is non-empty it means either:
      //   (a) the task has no type set in Odoo, or
      //   (b) _injectTaskTypes failed to resolve the type (check [inject] logs above).
      if (uncategorised.isNotEmpty) {
        debugPrint('[classify] ${uncategorised.length} uncategorised task(s) '
            '(fs_task_type_id=false) → placed in periodicTasks as default. '
            'ids: ${uncategorised.map((t) => t["id"]).toList()}');
      }
      periodicTasks = [...periodicTasks, ...uncategorised];

      debugLastFetch += ' | p=${periodicTasks.length} e=${emergencyTasks.length}'
          ' s=${sparePartsTasks.length} sv=${surveyTasks.length}'
          ' (uncat=${uncategorised.length})';

      tasksState = LoadState.loaded;
    } on OdooException catch (e) {
      tasksError = e.message;
      tasksState = LoadState.error;
    } catch (e) {
      tasksError = e.toString();
      tasksState = LoadState.error;
    }
    notifyListeners();
  }

  bool _isType(Map<String, dynamic> t, String keyword) {
    final type = t['fs_task_type_id'];
    if (type == null || type == false) return false;
    // type is [id, name] from Odoo many2one field
    final name = (type is List ? type[1] : type).toString().toLowerCase().trim();
    return name.contains(keyword.toLowerCase());
  }

  // Returns the raw type name for debugging
  String _typeName(Map<String, dynamic> t) {
    final type = t['fs_task_type_id'];
    if (type == null || type == false) return '(none)';
    return (type is List ? type[1] : type).toString();
  }

  // ── Fetch customers ───────────────────────────────────────────────────
  Future<void> fetchCustomers() async {
    if (_service == null) return;
    customersState = LoadState.loading;
    customersError = null;
    notifyListeners();
    try {
      // ── STRATEGY 1 (PRIMARY): fetch by exact partner IDs from loaded tasks ──
      // This is the ONLY reliable approach for FSM — contacts linked to field
      // service tasks often have customer_rank = 0 and are invisible to any
      // customer_rank filter.
      //
      // REQUIREMENT: fetchMyTasks() MUST be awaited before calling this method.
      // fetchAll() and initState() in task_customers_screen both guarantee this.
      final partnerIds = myTasks
          .map((t) => t['partner_id'])
          .where((p) => p is List && (p as List).isNotEmpty)
          .map((p) => (p as List)[0] as int)
          .toSet()
          .toList();

      if (partnerIds.isNotEmpty) {
        // Fetch exactly the partners we need + equipment in parallel
        final results = await Future.wait([
          _service!.fetchPartnersByIds(partnerIds),
          _service!.fetchEquipment().catchError((_) => <Map<String, dynamic>>[]),
        ]);
        customers = results[0];
        equipment = results[1];
      } else {
        // ── STRATEGY 2 (FALLBACK): no tasks loaded or tasks have no partner ──
        // Try broad fetchPartners() as a fallback.
        equipment = await _service!.fetchEquipment()
            .catchError((_) => <Map<String, dynamic>>[]);
        customers = await _service!.fetchPartners();
      }

      // ── STRATEGY 3 (SAFETY NET): if still empty, log for debugging ──
      // This means either: tasks have no partner_id set, OR the res.partner
      // records are inaccessible (permissions issue on the Odoo instance).
      // The customer list screen will show the customer name from task.partner_id
      // directly — no full partner record needed for that, only for address/phone.

      customersState = LoadState.loaded;
    } on OdooException catch (e) {
      customersError = e.message;
      customersState = LoadState.error;
    } catch (e) {
      customersError = e.toString();
      customersState = LoadState.error;
    }
    notifyListeners();
  }

  // ── Fetch spare parts ─────────────────────────────────────────────────
  Future<void> fetchSpareParts() async {
    if (_service == null) return;
    sparePartsState = LoadState.loading;
    sparePartsError = null;
    notifyListeners();
    try {
      var parts = await _service!.fetchProductsViaFSM();
      if (parts.isEmpty) parts = await _service!.fetchFieldServiceProducts();
      if (parts.isEmpty) parts = await _service!.fetchAllProducts();
      spareParts      = parts;
      sparePartsState = LoadState.loaded;
    } on OdooException catch (e) {
      sparePartsError = e.message;
      sparePartsState = LoadState.error;
    } catch (e) {
      sparePartsError = e.toString();
      sparePartsState = LoadState.error;
    }
    notifyListeners();
  }

  // ── Fetch today timesheets ─────────────────────────────────────────────
  Future<void> fetchTodayTimesheets() async {
    if (_service == null || _loggedUid == null) return;
    try {
      todayTimesheets = await _service!.fetchTodayTimesheets(_loggedUid!);
    } catch (_) {
      todayTimesheets = [];
    }
    notifyListeners();
  }

  // ── Fetch maintenance requests ─────────────────────────────────────────
  Future<void> fetchRequests() async {
    if (_service == null) return;
    requestsState = LoadState.loading;
    requestsError = null;
    notifyListeners();
    try {
      maintenanceRequests = await _service!.fetchMaintenanceRequests();
      requestsState = LoadState.loaded;
    } on OdooException catch (e) {
      requestsError = e.message;
      requestsState = LoadState.error;
    } catch (e) {
      requestsError = e.toString();
      requestsState = LoadState.error;
    }
    notifyListeners();
  }

  // ── Fetch all ─────────────────────────────────────────────────────────
  Future<void> fetchAll() async {
    // CRITICAL ORDER: tasks MUST complete before fetchCustomers runs,
    // because fetchCustomers extracts partner IDs directly from myTasks.
    await fetchMyTasks();
    await fetchCustomers();   // sequential — needs myTasks populated
    await Future.wait([
      fetchSpareParts(),
      fetchTodayTimesheets(),
      fetchRequests(),
    ]);
  }

  // ── Reset ─────────────────────────────────────────────────────────────
  void reset() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    isPortalUser    = false;
    debugLastFetch  = '';
    myTasks = []; periodicTasks = []; emergencyTasks = []; surveyTasks = [];
    sparePartsTasks = [];
    customers = []; equipment = []; spareParts = []; todayTimesheets = [];
    maintenanceRequests = [];
    tasksState      = LoadState.idle;
    customersState  = LoadState.idle;
    sparePartsState = LoadState.idle;
    surveyState     = LoadState.idle;
    requestsState   = LoadState.idle;
    tasksError      = null;
    customersError  = null;
    sparePartsError = null;
    requestsError   = null;
    _service   = null;
    _loggedUid = null;
    notifyListeners();
  }
}
