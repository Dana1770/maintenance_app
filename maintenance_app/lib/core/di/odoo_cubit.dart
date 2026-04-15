import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import './odoo_service.dart';
import './timer_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Load state enum (same as before, kept for screen compatibility)
// ─────────────────────────────────────────────────────────────────────────────

enum LoadState { idle, loading, loaded, error }

// ─────────────────────────────────────────────────────────────────────────────
// Immutable state
// ─────────────────────────────────────────────────────────────────────────────

class OdooState {
  // ── Task states ──────────────────────────────────────────────────────────
  final LoadState tasksState;
  final LoadState customersState;
  final LoadState sparePartsState;
  final LoadState surveyState;
  final LoadState requestsState;

  final String? tasksError;
  final String? customersError;
  final String? sparePartsError;
  final String? surveyError;
  final String? requestsError;

  // ── Data ─────────────────────────────────────────────────────────────────
  /// ALL tasks assigned to the logged-in user.
  final List<Map<String, dynamic>> myTasks;

  /// Classified task lists (all tasks, matching original provider behaviour).
  final List<Map<String, dynamic>> periodicTasks;
  final List<Map<String, dynamic>> emergencyTasks;
  final List<Map<String, dynamic>> surveyTasks;
  final List<Map<String, dynamic>> sparePartsTasks;

  // ── Customers + equipment ─────────────────────────────────────────────
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> equipment;

  // ── Spare parts ───────────────────────────────────────────────────────
  final List<Map<String, dynamic>> spareParts;

  // ── Maintenance requests ──────────────────────────────────────────────
  final List<Map<String, dynamic>> maintenanceRequests;

  // ── Timesheets ────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> todayTimesheets;

  // ── Misc ──────────────────────────────────────────────────────────────
  final bool   isPortalUser;
  final String debugLastFetch;

  const OdooState({
    this.tasksState      = LoadState.idle,
    this.customersState  = LoadState.idle,
    this.sparePartsState = LoadState.idle,
    this.surveyState     = LoadState.idle,
    this.requestsState   = LoadState.idle,
    this.tasksError,
    this.customersError,
    this.sparePartsError,
    this.surveyError,
    this.requestsError,
    this.myTasks              = const [],
    this.periodicTasks        = const [],
    this.emergencyTasks       = const [],
    this.surveyTasks          = const [],
    this.sparePartsTasks      = const [],
    this.customers            = const [],
    this.equipment            = const [],
    this.spareParts           = const [],
    this.maintenanceRequests  = const [],
    this.todayTimesheets      = const [],
    this.isPortalUser         = false,
    this.debugLastFetch       = '',
  });

  OdooState copyWith({
    LoadState? tasksState,
    LoadState? customersState,
    LoadState? sparePartsState,
    LoadState? surveyState,
    LoadState? requestsState,
    String?    tasksError,
    String?    customersError,
    String?    sparePartsError,
    String?    surveyError,
    String?    requestsError,
    List<Map<String, dynamic>>? myTasks,
    List<Map<String, dynamic>>? periodicTasks,
    List<Map<String, dynamic>>? emergencyTasks,
    List<Map<String, dynamic>>? surveyTasks,
    List<Map<String, dynamic>>? sparePartsTasks,
    List<Map<String, dynamic>>? customers,
    List<Map<String, dynamic>>? equipment,
    List<Map<String, dynamic>>? spareParts,
    List<Map<String, dynamic>>? maintenanceRequests,
    List<Map<String, dynamic>>? todayTimesheets,
    bool?   isPortalUser,
    String? debugLastFetch,
  }) =>
      OdooState(
        tasksState:      tasksState      ?? this.tasksState,
        customersState:  customersState  ?? this.customersState,
        sparePartsState: sparePartsState ?? this.sparePartsState,
        surveyState:     surveyState     ?? this.surveyState,
        requestsState:   requestsState   ?? this.requestsState,
        tasksError:      tasksError      ?? this.tasksError,
        customersError:  customersError  ?? this.customersError,
        sparePartsError: sparePartsError ?? this.sparePartsError,
        surveyError:     surveyError     ?? this.surveyError,
        requestsError:   requestsError   ?? this.requestsError,
        myTasks:             myTasks             ?? this.myTasks,
        periodicTasks:       periodicTasks       ?? this.periodicTasks,
        emergencyTasks:      emergencyTasks      ?? this.emergencyTasks,
        surveyTasks:         surveyTasks         ?? this.surveyTasks,
        sparePartsTasks:     sparePartsTasks     ?? this.sparePartsTasks,
        customers:           customers           ?? this.customers,
        equipment:           equipment           ?? this.equipment,
        spareParts:          spareParts          ?? this.spareParts,
        maintenanceRequests: maintenanceRequests ?? this.maintenanceRequests,
        todayTimesheets:     todayTimesheets     ?? this.todayTimesheets,
        isPortalUser:    isPortalUser    ?? this.isPortalUser,
        debugLastFetch:  debugLastFetch  ?? this.debugLastFetch,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cubit
// ─────────────────────────────────────────────────────────────────────────────

class OdooCubit extends Cubit<OdooState> {
  OdooService? _service;
  int?         _loggedUid;
  Timer?       _refreshTimer;

  OdooCubit() : super(const OdooState());

  // ── Convenience getters so screens can do cubit.myTasks etc. ────────────
  OdooService? get service    => _service;
  int?         get loggedUid  => _loggedUid;

  // Forwarded from state for ergonomic access
  List<Map<String, dynamic>> get myTasks             => state.myTasks;
  List<Map<String, dynamic>> get periodicTasks        => state.periodicTasks;
  List<Map<String, dynamic>> get emergencyTasks       => state.emergencyTasks;
  List<Map<String, dynamic>> get surveyTasks          => state.surveyTasks;
  List<Map<String, dynamic>> get sparePartsTasks      => state.sparePartsTasks;
  List<Map<String, dynamic>> get customers            => state.customers;
  List<Map<String, dynamic>> get equipment            => state.equipment;
  List<Map<String, dynamic>> get spareParts           => state.spareParts;
  List<Map<String, dynamic>> get maintenanceRequests  => state.maintenanceRequests;
  List<Map<String, dynamic>> get todayTimesheets      => state.todayTimesheets;
  bool                       get isPortalUser         => state.isPortalUser;
  String                     get debugLastFetch       => state.debugLastFetch;
  LoadState                  get tasksState           => state.tasksState;
  LoadState                  get customersState       => state.customersState;
  LoadState                  get sparePartsState      => state.sparePartsState;
  LoadState                  get requestsState        => state.requestsState;
  String?                    get tasksError           => state.tasksError;
  String?                    get customersError       => state.customersError;
  String?                    get sparePartsError      => state.sparePartsError;
  String?                    get requestsError        => state.requestsError;

  // ── Derived values ───────────────────────────────────────────────────────

  int get totalTasks => state.myTasks.length;

  int get doneTasks => state.myTasks.where((t) {
    final stage = t['stage_id'];
    if (stage == null || stage == false) return false;
    final name =
        (stage is List ? stage[1] : stage).toString().toLowerCase();
    return name.contains('done') ||
        name.contains('complet') ||
        name.contains('closed') ||
        name.contains('validated');
  }).length;

  double get todayHoursSpent {
    double timesheetHours = 0;
    for (final t in state.todayTimesheets) {
      timesheetHours += (t['unit_amount'] as num? ?? 0).toDouble();
    }
    double timerHours = 0;
    final ts = TimerService.instance;
    for (final taskId in state.myTasks.map((t) => t['id'] as int)) {
      if (ts.isStarted(taskId)) {
        final startedAt = ts.startedAt(taskId);
        if (startedAt != null) {
          final today = DateTime.now();
          final isToday = startedAt.year == today.year &&
              startedAt.month == today.month &&
              startedAt.day == today.day;
          if (isToday) timerHours += ts.seconds(taskId) / 3600.0;
        }
      }
    }
    return timesheetHours + timerHours;
  }

  double get todayHoursSpentTimesheetOnly {
    double total = 0;
    for (final t in state.todayTimesheets) {
      total += (t['unit_amount'] as num? ?? 0).toDouble();
    }
    return total;
  }

  String get responseTimeDisplay {
    final ts    = TimerService.instance;
    final today = DateTime.now();

    for (final task in state.myTasks) {
      final taskId = task['id'] as int;
      if (ts.isStarted(taskId) && !ts.isPaused(taskId)) {
        final startedAt = ts.startedAt(taskId);
        if (startedAt != null) {
          final isToday = startedAt.year == today.year &&
              startedAt.month == today.month &&
              startedAt.day == today.day;
          if (isToday) return ts.display(taskId);
        }
      }
    }

    final lastSecs = ts.lastVisitSeconds;
    if (lastSecs > 0) {
      final h = lastSecs ~/ 3600;
      final m = (lastSecs % 3600) ~/ 60;
      final s = lastSecs % 60;
      if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
      if (m > 0) return s > 0 ? '${m}m ${s}s' : '${m}m';
      return '${s}s';
    }

    final mins = (todayHoursSpentTimesheetOnly * 60).round();
    if (mins == 0) return '0m';
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  List<Map<String, dynamic>> get tasksWorkedToday {
    final Set<int> workedIds = {};

    for (final t in state.todayTimesheets) {
      final taskField = t['task_id'];
      if (taskField is List && taskField.isNotEmpty) {
        workedIds.add(taskField[0] as int);
      } else if (taskField is int) {
        workedIds.add(taskField);
      }
    }

    final ts    = TimerService.instance;
    final today = DateTime.now();
    for (final task in state.myTasks) {
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

    final filtered =
        state.myTasks.where((t) => workedIds.contains(t['id'] as int)).toList();
    filtered.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return filtered;
  }

  // ── Init & auth ──────────────────────────────────────────────────────────

  Future<int> initAndAuth({
    required String serverUrl,
    required String login,
    required String password,
  }) async {
    final svc = OdooService(serverUrl);
    await svc.detectDatabase();
    final uid    = await svc.authenticate(login: login, password: password);
    _service     = svc;
    _loggedUid   = uid;
    _startAutoRefresh();
    return uid;
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_service != null && _loggedUid != null) fetchMyTasks();
    });
  }

  // ── Fetch tasks ──────────────────────────────────────────────────────────

  Future<void> fetchMyTasks() async {
    if (_service == null || _loggedUid == null) return;

    emit(state.copyWith(
      tasksState: LoadState.loading,
      tasksError: null,
    ));

    try {
      final isPortal =
          await _service!.checkIsPortalUser(_loggedUid!);
      var debug = 'portal=$isPortal';

      final all = await _service!.fetchMyTasks(_loggedUid!);
      debug += ' → ${all.length} tasks';

      // ── Classify from ALL tasks (matching original provider behaviour) ─
      final periodic   = all.where((t) =>
          _isTypeAny(t, ['periodic', 'دوري', 'دورية', 'periodic maintenance', 'صيانة دورية'])).toList();
      final emergency  = all.where((t) =>
          _isTypeAny(t, ['urgent', 'emergency', 'طارئ', 'طوارئ', 'عاجل']) ||
          _isHighPriority(t)).toList();
      final spareParts = all.where((t) =>
          _isTypeAny(t, ['spare', 'قطع', 'spare parts'])).toList();
      final survey     = all.where((t) =>
          _isTypeAny(t, ['survey', 'satisfaction', 'استبيان'])).toList();

      for (final t in all) {
        print('[classify] task ${t["id"]} → fs_task_type_id="${_typeName(t)}"');
      }

      final categorisedIds = {
        ...periodic.map((t) => t['id']),
        ...emergency.map((t) => t['id']),
        ...spareParts.map((t) => t['id']),
        ...survey.map((t) => t['id']),
      };
      final uncategorised =
          all.where((t) => !categorisedIds.contains(t['id'])).toList();

      if (uncategorised.isNotEmpty) {
        print('[classify] ${uncategorised.length} uncategorised task(s) '
            '(fs_task_type_id=false) → NOT placed in any category. '
            'ids: ${uncategorised.map((t) => t["id"]).toList()}');
      }

      debug +=
          ' | p=${periodic.length} e=${emergency.length}'
          ' s=${spareParts.length} sv=${survey.length}'
          ' (uncat=${uncategorised.length})';

      emit(state.copyWith(
        tasksState:      LoadState.loaded,
        isPortalUser:    isPortal,
        debugLastFetch:  debug,
        myTasks:         all,
        periodicTasks:   periodic,
        emergencyTasks:  emergency,
        sparePartsTasks: spareParts,
        surveyTasks:     survey,
      ));
    } on OdooException catch (e) {
      emit(state.copyWith(
          tasksState: LoadState.error, tasksError: e.message));
    } catch (e) {
      emit(state.copyWith(
          tasksState: LoadState.error, tasksError: e.toString()));
    }
  }

  // ── Fetch customers ──────────────────────────────────────────────────────

  Future<void> fetchCustomers() async {
    if (_service == null) return;

    emit(state.copyWith(
      customersState: LoadState.loading,
      customersError: null,
    ));

    try {
      final partnerIds = state.myTasks
          .map((t) => t['partner_id'])
          .where((p) => p is List && (p as List).isNotEmpty)
          .map((p) => (p as List)[0] as int)
          .toSet()
          .toList();

      List<Map<String, dynamic>> newCustomers;
      List<Map<String, dynamic>> newEquipment;

      if (partnerIds.isNotEmpty) {
        final results = await Future.wait([
          _service!.fetchPartnersByIds(partnerIds),
          _service!.fetchEquipment().catchError(
              (_) => <Map<String, dynamic>>[]),
        ]);
        newCustomers = results[0];
        newEquipment = results[1];
      } else {
        newEquipment = await _service!
            .fetchEquipment()
            .catchError((_) => <Map<String, dynamic>>[]);
        newCustomers = await _service!.fetchPartners();
      }

      emit(state.copyWith(
        customersState: LoadState.loaded,
        customers:      newCustomers,
        equipment:      newEquipment,
      ));
    } on OdooException catch (e) {
      emit(state.copyWith(
          customersState: LoadState.error, customersError: e.message));
    } catch (e) {
      emit(state.copyWith(
          customersState: LoadState.error, customersError: e.toString()));
    }
  }

  // ── Fetch spare parts ────────────────────────────────────────────────────

  Future<void> fetchSpareParts() async {
    if (_service == null) return;

    emit(state.copyWith(
      sparePartsState: LoadState.loading,
      sparePartsError: null,
    ));

    try {
      var parts = await _service!.fetchProductsViaFSM();
      if (parts.isEmpty) parts = await _service!.fetchFieldServiceProducts();
      if (parts.isEmpty) parts = await _service!.fetchAllProducts();

      emit(state.copyWith(
        sparePartsState: LoadState.loaded,
        spareParts:      parts,
      ));
    } on OdooException catch (e) {
      emit(state.copyWith(
          sparePartsState: LoadState.error, sparePartsError: e.message));
    } catch (e) {
      emit(state.copyWith(
          sparePartsState: LoadState.error, sparePartsError: e.toString()));
    }
  }

  // ── Fetch today timesheets ───────────────────────────────────────────────

  Future<void> fetchTodayTimesheets() async {
    if (_service == null || _loggedUid == null) return;
    try {
      final sheets = await _service!.fetchTodayTimesheets(_loggedUid!);
      emit(state.copyWith(todayTimesheets: sheets));
    } catch (_) {
      emit(state.copyWith(todayTimesheets: []));
    }
  }

  // ── Fetch maintenance requests ───────────────────────────────────────────

  Future<void> fetchRequests() async {
    if (_service == null) return;

    emit(state.copyWith(
      requestsState: LoadState.loading,
      requestsError: null,
    ));

    try {
      final reqs = await _service!.fetchMaintenanceRequests();
      emit(state.copyWith(
        requestsState:       LoadState.loaded,
        maintenanceRequests: reqs,
      ));
    } on OdooException catch (e) {
      emit(state.copyWith(
          requestsState: LoadState.error, requestsError: e.message));
    } catch (e) {
      emit(state.copyWith(
          requestsState: LoadState.error, requestsError: e.toString()));
    }
  }

  // ── Fetch all ────────────────────────────────────────────────────────────

  Future<void> fetchAll() async {
    await fetchMyTasks();
    await fetchCustomers(); // sequential — needs myTasks populated
    await Future.wait([
      fetchSpareParts(),
      fetchTodayTimesheets(),
      fetchRequests(),
    ]);
  }

  // ── Reset ────────────────────────────────────────────────────────────────

  void reset() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _service      = null;
    _loggedUid    = null;
    emit(const OdooState());
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  bool _isType(Map<String, dynamic> t, String keyword) {
    final type = t['fs_task_type_id'];
    if (type == null || type == false) return false;
    final name =
        (type is List ? type[1] : type).toString().toLowerCase().trim();
    return name.contains(keyword.toLowerCase());
  }

  // Match against multiple keywords (Arabic + English)
  bool _isTypeAny(Map<String, dynamic> t, List<String> keywords) {
    final type = t['fs_task_type_id'];
    if (type == null || type == false) return false;
    final name =
        (type is List ? type[1] : type).toString().toLowerCase().trim();
    return keywords.any((kw) => name.contains(kw.toLowerCase()));
  }

  // Odoo priority '1' = urgent/high — treat as emergency fallback
  bool _isHighPriority(Map<String, dynamic> t) {
    final p = t['priority'];
    if (p == null || p == false) return false;
    return p.toString() == '1';
  }

  String _typeName(Map<String, dynamic> t) {
    final type = t['fs_task_type_id'];
    if (type == null || type == false) return '(none)';
    return (type is List ? type[1] : type).toString();
  }

  @override
  Future<void> close() {
    _refreshTimer?.cancel();
    return super.close();
  }
}
