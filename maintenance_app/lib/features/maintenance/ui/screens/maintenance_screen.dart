import 'dart:async';
import 'dart:typed_data';
import 'dart:math' show asin, cos, pi, sin, sqrt;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/di/timer_service.dart';
import '../../../spare_parts/ui/screens/task_spare_parts_screen.dart';
import '../../../signature/ui/screens/signature_screen.dart';

class MaintenanceScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  final String maintenanceId;
  final String customerName;
  final String location;
  final String serialNumber;

  const MaintenanceScreen({
    super.key,
    required this.task,
    this.maintenanceId = '#0',
    this.customerName  = '',
    this.location      = '',
    this.serialNumber  = '',
  });

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late final int _taskId;
  late final TimerService _ts;

  bool _checkingOdoo = true;
  bool _startingVisit = false;

  bool _justCompleted = false;

  String _descriptionHtml = '';

  String? _worksheetModel;         
  String? _worksheetTaskField;     
  int?    _worksheetRecordId;      
  Map<String, dynamic>  _worksheetFieldDefs = {}; 
  Map<String, dynamic>  _worksheetValues    = {}; 
  final Map<String, TextEditingController> _worksheetCtrls = {};
  bool _loadingWorksheet = false;

  Map<String, bool> _checks = {};

  final _notesCtrl    = TextEditingController();
  final _feedbackCtrl = TextEditingController();

  // ── Signature state ──────────────────────────────────────────────────────
  Uint8List? _signatureBytes;        // captured PNG bytes (in-memory)
  bool       _signatureUploaded = false;  // successfully saved to Odoo
  bool       _uploadingSignature = false;
  String?    _signatureDate;         // from Odoo if already signed
  Timer? _notesDebounce; 

  List<Map<String, dynamic>> _taskMaterials = [];
  bool _loadingMaterials = false;

  // ── Prevents double-tap on COMPLETE button ──────────────────────────────
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _taskId = widget.task['id'] as int;
    _ts     = TimerService.instance;
    
    _ts.registerOdooSync(_odooSync);
    
    _notesCtrl.addListener(() {
      _notesDebounce?.cancel();
      _notesDebounce = Timer(const Duration(seconds: 2), _saveWorksheetToOdoo);
    });
    _init();
  }

  @override
  void dispose() {
    
    _ts.registerOdooSync(null);
    _notesDebounce?.cancel();
    _notesCtrl.dispose();
    _feedbackCtrl.dispose();
    for (final c in _worksheetCtrls.values) c.dispose();
    super.dispose();
  }

  Future<int?> _odooSync(int taskId, int localSeconds) async {
    if (!mounted) return null;
    final odoo = context.read<OdooCubit>();
    if (odoo.service == null) return null;

    try {
      final info = await odoo.service!.fetchTaskTimingInfo(taskId);
      if (info == null) return null;

      final stageInfo = info['stage_id'];
      if (stageInfo is List && stageInfo.length > 1) {
        final stageName = stageInfo[1].toString().toLowerCase();
        final isFsmValidated =
            stageName.contains('validated') ||
            stageName.contains('تنفيذ')    ||
            stageName.contains('منجز');
        if (isFsmValidated) {
          if (_ts.isStarted(taskId)) {
            _ts.stopTimer(taskId);
            if (mounted) setState(() {});
          }
          return null;
        }
      }

      final timerStartStr = _strOrNull(info['timer_start']);
      final isOdooPaused     = info['is_paused']        == true;
      final hasActiveSession = info['has_active_session'] == true;
      final pausedSeconds    = (info['paused_seconds'] as num?)?.toDouble() ?? 0.0;

      if (timerStartStr != null) {
        
        _ts.clearUserPaused(taskId);
        final dt = _parseOdooUtc(timerStartStr);
        if (dt != null) {
          final secs = ((DateTime.now().difference(dt).inMilliseconds + 500) ~/ 1000)
              .clamp(0, 86400 * 30);
          _odooTimerStart = dt;
          _ts.forceApplyOdooTimer(taskId,
              seedSeconds: secs, startedAt: dt, odooTimerStart: dt);
          return secs;
        }
      } else if (hasActiveSession && isOdooPaused) {
        
        if (_ts.isStarted(taskId) && !_ts.isPaused(taskId)) {
          _ts.pause(taskId);
        }
        return pausedSeconds.round();
      } else if (!hasActiveSession && _ts.isStarted(taskId) && !_ts.isPaused(taskId)) {
        
        _ts.pause(taskId);
        if (mounted) setState(() {});
      }

    } catch (_) {}
    return null;
  }
  
  Map<String, dynamic>? _odooTimerInfo;

  DateTime? _parseOdooUtc(String s) {
    try {
      var n = s.trim().replaceFirst(' ', 'T');
      if (!n.contains('+') && !n.toUpperCase().endsWith('Z')) n += 'Z';
      return DateTime.parse(n).toLocal();
    } catch (_) { return null; }
  }

  Future<void> _init() async {

    if (_ts.isStarted(_taskId) && !_ts.isPaused(_taskId)) {
      if (mounted) setState(() => _checkingOdoo = false);
      _loadWorksheet();
      _loadMaterials();
      return;
    }

    final odoo    = context.read<OdooCubit>();
    final service = odoo.service;

    if (service != null) {
      try {

        final info = await service.fetchTaskTimingInfo(_taskId);

        if (info != null && mounted) {
          _odooTimerInfo = info;
          final stageInfo = info['stage_id'];
          if (stageInfo is List && stageInfo.length > 1) {
            final stageName = stageInfo[1].toString().toLowerCase();
            
            final isFsmValidated =
                stageName.contains('validated') ||
                stageName.contains('تنفيذ')    ||
                stageName.contains('منجز');
            if (isFsmValidated) {
              _ts.startPollingOnly(_taskId);
              if (mounted) setState(() => _checkingOdoo = false);
              _loadWorksheet();
              _loadMaterials();
              return;}}

          final timerStartStr = _strOrNull(info['timer_start']);
          
          final totalHoursSpent = (info['total_hours_spent'] as num?)?.toDouble() ?? 0.0;
          final pausedSeconds   = (info['paused_seconds']   as num?)?.toDouble() ?? 0.0;
          final isOdooPaused    = info['is_paused'] == true;
          final hasActiveSession = info['has_active_session'] == true;

          if (timerStartStr != null) {
            
            _ts.clearUserPaused(_taskId);
            final dt = _parseOdooUtc(timerStartStr);
            if (dt != null) {
              final sessionSecs = ((DateTime.now().difference(dt).inMilliseconds + 500) ~/ 1000).clamp(0, 86400 * 30);
              _odooTimerStart = dt;
              _ts.forceApplyOdooTimer(_taskId,
                  seedSeconds: sessionSecs, startedAt: dt, odooTimerStart: dt);
              _hadPreviousTime = true;
            }
          } else if (hasActiveSession && isOdooPaused) {
            
            final pausedSecs = pausedSeconds.round();
            if (pausedSecs > 0) _hadPreviousTime = true;
            _ts.startTimerPaused(_taskId, seedSeconds: pausedSecs);
          } else {
            
            _ts.startPollingOnly(_taskId);
          }
        }
      } catch (e) {
        debugPrint('[MaintenanceScreen] _init error: $e');
        _ts.startPollingOnly(_taskId); 
      }
    }

    if (mounted) setState(() => _checkingOdoo = false);
    _loadWorksheet();
    _loadMaterials();
    _checkExistingSignature();

    // ── Fetch geofence radius for this task's partner ───────────────────────
    try {
      final odoo = context.read<OdooCubit>();
      final loc = await odoo.service?.fetchTaskLocation(_taskId);
      if (loc != null && loc['restriction_m'] != null) {
        final r = loc['restriction_m'];
        if (mounted) setState(() => _restrictionMetres = (r as num).toInt());
        print('[MaintenanceScreen] restriction_m=$_restrictionMetres');
      }
    } catch (_) {}
  }

  String? _strOrNull(dynamic v) {
    if (v == null || v == false || v.toString().isEmpty) return null;
    return v.toString();
  }

  String _stageName(dynamic stageField) {
    if (stageField == null || stageField == false) return '';
    return (stageField is List ? stageField[1] : stageField).toString();
  }

  bool _hadPreviousTime = false;

  double _accumulatedHours = 0.0;

  DateTime? _odooTimerStart;

  static const int _minTimerSeconds = 15;
  bool _isTaskCompleted() {
    
    if (_justCompleted) return true;

    final stage = widget.task['stage_id'];
    if (stage == null || stage == false) return false;

    final stageName = (stage is List ? stage[1] : stage).toString().toLowerCase();
    return stageName.contains('validated') ||
        stageName.contains('تنفيذ')       ||
        stageName.contains('منجز');
  }
  void _showNoLocationDialog(String? message) {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.location_off, color: Colors.red, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(l.t('no_location_title'),
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700,
                  color: AppTheme.textDark))),
        ]),
        content: Text(
          message?.isNotEmpty == true ? message! : l.t('no_location_body'),
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.t('location_ok'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w600,
                    color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _startVisit() async {
    if (_isTaskCompleted()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            AppLocalizations.of(context).t('task_already_completed'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      return;
    }

    // FIX: removed duplicate guard+setState. The second guard returned early
    // without resetting _startingVisit=false, permanently freezing the Start button.
    if (_ts.isStarted(_taskId) && !_ts.isPaused(_taskId)) return;
    setState(() => _startingVisit = true);

    final odoo = context.read<OdooCubit>();
    bool odooOk = false;

    if (odoo.service != null) {
      for (int attempt = 0; attempt < 3 && !odooOk; attempt++) {
        try {
          if (_hadPreviousTime || _ts.isPaused(_taskId)) {
            odooOk = await odoo.service!.resumeTask(_taskId);
          } else {
            // Get current GPS position to send with the request
            final pos = await _getCurrentPosition();
            // Use startTaskResult so we can detect no_location / outside_geofence
            final res = await odoo.service!.startTaskResult(
              _taskId,
              userLat: pos?.latitude,
              userLng: pos?.longitude,
            );
            if (res['error'] == 'no_location') {
              if (mounted) setState(() => _startingVisit = false);
              await _handleNoLocationFromServer(isStart: true);
              return;
            }
            if (res['error'] == 'outside_geofence') {
              if (mounted) setState(() => _startingVisit = false);
              final distM   = (res['distance_m'] as num?)?.toDouble() ?? 0;
              final limM    = (res['restriction_m'] as num?)?.toInt() ?? _restrictionMetres;
              final isKm    = distM >= 1000;
              final distStr = isKm ? (distM / 1000).toStringAsFixed(1) : distM.toStringAsFixed(0);
              final unit    = isKm ? 'km' : 'm';
              _showCompleteLocationWarning(
                title: 'Too Far from Customer',
                message: 'You are ${distStr}${unit} away. You must be within ${limM}m to start this task.',
                customerLat: null, customerLng: null,
              );
              return;
            }
            odooOk = res['success'] == true;
          }
        } catch (_) {
          if (attempt < 2) await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (odooOk) {
        try {
          
          await Future.delayed(const Duration(milliseconds: 300));
          Map<String, dynamic>? info = await odoo.service!.fetchTaskTimingInfo(_taskId);

          if (info != null && _strOrNull(info['timer_start']) == null) {
            await Future.delayed(const Duration(milliseconds: 300));
            info = await odoo.service!.fetchTaskTimingInfo(_taskId);
          }

          final timerStartStr = info != null ? _strOrNull(info['timer_start']) : null;
          if (timerStartStr != null) {
            final dt = _parseOdooUtc(timerStartStr);
            if (dt != null) {
              final secs = ((DateTime.now().difference(dt).inMilliseconds + 500) ~/ 1000).clamp(0, 86400 * 30);
              _odooTimerStart = dt;
              
              _ts.clearUserPaused(_taskId);
              _ts.forceApplyOdooTimer(_taskId,
                  seedSeconds: secs, startedAt: dt, odooTimerStart: dt);
              _hadPreviousTime = true;
              if (mounted) setState(() => _startingVisit = false);
              return;
            }
          }
        } catch (_) {}

        _odooTimerStart = DateTime.now();
        if (_ts.isPaused(_taskId)) {
          _ts.resume(_taskId);
        } else {
          _ts.startTimer(_taskId, seedSeconds: 0);
        }
        if (mounted) setState(() => _startingVisit = false);
        return;
      }
    }

    if (odoo.service != null && odoo.service!.isPortalUser) {
      
      try {
        final info = await odoo.service!.fetchTaskTimingInfo(_taskId);
        if (info != null) {
          final totalHours = (info['total_hours_spent'] as num?)?.toDouble() ?? 0.0;
          if (totalHours > _accumulatedHours) _accumulatedHours = totalHours;

          final timerStartStr = _strOrNull(info['timer_start']);
          if (timerStartStr != null) {
            
            final dt = _parseOdooUtc(timerStartStr);
            if (dt != null) {
              final secs = ((DateTime.now().difference(dt).inMilliseconds + 500) ~/ 1000).clamp(0, 86400 * 30);
              _odooTimerStart = dt;
              _ts.forceApplyOdooTimer(_taskId, seedSeconds: secs, startedAt: dt);
              _hadPreviousTime = true;
              if (mounted) setState(() => _startingVisit = false);
              return;
            }
          }
        }
      } catch (_) {}
      
      if (mounted) setState(() => _startingVisit = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Could not start timer on server. Check your connection and try again.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      return;
    }

    if (_ts.isPaused(_taskId)) {
      _ts.resume(_taskId);
    } else {
      _ts.startTimer(_taskId, seedSeconds: 0);
    }
    if (mounted) setState(() => _startingVisit = false);
  }

  bool _pausingVisit = false;

  // ── Geofence radius fetched from server (res.partner.restriction_m) ────
  // 0 = no restriction. Loaded once in _init() via fetchTaskLocation.
  int _restrictionMetres = 0;

  Future<void> _pauseVisit() async {
    if (_isTaskCompleted()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'This task is already completed.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
      return;
    }

    if (_pausingVisit) return;
    final elapsed = _ts.seconds(_taskId);
    if (elapsed < _minTimerSeconds) return;

    setState(() => _pausingVisit = true);

    final odoo  = context.read<OdooCubit>();
    bool odooOk = false;

    if (odoo.service != null) {
      odooOk = await odoo.service!.pauseTask(_taskId);
    }

    if (odooOk) {
      
      _ts.pause(_taskId);
      _hadPreviousTime = true;
      _odooTimerStart  = null;
    } else {
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Could not pause timer on server. Please try again.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }

    if (mounted) setState(() => _pausingVisit = false);
  }

  Future<void> _resumeVisit() async {
    if (_isTaskCompleted()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'This task is already completed.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
      return;
    }

    _hadPreviousTime = true;
    await _startVisit();
  }

  Future<void> _loadWorksheet() async {
    if (!mounted) return;
    setState(() => _loadingWorksheet = true);
    final odoo = context.read<OdooCubit>();
    if (odoo.service == null) {
      if (mounted) setState(() => _loadingWorksheet = false);
      return;
    }

    await Future.wait([
      _loadWorksheetFields(odoo),
      _loadDescriptionGuide(odoo),
    ]);

    if (mounted) setState(() => _loadingWorksheet = false);
  }

  Future<void> _loadWorksheetFields(OdooCubit odoo) async {
    if (odoo.service == null) {
      return;
    }
    try {
      final result = await odoo.service!.fetchWorksheetForTask(
        _taskId,
        onDebug: (_) {},
      );
      if (result != null && mounted) {
        final fieldDefs = result['fields'] as Map<String, dynamic>;
        final record    = result['record'] as Map<String, dynamic>?;
        final model     = result['model'] as String;
        final taskField = result['taskField'] as String;

        for (final key in fieldDefs.keys) {
          final def   = fieldDefs[key] as Map?;
          final ftype = def?['type']?.toString() ?? 'char';
          final val   = record?[key];
          if (ftype == 'boolean') continue;
          final text = (val == null || val == false) ? '' : val.toString();
          if (!_worksheetCtrls.containsKey(key)) {
            _worksheetCtrls[key] = TextEditingController();
          }
          _worksheetCtrls[key]!.text = text;
        }

        if (mounted) setState(() {
          _worksheetModel     = model;
          _worksheetTaskField = taskField;
          _worksheetRecordId  = record?['id'] as int?;
          _worksheetFieldDefs = fieldDefs;
          _worksheetValues    = record != null
              ? Map<String, dynamic>.from(record) : {};
        });
      } else {
        if (mounted) setState(() {
        });
      }
    } catch (e) {
    }
  }

  Future<void> _loadDescriptionGuide(OdooCubit odoo) async {
    try {
      final tasks = await odoo.service!.searchRead(
        model: 'project.task',
        domain: [['id', '=', _taskId]],
        fields: ['id', 'description'],
        limit: 1,
      );
      if (tasks.isNotEmpty && mounted) {
        final raw = tasks.first['description'];
        final html = (raw == null || raw == false) ? '' : raw.toString();
        if (html.isNotEmpty && mounted) {
          setState(() => _descriptionHtml = html);
        }
      }
    } catch (_) {}
  }

  List<Map<String, String>> _parseDescriptionToSteps(String html) {
    if (html.trim().isEmpty) return [];

    final structuredSteps = <Map<String, String>>[];
    final hLiRe = RegExp(r'<(h[1-3]|li)[^>]*>(.*?)<\/\1>',
        caseSensitive: false, dotAll: true);
    final pRe   = RegExp(r'<p[^>]*>(.*?)<\/p>',
        caseSensitive: false, dotAll: true);

    String stripInner(String s) => s
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    for (final m in hLiRe.allMatches(html)) {
      final title = stripInner(m.group(2) ?? '');
      if (title.length > 3) structuredSteps.add({'title': title, 'body': ''});
    }
    if (structuredSteps.isNotEmpty) return structuredSteps;

    String text = html
        .replaceAllMapped(pRe, (m) => '\n${m.group(1)}\n')
        .replaceAll(RegExp(r'<br\s*\/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');

    final allLines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (allLines.isEmpty) return [];

    final numberedRe = RegExp(r'^\d+[\.\)]\s+(.+)$');
    final numbered   = <Map<String, String>>[];
    String? curTitle;
    final bodyBuf = StringBuffer();

    void flush() {
      if (curTitle != null && curTitle!.length > 3) {
        numbered.add({'title': curTitle!, 'body': bodyBuf.toString().trim()});
      }
      bodyBuf.clear();
      curTitle = null;
    }

    for (final line in allLines) {
      final m = numberedRe.firstMatch(line);
      if (m != null) {
        flush();
        curTitle = m.group(1)!;
      } else if (curTitle != null) {
        if (bodyBuf.isNotEmpty) bodyBuf.write(' ');
        bodyBuf.write(line);
      }
    }
    flush();
    if (numbered.isNotEmpty) return numbered;

    final paragraph = allLines.join(' ');
    final sentenceRe = RegExp(r'(?<=[.!?])\s+');
    final sentences  = paragraph
        .split(sentenceRe)
        .map((s) => s.trim())
        .where((s) => s.length > 10)
        .toList();

    if (sentences.isNotEmpty) {
      
      if (sentences.length == 1) {
        return [{'title': sentences.first, 'body': ''}];
      }
      
      return sentences.map((s) => {'title': s, 'body': ''}).toList();
    }

    if (paragraph.length > 5) {
      return [{'title': paragraph, 'body': ''}];
    }

    return [];
  }

  Future<void> _loadMaterials() async {
    if (!mounted) return;
    setState(() => _loadingMaterials = true);
    final odoo = context.read<OdooCubit>();
    if (odoo.service == null) {
      if (mounted) setState(() => _loadingMaterials = false);
      return;
    }
    try {
      final mats = await odoo.service!.fetchFSMMaterials(_taskId);
      if (mounted) setState(() { _taskMaterials = mats; _loadingMaterials = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingMaterials = false);
    }
  }

  int    get _completedChecks => _checks.values.where((v) => v).length;
  Future<void> _saveWorksheetToOdoo() async {
    final odoo = context.read<OdooCubit>();
    if (odoo.service == null) return;

    if (_worksheetModel != null && _worksheetTaskField != null) {
      final values = <String, dynamic>{};
      _worksheetCtrls.forEach((key, ctrl) {
        final def   = _worksheetFieldDefs[key] as Map?;
        final ftype = def?['type']?.toString() ?? 'char';
        final text  = ctrl.text.trim();
        if (ftype == 'integer') {
          values[key] = int.tryParse(text) ?? 0;
        } else if (ftype == 'float' || ftype == 'monetary') {
          values[key] = double.tryParse(text) ?? 0.0;
        } else {
          values[key] = text;
        }
      });
      _worksheetFieldDefs.forEach((key, defRaw) {
        final ftype = (defRaw as Map?)?['type']?.toString() ?? '';
        if (ftype == 'boolean') {
          values[key] = _worksheetValues[key] == true;
        } else if (ftype == 'selection' && _worksheetValues.containsKey(key)) {
          values[key] = _worksheetValues[key];
        }
      });
      if (values.isNotEmpty) {
        try {
          await odoo.service!.saveWorksheetValues(
            model: _worksheetModel!,
            taskField: _worksheetTaskField!,
            taskId: _taskId,
            values: values,
            existingRecordId: _worksheetRecordId,
          );
        } catch (_) {}
      }
      return;
    }

    if (_checks.isNotEmpty) {
      try {
        await odoo.service!.saveWorksheet(
          taskId: _taskId,
          checks: _checks,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } catch (_) {}
    }
  }

  double _distanceMetres(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * asin(sqrt(a));
  }

  ({double lat, double lng})? _latLngFromUrl(String url) {
    final patterns = [
      RegExp(r'[?&]q=(-?[\d.]+),(-?[\d.]+)'),
      RegExp(r'[?&]ll=(-?[\d.]+),(-?[\d.]+)'),
      RegExp(r'/@(-?[\d.]+),(-?[\d.]+)'),
      RegExp(r'[?&]center=(-?[\d.]+),(-?[\d.]+)'),
      RegExp(r'maps/place/[^/]*/(-?[\d.]+),(-?[\d.]+)'),
      RegExp(r'!3d(-?[\d.]+)!4d(-?[\d.]+)'),
      RegExp(r'maps\?q=(-?[\d.]+)%2C(-?[\d.]+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) {
        final lat = double.tryParse(m.group(1)!);
        final lng = double.tryParse(m.group(2)!);
        if (lat != null && lng != null && lat.abs() > 0.0001 && lng.abs() > 0.0001) {
          return (lat: lat, lng: lng);
        }
      }
    }
    return null;
  }

  void _showCompleteLocationWarning({
    required String title,
    required String message,
    required double? customerLat,
    required double? customerLng,
    String? manualLink,
    bool allowProceed = false,
    VoidCallback? onProceed,
  }) {
    final l = AppLocalizations.of(context);

    // Prefer coords-based directions; fall back to raw manual link
    final String? mapsUrl;
    if (customerLat != null && customerLng != null) {
      mapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$customerLat,$customerLng';
    } else if (manualLink != null && manualLink.isNotEmpty) {
      mapsUrl = manualLink;
    } else {
      mapsUrl = null;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Icon(Icons.location_off, color: Colors.orange, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: AppTheme.textDark)),
          ),
        ]),
        content: Text(message,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppTheme.textGrey, height: 1.5)),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('cancel'),
                style: GoogleFonts.inter(color: AppTheme.textGrey)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mapsUrl != null)
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await launchUrl(Uri.parse(mapsUrl!),
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  icon: const Icon(Icons.navigation, color: Colors.white, size: 16),
                  label: Text(l.t('open_in_maps'),
                      style: GoogleFonts.inter(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              if (allowProceed && onProceed != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onProceed();
                  },
                  child: Text('Proceed',
                      style: GoogleFonts.inter(
                          color: Colors.orange, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Handle no_location from server: GPS check if any location exists ──────
  // isStart = true  → if proximity passes, force-start via ORM bypass.
  // isStart = false → if proximity passes, retry _completeMaintenance().
  Future<void> _handleNoLocationFromServer({required bool isStart}) async {
    final l = AppLocalizations.of(context);

    // Always work with fresh data — the manual link may have just been added.
    final freshTask = await _fetchFreshTaskData();
    final task = freshTask ?? widget.task;

    // Resolve partner location from OdooCubit's cached customers
    _resolvePartnerLocationFromCache(task);

    String _str(dynamic v) {
      if (v == null || v == false) return '';
      final s = v.toString().trim();
      return s == 'false' ? '' : s;
    }

    // ── DEBUG: print everything we have at this point ─────────────────
    debugPrint('════════════════════════════════════════════════════════');
    debugPrint('[LOC-DEBUG] task_id=$_taskId  isStart=$isStart');
    debugPrint('[LOC-DEBUG] widget.task[partner_id]      = ${widget.task['partner_id']}');
    debugPrint('[LOC-DEBUG] widget.task[google_map_link_manual] = ${widget.task['google_map_link_manual']}');
    debugPrint('[LOC-DEBUG] widget.task[partner_latitude]= ${widget.task['partner_latitude']}');
    debugPrint('[LOC-DEBUG] widget.task[partner_longitude]=${widget.task['partner_longitude']}');
    debugPrint('[LOC-DEBUG] freshTask null? ${freshTask == null}');
    if (freshTask != null) {
      debugPrint('[LOC-DEBUG] freshTask[google_map_link_manual] = ${freshTask['google_map_link_manual']}');
      debugPrint('[LOC-DEBUG] freshTask[partner_latitude]       = ${freshTask['partner_latitude']}');
      debugPrint('[LOC-DEBUG] freshTask[partner_longitude]      = ${freshTask['partner_longitude']}');
    }
    debugPrint('════════════════════════════════════════════════════════');

    // FIX: three-layer fallback for manual link:
    // 1. freshTask (already has fetchTaskLocation data baked in)
    // 2. widget.task (loaded at login — may be stale if link was added later)
    // 3. Direct fetchTaskLocation call — last resort for stale-cache cases
    String manualLink = _str(task['google_map_link_manual']).isNotEmpty
        ? _str(task['google_map_link_manual'])
        : _str(widget.task['google_map_link_manual']);

    debugPrint('[LOC-DEBUG] manualLink after layers 1&2: "$manualLink"');

    if (manualLink.isEmpty) {
      debugPrint('[LOC-DEBUG] manualLink still empty → calling fetchTaskLocation directly...');
      try {
        final odoo = context.read<OdooCubit>();
        final loc = await odoo.service?.fetchTaskLocation(_taskId);
        debugPrint('[LOC-DEBUG] fetchTaskLocation raw response: $loc');
        if (loc != null) {
          final v = _str(loc['google_map_link_manual']);
          debugPrint('[LOC-DEBUG] fetchTaskLocation[google_map_link_manual] = "$v"');
          if (v.isNotEmpty) {
            manualLink = v;
            task['google_map_link_manual'] = v;
            debugPrint('[LOC-DEBUG] manualLink resolved via direct fetchTaskLocation: $v');
          }
        } else {
          debugPrint('[LOC-DEBUG] fetchTaskLocation returned NULL (network/auth error?)');
        }
      } catch (e) {
        debugPrint('[LOC-DEBUG] fetchTaskLocation fallback error: $e');
      }
    }

    debugPrint('[LOC-DEBUG] FINAL manualLink = "$manualLink"');

    // ── Resolve best available coordinates ──────────────────────────────
    double? custLat;
    double? custLng;

    final rawLat = task['partner_latitude'];
    final rawLng = task['partner_longitude'];
    if (rawLat != null && rawLat != false) {
      final lat = (rawLat as num).toDouble();
      final lng = rawLng != null && rawLng != false
          ? (rawLng as num).toDouble() : 0.0;
      if (lat.abs() > 0.0001 && lng.abs() > 0.0001) {
        custLat = lat; custLng = lng;
      }
    }
    if (custLat == null) {
      final googleLink = _str(task['google_map_link']);
      final coords = _latLngFromUrl(googleLink.isNotEmpty ? googleLink : '')
          ?? _latLngFromUrl(manualLink);
      if (coords != null) { custLat = coords.lat; custLng = coords.lng; }
    }

    // ── Truly no location of any kind → block ────────────────────────────
    final googleLinkFallback = _str(task['google_map_link']);
    if (custLat == null && manualLink.isEmpty && googleLinkFallback.isEmpty) {
      debugPrint('[LOC-DEBUG] ❌ BLOCKING: custLat=null AND manualLink empty AND googleLink empty → showing No Location dialog');
      _showNoLocationDialog(null);
      return;
    }

    // ── Has link but no parseable coordinates → block ───────────────────
    // Business rule: start/complete must be geofence-validated against
    // customer latitude/longitude and restriction_m, so manual links alone
    // are not enough for action execution.
    if (custLat == null) {
      _showCompleteLocationWarning(
        title: 'Customer Coordinates Required',
        message: 'Customer location must include valid latitude/longitude so distance can be validated before starting or completing the task.',
        customerLat: null, customerLng: null,
        manualLink: manualLink,
      );
      return;
    }

    // ── GPS proximity check ──────────────────────────────────────────────
    if (!mounted) return;
    bool spinnerOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
    void closeSpinner() {
      if (spinnerOpen && mounted) {
        spinnerOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    // ── Use server-configured restriction_m; fall back to 500m if none ──
    final double thresholdMetres =
        _restrictionMetres > 0 ? _restrictionMetres.toDouble() : 500.0;

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (!mounted) { spinnerOpen = false; return; }

      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        closeSpinner();
        _showCompleteLocationWarning(
          title: l.t('location_permission_denied_title'),
          message: l.t('location_permission_denied_body'),
          customerLat: custLat, customerLng: custLng,
          manualLink: manualLink,
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      closeSpinner();
      if (!mounted) return;

      final dist = _distanceMetres(
          pos.latitude, pos.longitude, custLat!, custLng!);

      if (dist <= thresholdMetres) {
        // ✅ User is close enough — proceed with the action
        if (isStart) {
          // Force-start via ORM (bypasses server location gate)
          final odoo = context.read<OdooCubit>();
          if (odoo.service != null) {
            final ok = await odoo.service!.startTaskBypassed(_taskId);
            if (ok && mounted) setState(() => _startingVisit = false);
          }
        } else {
          // Re-attempt complete — pass GPS coords this time
          _completeMaintenance(
            userLat: pos.latitude,
            userLng: pos.longitude,
          );
        }
      } else {
        // ❌ Too far → show distance warning with navigation link
        final isKm = dist >= 1000;
        final distStr = isKm
            ? (dist / 1000).toStringAsFixed(1)
            : dist.toStringAsFixed(0);
        final limitStr = thresholdMetres >= 1000
            ? '${(thresholdMetres / 1000).toStringAsFixed(1)} km'
            : '${thresholdMetres.toStringAsFixed(0)} m';
        final titleKey = 'manual_location_mismatch_title';
        final bodyKey  = isKm
            ? 'manual_location_mismatch_body_km'
            : 'manual_location_mismatch_body_m';
        final body = l.t(bodyKey).replaceAll('{dist}', distStr);
        _showCompleteLocationWarning(
          title: l.t(titleKey),
          message: '$body (Limit: $limitStr)',
          customerLat: custLat, customerLng: custLng,
          manualLink: manualLink,
        );
      }
    } catch (_) {
      closeSpinner();
      if (!mounted) return;
      _showCompleteLocationWarning(
        title: l.t('location_unavailable_title'),
        message: l.t('location_unavailable_body'),
        customerLat: custLat, customerLng: custLng,
        manualLink: manualLink,
      );
    }
  }

  /// Resolve partner location fields from OdooCubit's cached customer list.
  /// google_map_link_manual / partner_latitude / partner_longitude live on
  /// res.partner, NOT on project.task. This bridges the gap when the server
  /// endpoint is unavailable.
  void _resolvePartnerLocationFromCache(Map<String, dynamic> task) {
    try {
      final odoo = context.read<OdooCubit>();
      final partnerId = task['partner_id'];
      int? pId;
      if (partnerId is List && partnerId.isNotEmpty) {
        pId = partnerId[0] as int;
      } else if (partnerId is int) {
        pId = partnerId;
      }
      if (pId == null) return;

      final matches = odoo.customers.where((c) => c['id'] == pId).toList();
      if (matches.isEmpty) return;

      final p = matches.first;
      for (final key in ['google_map_link_manual', 'google_map_link',
                          'partner_latitude', 'partner_longitude']) {
        final pVal = p[key];
        if (pVal != null && pVal != false &&
            pVal.toString().trim().isNotEmpty &&
            pVal.toString().trim() != 'false') {
          final existing = task[key];
          if (existing == null || existing == false ||
              existing.toString().trim().isEmpty ||
              existing.toString().trim() == 'false') {
            task[key] = pVal;
          }
        }
      }
      debugPrint('[MaintenanceScreen] partner location from cache: '
          'manual=${task['google_map_link_manual']} '
          'lat=${task['partner_latitude']} lng=${task['partner_longitude']}');
    } catch (e) {
      debugPrint('[MaintenanceScreen] _resolvePartnerLocationFromCache error: $e');
    }
  }

  // ── Fetch the latest task data from Odoo to get up-to-date location ──
  // ── Fetch latest task data + partner location fields ─────────────────
  // IMPORTANT: google_map_link_manual / partner_latitude / partner_longitude
  // live on res.partner, NOT on project.task.  A plain searchRead on
  // project.task returns false for these fields even when they are set.
  // We fetch the task first, then fetch the partner row separately.
  Future<Map<String, dynamic>?> _fetchFreshTaskData() async {
    try {
      final odoo = context.read<OdooCubit>();
      if (odoo.service == null) return null;

      // 1. Task-level fields
      // FIX: fs_task_type_id is a custom field — portal users get an access
      // denied when trying to read it via ORM (groups=False means no portal
      // access at the record level). We drop it from the ORM read and fall
      // back to the value already present in widget.task (set at login via
      // the /fsm/my_tasks sudo route which does have access).
      final results = await odoo.service!.searchRead(
        model: 'project.task',
        domain: [['id', '=', _taskId]],
        fields: ['id', 'name', 'partner_id', 'stage_id', 'description'],
        limit: 1,
      );
      if (results.isEmpty) return null;

      final task = Map<String, dynamic>.from(results.first);

      // 2. Seed with widget.task values as baseline (already fetched at login)
      for (final key in ['google_map_link_manual', 'google_map_link',
                          'partner_latitude', 'partner_longitude']) {
        if (!task.containsKey(key) || task[key] == null || task[key] == false) {
          final fallback = widget.task[key];
          if (fallback != null && fallback != false) task[key] = fallback;
        }
      }

      // 2b. Resolve from cached partner data in OdooCubit
      _resolvePartnerLocationFromCache(task);

      // 3. Use dedicated /fsm/task/location endpoint (sudo) so portal users
      //    can read google_map_link_manual without needing res.partner access.
      //    This always overwrites with the freshest server-side values.
      try {
        final loc = await odoo.service!.fetchTaskLocation(_taskId);
        if (loc != null) {
          // FIX: apply the same "only overwrite when truthy" protection to
          // lat/lng that was already applied to google_map_link_manual.
          // Previously, blindly doing `task['partner_latitude'] = loc[...]`
          // would replace a valid cached coordinate with `false` whenever
          // the server returned false (e.g. one coord is zero, or the
          // endpoint returned false due to the old has_coords AND gate).
          // Now we only update when the endpoint gave us a real value.
          final _freshLat = loc['partner_latitude'];
          final _freshLng = loc['partner_longitude'];
          if (_freshLat != null && _freshLat != false) {
            task['partner_latitude'] = _freshLat;
          }
          if (_freshLng != null && _freshLng != false) {
            task['partner_longitude'] = _freshLng;
          }
          task['google_map_link']   = loc['google_map_link'];
          final _freshManual = loc['google_map_link_manual'];
          debugPrint('[LOC-DEBUG] _fetchFreshTaskData fetchTaskLocation raw: '
              'manual=$_freshManual lat=${loc["partner_latitude"]} lng=${loc["partner_longitude"]}');
          if (_freshManual != null &&
              _freshManual != false &&
              _freshManual.toString().trim().isNotEmpty &&
              _freshManual.toString().trim() != 'false') {
            task['google_map_link_manual'] = _freshManual;
          }
          debugPrint(
              '[MaintenanceScreen] location via endpoint: '
              'manual=${task["google_map_link_manual"]} '
              'lat=${loc["partner_latitude"]} lng=${loc["partner_longitude"]}');
        }
      } catch (e) {
        debugPrint('[MaintenanceScreen] fetchTaskLocation error: $e — using widget.task fallback');
      }

      // 3b. Last resort: direct ORM read on res.partner if still no location
      String _sVal(dynamic v) {
        if (v == null || v == false) return '';
        final s = v.toString().trim();
        return s == 'false' ? '' : s;
      }
      if (_sVal(task['google_map_link_manual']).isEmpty &&
          _sVal(task['partner_latitude']).isEmpty) {
        final partnerId = task['partner_id'];
        int? pId;
        if (partnerId is List && partnerId.isNotEmpty) pId = partnerId[0] as int;
        else if (partnerId is int) pId = partnerId;
        if (pId != null) {
          try {
            final partnerRows = await odoo.service!.searchRead(
              model: 'res.partner',
              domain: [['id', '=', pId]],
              fields: ['id', 'google_map_link_manual', 'google_map_link',
                       'partner_latitude', 'partner_longitude'],
              limit: 1,
            );
            if (partnerRows.isNotEmpty) {
              final p = partnerRows.first;
              for (final key in ['google_map_link_manual', 'google_map_link',
                                  'partner_latitude', 'partner_longitude']) {
                final pVal = p[key];
                if (pVal != null && pVal != false &&
                    pVal.toString().trim().isNotEmpty &&
                    pVal.toString().trim() != 'false') {
                  task[key] = pVal;
                }
              }
              debugPrint('[MaintenanceScreen] location from ORM res.partner: '
                  'manual=${task['google_map_link_manual']} '
                  'lat=${task['partner_latitude']} lng=${task['partner_longitude']}');
            }
          } catch (e) {
            debugPrint('[MaintenanceScreen] ORM res.partner fallback error: $e');
          }
        }
      }

      return task;
    } catch (e) {
      debugPrint('[MaintenanceScreen] _fetchFreshTaskData error: $e');
    }
    return null;
  }

  /// Triggered when the user taps COMPLETE.
  ///
  /// Design: mirror the Start-Visit approach — just get GPS coords and let the
  /// SERVER evaluate the geofence via [restriction_m].  The old client-side
  /// proximity calculation was fragile and blocked legitimate completions.
  Future<void> _completeWithLocationCheck() async {
    // ── Double-tap guard ─────────────────────────────────────────────────
    if (_completing) return;
    if (mounted) setState(() => _completing = true);

    try {
      // Get current GPS position (null if permission denied — server skips
      // geofence when no coords are sent).
      final pos = await _getCurrentPosition();
      await _completeMaintenance(
        userLat: pos?.latitude,
        userLng: pos?.longitude,
      );
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> _completeMaintenance({
    bool bypassLocationCheck = false,
    double? userLat,
    double? userLng,
  }) async {
    final odoo = context.read<OdooCubit>();

    final now = DateTime.now();
    final tickerSecs = _ts.seconds(_taskId);
    double elapsedHours;

    if (tickerSecs > 0) {
      
      elapsedHours = tickerSecs / 3600.0;
    } else if (_odooTimerStart != null) {
      final secs = ((now.difference(_odooTimerStart!).inMilliseconds + 500) ~/ 1000)
          .clamp(0, 86400 * 30);
      elapsedHours = secs / 3600.0;
    } else if (_ts.startedAt(_taskId) != null) {
      final secs = ((now.difference(_ts.startedAt(_taskId)!).inMilliseconds + 500) ~/ 1000)
          .clamp(0, 86400 * 30);
      elapsedHours = secs / 3600.0;
    } else {
      elapsedHours = _ts.hoursElapsed(_taskId);
    }

    final totalElapsedSecs = (elapsedHours * 3600).round();
    debugPrint('[Complete] tickerSecs=$tickerSecs elapsedHours=$elapsedHours totalElapsedSecs=$totalElapsedSecs');

    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const AlertDialog(
            content: Row(children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(width: 16),
              Text('Completing task...'),
            ])));

    bool success = false;

    if (odoo.service != null) {
      
      String?              _wsModel;
      Map<String, dynamic>? _wsValues;
      int?                 _wsRecordId;

      if (_worksheetModel != null && _worksheetTaskField != null) {
        final values = <String, dynamic>{};
        _worksheetCtrls.forEach((key, ctrl) {
          final def   = _worksheetFieldDefs[key] as Map?;
          final ftype = def?['type']?.toString() ?? 'char';
          final text  = ctrl.text.trim();
          if (ftype == 'integer') {
            values[key] = int.tryParse(text) ?? 0;
          } else if (ftype == 'float' || ftype == 'monetary') {
            values[key] = double.tryParse(text) ?? 0.0;
          } else {
            values[key] = text;
          }
        });
        _worksheetFieldDefs.forEach((key, defRaw) {
          final ftype = (defRaw as Map?)?['type']?.toString() ?? '';
          if (ftype == 'boolean') {
            values[key] = _worksheetValues[key] == true;
          } else if (ftype == 'selection' && _worksheetValues.containsKey(key)) {
            values[key] = _worksheetValues[key];
          }
        });
        if (values.isNotEmpty) {
          _wsModel     = _worksheetModel;
          _wsValues    = values;
          _wsRecordId  = _worksheetRecordId;
        }
      }

      for (int i = 0; i < 3 && !success; i++) {
        try {
          success = await odoo.service!.markTaskDone(
            _taskId,
            elapsedHours: elapsedHours,
            description: 'Maintenance visit - ${widget.maintenanceId}',
            worksheetModel:    _wsModel,
            worksheetValues:   _wsValues,
            worksheetRecordId: _wsRecordId,
            bypassLocationCheck: bypassLocationCheck,
            userLat: userLat,
            userLng: userLng,
          );
          debugPrint('[Complete] markTaskDone attempt $i: success=$success');
        } catch (e) {
          debugPrint('[Complete] markTaskDone error: $e');
          // no_location from server: enforce location requirement.
          if (e.toString().contains('no_location:')) {
            if (mounted) Navigator.pop(context);
            await _handleNoLocationFromServer(isStart: false);
            return;
          }

          // Task already completed — treat as success so local state is
          // cleaned up properly (timer stopped, task marked done locally).
          // FIX: previously this returned early, skipping _ts.stopTimer etc.
          if (e.toString().contains('already_completed:')) {
            success = true;
            break;
          }

          // Outside geofence — show distance warning
          if (e.toString().contains('outside_geofence:')) {
            if (mounted) {
              Navigator.pop(context);
              final msg = e.toString().replaceFirst('Exception: outside_geofence:', '').trim();
              _showCompleteLocationWarning(
                title: 'Too Far from Customer',
                message: msg,
                customerLat: null, customerLng: null,
              );
            }
            return;
          }
          if (i < 2) await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    _ts.recordCompletedVisit(_taskId);
    _ts.stopTimer(_taskId);
    _odooTimerStart = null;
    _accumulatedHours = 0.0;

    if (mounted) {
      Navigator.pop(context); 

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          success ? 'Time saved ✓' : 'Saved locally — sync failed.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: success ? AppTheme.success : Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));

      await odoo.fetchMyTasks();
      if (mounted) Navigator.pop(context); 
    }
  }
  // ─────────────────────────────────────────────────────────────────────────
  // Signature helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// On init: check if Odoo already has a signature for this task.
  Future<void> _checkExistingSignature() async {
    final odoo = context.read<OdooCubit>();
    if (odoo.service == null) return;
    try {
      final status = await odoo.service!.checkSignatureStatus(_taskId);
      if (status.hasSig && mounted) {
        setState(() {
          _signatureUploaded = true;
          _signatureDate     = status.sigDate;
        });
        // Load the actual bytes so thumbnail shows and WhatsApp share works
        final bytes = await odoo.service!.fetchSignatureBytes(_taskId);
        if (bytes != null && mounted) {
          setState(() => _signatureBytes = bytes);
        }
      }
    } catch (_) {}
  }

  /// Open the signature pad and handle the result.
  Future<void> _openSignaturePad() async {
    final pngBytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (_) => SignatureScreen(
          customerName: widget.customerName,
          taskName: widget.task['name']?.toString() ?? widget.maintenanceId,
        ),
      ),
    );

    if (pngBytes == null || !mounted) return; // user cancelled

    setState(() {
      _signatureBytes   = pngBytes;
      _uploadingSignature = true;
    });

    // Upload to Odoo in background
    final odoo = context.read<OdooCubit>();
    if (odoo.service != null) {
      final result = await odoo.service!.uploadSignature(
        taskId:   _taskId,
        pngBytes: pngBytes,
      );
      if (mounted) {
        setState(() {
          _uploadingSignature  = false;
          _signatureUploaded   = result.success;
          if (result.success) {
            _signatureDate = DateTime.now().toUtc().toIso8601String();
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            result.success
                ? 'Signature saved ✓'
                : 'Signature captured locally. Upload failed: ${result.error}',
            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          backgroundColor: result.success
              ? AppTheme.success
              : Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ));
      }
    } else {
      // No service — keep bytes in-memory
      if (mounted) setState(() => _uploadingSignature = false);
    }
  }

  /// Build the signature section widget shown in the maintenance screen.
  Widget _buildSignatureSection() {
    // ── Already signed (uploaded to Odoo or captured locally) ─────────────
    if (_signatureUploaded || _signatureBytes != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.success.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.15),
                    shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_outline,
                    color: AppTheme.success, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _signatureUploaded
                        ? 'Signature Saved to Odoo ✓'
                        : 'Signature Captured (pending upload)',
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppTheme.success),
                  ),
                  if (_signatureDate != null) ...[ 
                    const SizedBox(height: 2),
                    Text(
                      _formatSigDate(_signatureDate!),
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppTheme.textGrey),
                    ),
                  ],
                ],
              )),
              // Re-sign button
              TextButton(
                onPressed: _uploadingSignature ? null : _openSignaturePad,
                child: Text('Re-sign',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ]),

            // Show the captured signature thumbnail
            if (_signatureBytes != null) ...[ 
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  color: Colors.white,
                  child: Image.memory(_signatureBytes!,
                      fit: BoxFit.contain),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // ── Not yet signed ─────────────────────────────────────────────────────
    return GestureDetector(
      onTap: _uploadingSignature ? null : _openSignaturePad,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.orange.shade300, width: 1.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_uploadingSignature)
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: AppTheme.primary, strokeWidth: 2.5),
            )
          else
            const Icon(Icons.draw_outlined,
                color: AppTheme.textDark, size: 22),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              _uploadingSignature
                  ? 'Uploading signature…'
                  : 'Customer Signature Required',
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _uploadingSignature
                      ? AppTheme.textGrey
                      : AppTheme.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!_uploadingSignature) ...[ 
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6)),
              child: Text('TAP',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange.shade700)),
            ),
          ],
        ]),
      ),
    );
  }

  String _formatSigDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h  = dt.hour.toString().padLeft(2, '0');
      final m  = dt.minute.toString().padLeft(2, '0');
      final d  = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      return 'Signed on ${dt.year}-$mo-$d at $h:$m';
    } catch (_) {
      return 'Signed';
    }
  }

  // ── Get current GPS position (returns null if permission denied) ──────────
  Future<Position?> _getCurrentPosition() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return ListenableBuilder(
      listenable: _ts,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final started = _ts.isStarted(_taskId);
    final paused  = _ts.isPaused(_taskId);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Builder(builder: (_) {
          final typeField = widget.task['fs_task_type_id'];
          final typeName  = (typeField is List && typeField.length > 1)
              ? typeField[1].toString()
              : widget.maintenanceId;
          final taskName  = widget.task['name']?.toString() ?? '';
          final titleStr  = taskName.isNotEmpty
              ? '$typeName · $taskName'
              : typeName;
          return Text(titleStr,
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700,
                  color: AppTheme.textDark),
              overflow: TextOverflow.ellipsis);
        }),
        centerTitle: true,
        
        actions: [
          if (started && !paused)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6,
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('Live', style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: Colors.green.shade700)),
                  ]),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          _buildTimerCard(started, paused),
          const SizedBox(height: 18),

          _infoCard([
            _infoRow(Icons.business_outlined, 'CUSTOMER',
                widget.customerName.isNotEmpty ? widget.customerName : 'N/A', AppTheme.primary),
            const Divider(height: 1, indent: 14, endIndent: 14),
            _infoRow(Icons.location_on_outlined, 'LOCATION',
                widget.location.isNotEmpty ? widget.location : 'N/A', Colors.red),
            const Divider(height: 1, indent: 14, endIndent: 14),
            _infoRow(Icons.tag, 'SERIAL NUMBER', widget.serialNumber, AppTheme.textGrey),
          ]),
          const SizedBox(height: 24),

          Builder(builder: (_) {
            final tf = widget.task['fs_task_type_id'];
            final typeName = (tf is List && tf.length > 1)
                ? tf[1].toString()[0].toUpperCase() + tf[1].toString().substring(1)
                : '';
            return Text(typeName.isNotEmpty ? '$typeName Guide' : 'Guide',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800,
                    color: AppTheme.textDark));
          }),
          const SizedBox(height: 8),
          const SizedBox(height: 4),
          if (_loadingWorksheet)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
            )
          else if (_descriptionHtml.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Text('No description found.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey)),
            )
          else
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Text(
                _descriptionHtml
                    .replaceAll(RegExp(r'<br\s*\/?>'), '\n')
                    .replaceAll(RegExp(r'<p[^>]*>'), '')
                    .replaceAll('</p>', '\n')
                    .replaceAll(RegExp(r'<li[^>]*>'), '• ')
                    .replaceAll('</li>', '\n')
                    .replaceAll(RegExp(r'<[^>]+>'), '')
                    .replaceAll('&nbsp;', ' ')
                    .replaceAll('&amp;', '&')
                    .replaceAll('&lt;', '<')
                    .replaceAll('&gt;', '>')
                    .replaceAll('&quot;', '"')
                    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
                    .trim(),
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textDark, height: 1.6),
              ),
            ),
          const SizedBox(height: 20),

          Builder(builder: (_) {
            final tf = widget.task['fs_task_type_id'];
            final typeName = (tf is List && tf.length > 1)
                ? tf[1].toString()[0].toUpperCase() + tf[1].toString().substring(1)
                : '';
            return Text(typeName.isNotEmpty ? '$typeName Tasks' : 'Tasks',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800,
                    color: AppTheme.textDark));
          }),
          const SizedBox(height: 12),

          if (_loadingWorksheet)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16)),
              child: const Center(child: CircularProgressIndicator(
                  color: AppTheme.primary, strokeWidth: 2)),
            )

          else if (_worksheetModel != null && _worksheetFieldDefs.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                      blurRadius: 8, offset: const Offset(0, 2))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._worksheetFieldDefs.entries.map((entry) {
                    final fieldKey = entry.key;
                    final def      = entry.value as Map;
                    final ftype    = def['type']?.toString() ?? 'char';
                    final label    = def['string']?.toString() ?? fieldKey;

                    if (ftype == 'boolean') {
                      final val = _worksheetValues[fieldKey] == true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _worksheetValues[fieldKey] = !val);
                            _saveWorksheetToOdoo();
                          },
                          child: Row(children: [
                            Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                  color: val ? AppTheme.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: val ? AppTheme.primary : Colors.grey.shade300,
                                      width: 2)),
                              child: val ? const Icon(Icons.check, size: 14,
                                  color: Colors.white) : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(label,
                                style: GoogleFonts.inter(fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textDark))),
                          ]),
                        ),
                      );
                    }

                    if (ftype == 'selection') {
                      final selOpts = def['selection'];
                      final cur = _worksheetValues[fieldKey]?.toString();
                      List<MapEntry<String, String>> opts = [];
                      if (selOpts is List) {
                        opts = selOpts.map<MapEntry<String, String>>((e) => e is List
                            ? MapEntry(e[0].toString(), e[1].toString())
                            : MapEntry(e.toString(), e.toString())).toList();
                      } else if (selOpts is String) {
                        final re = RegExp(r"\('([^']+)',\s*'([^']+)'\)");
                        opts = re.allMatches(selOpts)
                            .map<MapEntry<String, String>>(
                                (m) => MapEntry(m.group(1)!, m.group(2)!))
                            .toList();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label.toUpperCase(),
                                style: GoogleFonts.inter(fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textGrey, letterSpacing: 0.5)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(10)),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: opts.any((e) => e.key == cur) ? cur : null,
                                  isExpanded: true,
                                  hint: Text('Select...', style: GoogleFonts.inter(
                                      fontSize: 13, color: AppTheme.textGrey)),
                                  items: opts.map((e) => DropdownMenuItem<String>(
                                    value: e.key,
                                    child: Text(e.value, style: GoogleFonts.inter(
                                        fontSize: 13, color: AppTheme.textDark)),
                                  )).toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _worksheetValues[fieldKey] = v);
                                      _saveWorksheetToOdoo();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final ctrl = _worksheetCtrls[fieldKey] ??= TextEditingController(
                        text: (_worksheetValues[fieldKey]?.toString() ?? ''));
                    final isNum = ftype == 'integer' || ftype == 'float' ||
                        ftype == 'monetary';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label.toUpperCase(),
                              style: GoogleFonts.inter(fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textGrey, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200)),
                            child: TextField(
                              controller: ctrl,
                              keyboardType: isNum
                                  ? const TextInputType.numberWithOptions(decimal: true)
                                  : TextInputType.multiline,
                              maxLines: ftype == 'text' ? 4 : 1,
                              style: GoogleFonts.inter(fontSize: 14,
                                  color: AppTheme.textDark),
                              decoration: InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  hintText: 'Enter ${label.toLowerCase()}...',
                                  hintStyle: GoogleFonts.inter(fontSize: 13,
                                      color: AppTheme.textGrey)),
                              onChanged: (_) {
                                _notesDebounce?.cancel();
                                _notesDebounce = Timer(
                                    const Duration(seconds: 2), _saveWorksheetToOdoo);
                              },
                              onEditingComplete: _saveWorksheetToOdoo,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            )

          else if (_checks.isNotEmpty) ...[
              Text('$_completedChecks of ${_checks.length} completed',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textGrey)),
              const SizedBox(height: 8),
              _progressBar(_checks.isEmpty ? 0 : _completedChecks / _checks.length),
              const SizedBox(height: 14),
              if (_checks.isNotEmpty) _fullTask(_checks.keys.first, _checks[_checks.keys.first]!),
              const SizedBox(height: 10),
              ...() {
                final keys = _checks.keys.skip(1).toList();
                final rows = <Widget>[];
                for (int i = 0; i < keys.length; i += 2) {
                  rows.add(Row(children: [
                    Expanded(child: _task(keys[i], _checks[keys[i]]!)),
                    const SizedBox(width: 10),
                    Expanded(child: i + 1 < keys.length
                        ? _task(keys[i + 1], _checks[keys[i + 1]]!)
                        : const SizedBox()),
                  ]));
                  if (i + 2 < keys.length) rows.add(const SizedBox(height: 10));
                }
                return rows;
              }(),
            ]

            else
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: Text('No worksheet fields found.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey)),
              ),
          const SizedBox(height: 16),

          Text('MAINTENANCE TECHNICIAN NOTES',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppTheme.textGrey, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          _textArea(_notesCtrl, 'Type your observations here...'),
          const SizedBox(height: 24),

          if (() {
            final tf = widget.task['fs_task_type_id'];
            final n = (tf is List && tf.length > 1)
                ? tf[1].toString().toLowerCase()
                : '';
            return n.contains('spare');
          }()) ...[
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => TaskSparePartsScreen(task: widget.task)));
                _loadMaterials();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: AppTheme.textDark,
                    borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text('Spare Parts Management',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ]),
              ),
            ),

            if (_loadingMaterials)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2)))
            else if (_taskMaterials.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_taskMaterials.length} part(s) linked',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textGrey,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ..._taskMaterials.take(3).map((m) {
                    final prod = m['product_id'];
                    final name = prod is List ? prod[1].toString() : m['name']?.toString() ?? 'Part';
                    final qty  = m['product_uom_qty'] ?? m['qty'] ?? 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.circle, size: 6, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(name,
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textDark))),
                        Text('x$qty', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textGrey)),
                      ]),
                    );
                  }),
                ]),
              ),
            ],
          ], 
          const SizedBox(height: 22),
          Text('CUSTOMER FEEDBACK',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppTheme.textGrey, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          _textArea(_feedbackCtrl, 'Client comments...'),
          const SizedBox(height: 14),

          _buildSignatureSection(),
          const SizedBox(height: 14),

          GestureDetector(
            onTap: (started && !_completing) ? _completeWithLocationCheck : null,
            child: Container(
              width: double.infinity, height: 56,
              decoration: BoxDecoration(
                  color: (started && !_completing) ? AppTheme.primary : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: (started && !_completing) ? [BoxShadow(color: AppTheme.primary.withOpacity(0.35),
                      blurRadius: 16, offset: const Offset(0, 6))] : []),
              child: Center(
                child: _completing
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text('COMPLETE',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800,
                            color: Colors.white, letterSpacing: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _buildTimerCard(bool started, bool paused) {
    final isCompleted = _isTaskCompleted();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 20, offset: const Offset(0, 4))]),
      child: Column(children: [
        Text('Visit #${widget.task['id']}',
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),

        if (_checkingOdoo)
          const SizedBox(height: 52, child: Center(
              child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)))
        else if (isCompleted)
        
          Column(children: [
            Icon(Icons.check_circle_outline, size: 48, color: AppTheme.success),
            const SizedBox(height: 12),
            Text(
              'Task Completed',
              style: GoogleFonts.inter(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppTheme.success),
            ),
            const SizedBox(height: 8),
            Text(
              'This maintenance task has been marked as done',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppTheme.textGrey),
              textAlign: TextAlign.center,
            ),
          ])
        else
          Builder(builder: (_) {
            final sessionSecs = started ? _ts.seconds(_taskId) : 0;
            final totalSecs = sessionSecs + (_accumulatedHours * 3600).round();
            final h = totalSecs ~/ 3600;
            final m = (totalSecs % 3600) ~/ 60;
            final s = totalSecs % 60;
            final display = '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
            return Text(
              (started || _accumulatedHours > 0) ? display : '00:00:00',
              style: GoogleFonts.inter(
                  fontSize: 52, fontWeight: FontWeight.w900,
                  color: started
                      ? (paused ? Colors.orange.shade700 : AppTheme.textDark)
                      : (_accumulatedHours > 0 ? Colors.orange.shade700 : Colors.grey.shade400),
                  letterSpacing: 2),
            );
          }),

        if (isCompleted)
          const SizedBox(height: 8)
        else if (started) ...[
          const SizedBox(height: 6),
          Text(
            paused
                ? 'Task Paused'
                : (_ts.startedAt(_taskId) != null
                ? 'Started ${_formatStartTime(_ts.startedAt(_taskId)!)}'
                : ''),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: paused ? FontWeight.w600 : FontWeight.w400,
              color: paused ? Colors.orange.shade700 : AppTheme.textGrey,
            ),
          ),
          const SizedBox(height: 18),
          
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: (_pausingVisit || _startingVisit) ? null : () {
                if (paused) _resumeVisit(); else _pauseVisit();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: paused ? AppTheme.primary : AppTheme.textDark,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              icon: _pausingVisit
                  ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Icon(paused ? Icons.play_arrow : Icons.pause,
                  color: Colors.white, size: 20),
              label: Text(
                  _pausingVisit ? 'Syncing...' : (paused ? 'Resume Visit' : 'Pause'),
                  style: GoogleFonts.inter(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ] else if (!isCompleted) ...[
          
          const SizedBox(height: 8),
          Text(
            'Press "Start Visit" to begin tracking time',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, height: 54,
            child: ElevatedButton.icon(
              onPressed: _checkingOdoo || _startingVisit ? null : _startVisit,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              icon: _startingVisit
                  ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.play_circle_outline, color: Colors.white, size: 22),
              label: Text(_startingVisit ? 'Starting...' : 'Start Visit',
                  style: GoogleFonts.inter(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ]),
    );
  }
  String _formatStartTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'today at $h:$m';
    }
    return '${diff.inDays}d ago';
  }

  Widget _infoCard(List<Widget> children) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(children: children),
  );

  Widget _infoRow(IconData icon, String label, String value, Color iconColor) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: iconColor)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textGrey,
                fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700,
                color: AppTheme.textDark), overflow: TextOverflow.ellipsis),
          ])),
        ]),
      );

  Widget _progressBar(double value) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: LinearProgressIndicator(value: value,
        backgroundColor: Colors.grey.shade200,
        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
        minHeight: 6),
  );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: GoogleFonts.inter(
        fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );

  Widget _fullTask(String label, bool checked) => GestureDetector(
    onTap: () {
      setState(() => _checks[label] = !checked);
      _saveWorksheetToOdoo(); 
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        _checkbox(checked), const SizedBox(width: 12),
        Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13,
            fontWeight: FontWeight.w500, color: AppTheme.textDark))),
      ]),
    ),
  );

  Widget _task(String label, bool checked) => GestureDetector(
    onTap: () {
      setState(() => _checks[label] = !checked);
      _saveWorksheetToOdoo(); 
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        _checkbox(checked), const SizedBox(width: 8),
        Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 12,
            fontWeight: FontWeight.w500, color: AppTheme.textDark))),
      ]),
    ),
  );

  Widget _checkbox(bool checked) => Container(
    width: 22, height: 22,
    decoration: BoxDecoration(
        color: checked ? AppTheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: checked ? AppTheme.primary : Colors.grey.shade300, width: 2)),
    child: checked ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
  );

  Widget _textArea(TextEditingController ctrl, String hint) => Container(
    height: 100,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200)),
    child: TextField(controller: ctrl, maxLines: null,
        decoration: InputDecoration(hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey),
            border: InputBorder.none, contentPadding: const EdgeInsets.all(14))),
  );
}
