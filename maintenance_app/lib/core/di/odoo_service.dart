import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OdooService {
  final String baseUrl;
  String? _sessionId;
  int? _uid;
  String _storedLogin = '';
  String _storedPassword = '';
  bool _isPortalUser = false;

  OdooService(String raw) : baseUrl = _cleanUrl(raw);
  int? get uid => _uid;
  bool get isPortalUser => _isPortalUser;

  static String _cleanUrl(String raw) {
    raw = raw.trim();
    while (raw.endsWith('/')) raw = raw.substring(0, raw.length - 1);
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return raw;
    return '${uri.scheme}://${uri.host}';
  }

  static Never _throwNetworkError(dynamic e, String url) {
    if (e is OdooException) throw e;
    if (e is SocketException) {
      final msg = e.message;
      if (msg.contains('Failed host lookup') || msg.contains('No address associated')) {
        throw OdooException('Cannot connect to $url\nHost not found.');
      }
      throw OdooException('Network error: $msg');
    }
    if (e is HandshakeException) throw OdooException('SSL/TLS error for $url');
    if (e is TimeoutException) throw OdooException('Connection timed out.');
    if (e is FormatException) throw OdooException('Invalid response from server.');
    throw OdooException('Unexpected error: $e');
  }

  String? _detectedDb;

  Future<String> detectDatabase() async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/web/database/list'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'id': 1, 'params': {}}),
      ).timeout(const Duration(seconds: 15));
      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final body = jsonDecode(raw) as Map<String, dynamic>;
        if (body['error'] == null) {
          final dbs = List<String>.from(body['result'] as List? ?? []);
          if (dbs.isNotEmpty) {
            _detectedDb = dbs.first;
            return _detectedDb!;
          }
        }
      }
    } catch (_) {}

    try {
      final uri = Uri.parse(baseUrl);
      final host = uri.host;
      if (host.contains('.dev.odoo.com') || host.contains('.odoo.com')) {
        final subdomain = host.split('.').first;
        _detectedDb = subdomain;
        return _detectedDb!;
      }
    } catch (_) {}

    _detectedDb = '';
    return '';
  }

  Future<int> authenticate({required String login, required String password, String? dbOverride}) async {
    final db = dbOverride ?? _detectedDb ?? '';
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/web/session/authenticate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'db': db, 'login': login.trim(), 'password': password}}),
      ).timeout(const Duration(seconds: 20));
      final cookie = res.headers['set-cookie'] ?? '';
      final cm = RegExp(r'session_id=([^;]+)').firstMatch(cookie);
      if (cm != null) _sessionId = cm.group(1);
      final raw = res.body.trim();
      if (raw.toLowerCase().startsWith('<!')) throw OdooException('Server returned HTML. Check the URL.');
      final body = jsonDecode(raw) as Map<String, dynamic>;
      if (body['error'] != null) {
        final msg = (body['error']['data']?['message'] ?? body['error']['message'] ?? 'Server error').toString();

        if ((msg.toLowerCase().contains('database') || msg.toLowerCase().contains('not found')) && db.isNotEmpty) {
          return await authenticate(login: login, password: password, dbOverride: '');
        }
        throw OdooException(msg);
      }
      final result = body['result'];
      if (result == null) throw OdooException('No response. Check URL.');
      final uid = result['uid'];
      if (uid == null || uid == false) {
        if (db.isNotEmpty && dbOverride == null) {
          try {
            return await authenticate(login: login, password: password, dbOverride: '');
          } catch (_) {}
        }
        throw OdooException('Incorrect email or password.');
      }
      _uid = (uid as num).toInt();
      if (login.isNotEmpty) _storedLogin = login.trim();
      if (password.isNotEmpty) _storedPassword = password;
      return _uid!;
    } catch (e) { _throwNetworkError(e, baseUrl); }
  }

  Future<bool> _reauthenticate() async {
    if (_storedLogin.isEmpty || _storedPassword.isEmpty) return false;
    try {
      await authenticate(login: _storedLogin, password: _storedPassword);
      return _sessionId != null;
    } catch (_) { return false; }
  }

  Future<List<Map<String, dynamic>>> searchRead({
    required String model,
    required List<dynamic> domain,
    required List<String> fields,
    int limit = 200,
    String? order,
  }) async {
    try {
      final kwargs = <String, dynamic>{'fields': fields, 'limit': limit};
      if (order != null) kwargs['order'] = order;
      final res = await http.post(
        Uri.parse('$baseUrl/web/dataset/call_kw'),
        headers: {'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId'},
        body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'model': model, 'method': 'search_read',
            'args': [domain], 'kwargs': kwargs}}),
      ).timeout(const Duration(seconds: 20));
      final cookie = res.headers['set-cookie'] ?? '';
      final cm = RegExp(r'session_id=([^;]+)').firstMatch(cookie);
      if (cm != null) _sessionId = cm.group(1);
      final raw = res.body.trim();
      if (raw.toLowerCase().startsWith('<!')) throw OdooException('Session expired. Please log in again.');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['error'] != null) {
        throw OdooException((decoded['error']?['data']?['message'] ??
            decoded['error']?['message'] ?? 'API error').toString());
      }
      final result = decoded['result'];
      if (result == null) return [];
      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) { _throwNetworkError(e, baseUrl); }
  }

  Future<dynamic> callMethod({
    required String model,
    required String method,
    required List<dynamic> args,
    Map<String, dynamic>? kwargs,
    bool isRetry = false,
  }) async {
    try {
      final effectiveKwargs = Map<String, dynamic>.from(kwargs ?? {});
      if (_uid != null && !effectiveKwargs.containsKey('context')) {
        effectiveKwargs['context'] = {'uid': _uid};
      }
      final res = await http.post(
        Uri.parse('$baseUrl/web/dataset/call_kw'),
        headers: {'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId'},
        body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'model': model, 'method': method,
            'args': args, 'kwargs': effectiveKwargs}}),
      ).timeout(const Duration(seconds: 30));
      final cookie = res.headers['set-cookie'] ?? '';
      final cm = RegExp(r'session_id=([^;]+)').firstMatch(cookie);
      if (cm != null) _sessionId = cm.group(1);
      final raw = res.body.trim();
      if (raw.toLowerCase().startsWith('<!')) {
        if (!isRetry && await _reauthenticate()) {
          return callMethod(model: model, method: method, args: args, kwargs: kwargs, isRetry: true);
        }
        throw OdooException('Session expired. Please log in again.');
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['error'] != null) {
        final errMsg = (decoded['error']?['data']?['message'] ??
            decoded['error']?['message'] ?? 'API error').toString();
        if (!isRetry &&
            (errMsg.toLowerCase().contains('session') ||
                errMsg.toLowerCase().contains('access') ||
                errMsg.toLowerCase().contains('login'))) {
          if (await _reauthenticate()) {
            return callMethod(model: model, method: method, args: args, kwargs: kwargs, isRetry: true);
          }
        }
        throw OdooException(errMsg);
      }
      return decoded['result'];
    } catch (e) { _throwNetworkError(e, baseUrl); }
  }

  Future<bool> checkIsPortalUser(int userId) async {
    try {
      final res = await searchRead(
        model: 'res.users',
        domain: [['id', '=', userId]],
        fields: ['share'],
        limit: 1,
      );
      if (res.isNotEmpty) {
        _isPortalUser = res.first['share'] == true;
        print('[OdooService] checkIsPortalUser: userId=$userId isPortal=$_isPortalUser');
        return _isPortalUser;
      }
    } catch (e) {
      print('[OdooService] checkIsPortalUser error: $e');
    }
    return false;
  }

  // Helper to fetch app timer start from server
  Future<String?> fetchAppTimerStart(int taskId) async {
    try {
      final info = await fetchTaskTimingInfo(taskId);
      final timerStart = info?['timer_start'];
      if (timerStart != null && timerStart.toString().isNotEmpty) {
        print('[OdooService] fetchAppTimerStart: task=$taskId timer_start=$timerStart');
        return timerStart.toString();
      }
      return null;
    } catch (e) {
      print('[OdooService] fetchAppTimerStart error: $e');
      return null;
    }
  }

  // Helper to verify timer is actually running on server
  Future<bool> verifyTimerRunning(int taskId) async {
    final timerStart = await fetchAppTimerStart(taskId);
    final isRunning = timerStart != null && timerStart.isNotEmpty;
    print('[OdooService] verifyTimerRunning: task=$taskId isRunning=$isRunning timerStart=$timerStart');
    return isRunning;
  }

  Future<List<Map<String, dynamic>>> fetchMyTasks(int userId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/my_tasks'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {},
        }),
      ).timeout(const Duration(seconds: 20));
      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] != null) {
          final result = decoded['result'] as Map<String, dynamic>;
          final tasks = List<Map<String, dynamic>>.from(result['tasks'] as List);
          if (tasks.isNotEmpty) {
            print('[fetchMyTasks] /fsm/my_tasks OK → ${tasks.length} tasks');
            return tasks;
          }
        }
      }
    } catch (e) {
      print('[fetchMyTasks] /fsm/my_tasks error: $e — falling back');
    }

    final baseTasks = await _fetchBaseTasks(userId);
    if (baseTasks.isNotEmpty) {
      return await _injectTaskTypes(baseTasks, userId);
    }
    return baseTasks;
  }

  Future<List<Map<String, dynamic>>> _fetchBaseTasks(int userId) async {
    final fieldSets = [
      ['id', 'name', 'stage_id', 'project_id', 'partner_id', 'user_ids',
        'date_deadline', 'priority', 'description', 'fs_task_type_id',
        'planned_date_begin', 'fsm_location_id', 'total_hours_spent',
        'timer_start', 'date_start', 'active'],
      ['id', 'name', 'stage_id', 'project_id', 'partner_id', 'user_ids',
        'date_deadline', 'priority', 'description', 'fs_task_type_id',
        'planned_date_begin', 'active'],
      ['id', 'name', 'stage_id', 'project_id', 'partner_id', 'user_ids',
        'date_deadline', 'priority', 'description', 'active'],
      ['id', 'name', 'stage_id', 'project_id', 'partner_id', 'user_ids',
        'date_deadline', 'priority', 'description'],
    ];

    Future<List<Map<String, dynamic>>> tryDomain(List<dynamic> domain) async {
      for (final fields in fieldSets) {
        try {
          return await searchRead(
            model: 'project.task',
            domain: domain,
            fields: fields,
            limit: 500,
            order: 'priority desc, date_deadline asc',
          );
        } catch (_) {}
      }
      return [];
    }

    try {
      final res = await tryDomain([['active', '=', true], ['user_ids', 'in', [userId]]]);
      if (res.isNotEmpty) return res;
    } catch (_) {}

    try {
      final res = await tryDomain([['active', '=', true], ['user_id', '=', userId]]);
      if (res.isNotEmpty) return res;
    } catch (_) {}

    try {
      final res = await tryDomain([
        ['active', '=', true],
        '|',
        ['user_ids', 'in', [userId]],
        ['user_id', '=', userId],
      ]);
      if (res.isNotEmpty) return res;
    } catch (_) {}

    try {
      final ur = await searchRead(
        model: 'res.users',
        domain: [['id', '=', userId]],
        fields: ['partner_id'],
        limit: 1,
      );
      if (ur.isNotEmpty) {
        final pf = ur.first['partner_id'];
        if (pf is List && pf.isNotEmpty) {
          final partnerId = pf[0] as int;
          final res = await tryDomain([['active', '=', true], ['partner_id', '=', partnerId]]);
          if (res.isNotEmpty) return res;
        }
      }
    } catch (_) {}

    try {
      final res = await tryDomain([['user_ids', 'in', [userId]]]);
      if (res.isNotEmpty) return res;
    } catch (_) {}

    return [];
  }


  /// Calls /fsm/task/types (sudo on server) to get task types for portal users.
  /// Returns a map of taskId → [typeId, typeName] or null.
  Future<Map<int, List<dynamic>>> fetchTaskTypes(List<int> taskIds) async {
    if (taskIds.isEmpty) return {};
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/task/types'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_ids': taskIds},
        }),
      ).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      if (decoded['result'] != null) {
        final raw = decoded['result'] as Map<String, dynamic>;
        if (raw['success'] == true) {
          final typesRaw = raw['types'] as Map<String, dynamic>;
          final result = <int, List<dynamic>>{};
          typesRaw.forEach((key, value) {
            if (value != null && value != false && value is List) {
              result[int.parse(key)] = value;
            }
          });
          print('[fetchTaskTypes] /fsm/task/types → ${result.length}/${taskIds.length} typed');
          return result;
        }
      }
    } catch (e) {
      print('[fetchTaskTypes] error: $e');
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> _injectTaskTypes(
      List<Map<String, dynamic>> tasks,
      int userId,
      ) async {
    final alreadyHasTypes = tasks.any((t) {
      final v = t['fs_task_type_id'];
      return v is List && v.length > 1 && v[1].toString().isNotEmpty;
    });
    if (alreadyHasTypes) return tasks;

    final taskIds = tasks.map((t) => t['id'] as int).toList();
    if (taskIds.isEmpty) return tasks;

    final typeAssignment = <int, List<dynamic>>{};

    // ── Strategy 1: use /fsm/task/types (sudo) — works for portal users ─────
    try {
      final sudoTypes = await fetchTaskTypes(taskIds);
      if (sudoTypes.isNotEmpty) {
        typeAssignment.addAll(sudoTypes);
        print('[inject] sudo route got ${sudoTypes.length}/${taskIds.length} types ✓');
        return tasks.map((t) {
          final type = typeAssignment[t['id'] as int];
          return type != null ? {...t, 'fs_task_type_id': type} : t;
        }).toList();
      }
    } catch (e) {
      print('[inject] sudo route error: $e');
    }

    List<Map<String, dynamic>> allTypes = [];
    try {
      allTypes = await searchRead(
        model: 'fs.task.type',
        domain: [],
        fields: ['id', 'name'],
        limit: 200,
      );
      print('[inject] ${allTypes.length} types: ${allTypes.map((t) => t['name']).toList()}');
    } catch (e) {
      print('[inject] fs.task.type read error: $e');
    }

    for (final typeRec in allTypes) {
      final typeId = typeRec['id'] as int;
      final typeName = typeRec['name']?.toString() ?? '';
      if (typeName.isEmpty) continue;
      try {
        final matched = await searchRead(
          model: 'project.task',
          domain: [
            ['id', 'in', taskIds],
            ['fs_task_type_id.name', '=', typeName],
          ],
          fields: ['id'],
          limit: taskIds.length + 5,
        );
        for (final m in matched) {
          typeAssignment[m['id'] as int] = [typeId, typeName];
        }
        if (matched.isNotEmpty) {
          print('[inject] "$typeName" matched: ${matched.map((m) => m["id"]).toList()}');
        }
      } catch (e) {
        print('[inject] type "$typeName" dot-notation error: $e');
      }
    }

    if (typeAssignment.isEmpty) {
      print('[inject] dot-notation blocked — trying per-type user_ids queries');
      const kwMap = {
        'periodic': 'Periodic Maintenance',
        'urgent': 'Urgent',
        'spare': 'Spare Parts',
        'survey': 'Survey',
      };
      for (final entry in kwMap.entries) {
        final keyword = entry.key;
        final typeName = entry.value;

        final matchedType = allTypes.firstWhere(
              (t) => (t['name'] as String? ?? '').toLowerCase().contains(keyword),
          orElse: () => {'id': 0, 'name': typeName},
        );
        final typeId = matchedType['id'] as int;
        try {
          final matched = await searchRead(
            model: 'project.task',
            domain: [
              ['id', 'in', taskIds],
              ['name', 'ilike', keyword],
            ],
            fields: ['id'],
            limit: taskIds.length + 5,
          );
          for (final m in matched) {
            typeAssignment[m['id'] as int] = [typeId, typeName];
          }
        } catch (_) {}
      }
    }

    print('[inject] result: ${typeAssignment.length}/${taskIds.length} assigned');
    if (typeAssignment.isEmpty) return tasks;

    return tasks.map((t) {
      final type = typeAssignment[t['id'] as int];
      return type != null ? {...t, 'fs_task_type_id': type} : t;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchPeriodicTasksForPartner(int partnerId) async {
    try {
      return await searchRead(
        model: 'project.task',
        domain: [
          ['partner_id', '=', partnerId],
          ['fs_task_type_id.name', 'ilike', 'periodic maintenance'],
        ],
        fields: ['id', 'name', 'stage_id', 'date_deadline', 'priority', 'fs_task_type_id'],
        order: 'date_deadline desc',
        limit: 50,
      );
    } catch (_) {
      return await fetchTasksForPartner(partnerId);
    }
  }

  Future<List<Map<String, dynamic>>> fetchTasksForPartner(
      int partnerId, {int? userId}) async {
    final domain = <dynamic>[
      ['partner_id', '=', partnerId],
      if (userId != null) ['user_ids', 'in', [userId]],
    ];
    List<Map<String, dynamic>> res = [];
    for (final fields in [
      ['id', 'name', 'stage_id', 'date_deadline', 'priority', 'fs_task_type_id', 'user_ids'],
      ['id', 'name', 'stage_id', 'date_deadline', 'priority', 'user_ids'],
    ]) {
      try {
        res = await searchRead(
          model: 'project.task', domain: domain,
          fields: fields, order: 'date_deadline desc', limit: 100,
        );
        if (res.isNotEmpty) break;
      } catch (_) {}
    }
    if (res.isEmpty) return res;

    final enriched = await _injectTaskTypes(res, userId ?? 0);
    return enriched;
  }

  Future<List<Map<String, dynamic>>> fetchUrgentTasksForPartner(int partnerId) async {
    try {
      return await searchRead(
        model: 'project.task',
        domain: [
          ['partner_id', '=', partnerId],
          ['fs_task_type_id.name', 'ilike', 'urgent'],
        ],
        fields: ['id', 'name', 'stage_id', 'date_deadline', 'priority', 'fs_task_type_id'],
        order: 'date_deadline desc',
        limit: 50,
      );
    } catch (_) {
      return await searchRead(
        model: 'project.task',
        domain: [['partner_id', '=', partnerId], ['priority', '=', '1']],
        fields: ['id', 'name', 'stage_id', 'date_deadline', 'priority', 'fs_task_type_id'],
        order: 'date_deadline desc',
        limit: 50,
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchPartnersByIds(List<int> ids) async {
    try {
      final url = Uri.parse('$baseUrl/fsm/partners');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId'
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {'partner_ids': ids},
        }),
      ).timeout(const Duration(seconds: 15));
      
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        if (decoded['result'] != null && decoded['result']['partners'] != null) {
          final list = decoded['result']['partners'] as List;
          final partners = List<Map<String, dynamic>>.from(list);
          // ═══ DEBUG: log location fields from /fsm/partners ═══
          for (final p in partners) {
            print('[fetchPartnersByIds] /fsm/partners → id=${p['id']} name=${p['name']} '
                'keys=${p.keys.toList()} '
                'manual="${p['google_map_link_manual']}" '
                'glink="${p['google_map_link']}" '
                'lat=${p['partner_latitude']} lng=${p['partner_longitude']}');
          }
          return partners;
        }
      }
    } catch (e) {
      print('[fetchPartnersByIds] /fsm/partners error: $e');
    }

    // Fallback if the endpoint hasn't been deployed yet or failed
    print('[fetchPartnersByIds] using ORM fallback for ${ids.length} partners');
    final partners = await searchRead(
      model: 'res.partner',
      domain: [['id', 'in', ids]],
      fields: ['id', 'name', 'phone', 'mobile', 'email', 'street', 'city', 'image_128',
        'google_map_link', 'google_map_link_manual',
        'partner_latitude', 'partner_longitude'],
      limit: 1000,
    );
    // ═══ DEBUG: log location fields from ORM fallback ═══
    for (final p in partners) {
      print('[fetchPartnersByIds] ORM → id=${p['id']} name=${p['name']} '
          'manual="${p['google_map_link_manual']}" '
          'glink="${p['google_map_link']}" '
          'lat=${p['partner_latitude']} lng=${p['partner_longitude']}');
    }
    return partners;
  }

  Future<List<Map<String, dynamic>>> fetchPartners() async {
    const fields = ['id', 'name', 'phone', 'mobile', 'email', 'street', 'city', 'image_128',
      'google_map_link', 'google_map_link_manual',
      'partner_latitude', 'partner_longitude'];

    try {
      final res = await searchRead(
        model: 'res.partner',
        domain: [['customer_rank', '>=', 1]],
        fields: fields,
        limit: 2000,
      );
      if (res.isNotEmpty) return res;
    } catch (_) {}

    return searchRead(
      model: 'res.partner',
      domain: [['active', '=', true]],
      fields: fields,
      limit: 2000,
    );
  }

  Future<Map<String, dynamic>?> fetchWorksheetForTask(
      int taskId, {
        void Function(String)? onDebug,
      }) async {
    void dbg(String msg) {
      print(msg);
      onDebug?.call(msg);
    }

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/worksheet'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_id': taskId},
        }),
      ).timeout(const Duration(seconds: 20));

      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] != null) {
          final result = decoded['result'] as Map<String, dynamic>;
          if (result['error'] == null) {
            final fields = result['fields'] as Map<String, dynamic>? ?? {};
            final record = result['record'] as Map<String, dynamic>?;
            final model = result['model'] as String? ?? '';
            final tfField = result['task_field'] as String? ?? 'x_project_task_id';
            if (fields.isNotEmpty && model.isNotEmpty) {
              dbg('fetchWorksheet OK via /fsm/worksheet → ${fields.length} fields');
              return {
                'model': model,
                'taskField': tfField,
                'fields': fields,
                'record': record,
              };
            }
            dbg('fetchWorksheet endpoint returned: ${result['error']}');
          } else {
            dbg('fetchWorksheet endpoint error: ${result['error']}');
          }
        }
      }
    } catch (e) {
      dbg('fetchWorksheet endpoint exception: $e — falling back to direct ORM');
    }

    int? templateId;
    try {
      final rows = await searchRead(
        model: 'project.task',
        domain: [['id', '=', taskId]],
        fields: ['id', 'worksheet_template_id'],
        limit: 1,
      );
      if (rows.isEmpty) { dbg('S1 FAIL: task not found'); return null; }
      final tmpl = rows.first['worksheet_template_id'];
      if (tmpl == null || tmpl == false) {
        dbg('S1 FAIL: no worksheet_template_id'); return null;
      }
      templateId = tmpl is List ? (tmpl[0] as num).toInt() : (tmpl as num).toInt();
      dbg('S1 OK: templateId=$templateId');
    } catch (e) { dbg('S1 ERR: $e'); return null; }

    int? irModelId;
    try {
      final rows = await searchRead(
        model: 'worksheet.template',
        domain: [['id', '=', templateId]],
        fields: ['id', 'name', 'model_id'],
        limit: 1,
      );
      if (rows.isEmpty) { dbg('S2 FAIL'); return null; }
      final mid = rows.first['model_id'];
      if (mid is List && mid.isNotEmpty) {
        irModelId = (mid[0] as num).toInt();
        dbg('S2 OK: irModelId=$irModelId');
      } else { dbg('S2 FAIL: no model_id'); return null; }
    } catch (e) { dbg('S2 ERR: $e'); return null; }

    String? worksheetModel;
    try {
      final rows = await searchRead(
        model: 'ir.model',
        domain: [['id', '=', irModelId]],
        fields: ['id', 'model'],
        limit: 1,
      );
      if (rows.isEmpty) { dbg('S3 FAIL'); return null; }
      worksheetModel = rows.first['model']?.toString().trim();
      dbg('S3 OK: $worksheetModel');
    } catch (e) { dbg('S3 ERR: $e'); return null; }
    if (worksheetModel == null || worksheetModel.isEmpty) return null;

    Map<String, dynamic> visibleFields = {};
    try {
      final allF = await callMethod(
        model: worksheetModel, method: 'fields_get',
        args: [], kwargs: <String, dynamic>{},
      );
      if (allF is Map) {
        const skipTypes = {'many2many', 'one2many', 'binary', 'reference', 'many2one'};
        const skipNames = {'x_project_task_id', 'x_name', 'id', 'display_name',
          '__last_update', 'create_uid', 'write_uid', 'create_date', 'write_date'};
        for (final e in (allF as Map).entries) {
          final key = e.key as String;
          final def = e.value as Map;
          if (skipNames.contains(key)) continue;
          if (skipTypes.contains(def['type']?.toString())) continue;
          if (!key.startsWith('x_')) continue;
          visibleFields[key] = def;
        }
      }
      dbg('S4 OK: ${visibleFields.length} fields');
    } catch (e) { dbg('S4 ERR: $e'); return null; }
    if (visibleFields.isEmpty) return null;

    List<Map<String, dynamic>> rows = [];
    try {
      rows = await searchRead(
        model: worksheetModel,
        domain: [['x_project_task_id', '=', taskId]],
        fields: ['id', 'x_project_task_id', ...visibleFields.keys],
        limit: 1,
      );
    } catch (e) { dbg('S5 ERR: $e'); }

    return {
      'model': worksheetModel,
      'taskField': 'x_project_task_id',
      'fields': visibleFields,
      'record': rows.isNotEmpty ? rows.first : null,
    };
  }

  Future<bool> saveWorksheetValues({
    required String model,
    required String taskField,
    required int taskId,
    required Map<String, dynamic> values,
    int? existingRecordId,
  }) async {
    if (values.isEmpty) return false;

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/worksheet/save'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {
            'task_id': taskId,
            'model': model,
            'values': values,
            if (existingRecordId != null) 'existing_record_id': existingRecordId,
          },
        }),
      ).timeout(const Duration(seconds: 20));
      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] != null) {
          final result = decoded['result'] as Map<String, dynamic>;
          if (result['success'] == true) {
            print('[saveWorksheet] saved via endpoint, record_id=${result['record_id']}');
            return true;
          }
          print('[saveWorksheet] endpoint error: ${result['error']}');
        }
      }
    } catch (e) {
      print('[saveWorksheet] endpoint exception: $e — falling back to callMethod');
    }

    if (_isPortalUser) {
      print('[saveWorksheet] portal user — FSM endpoint failed, no ORM fallback');
      return false;
    }

    try {
      if (existingRecordId != null) {
        await callMethod(model: model, method: 'write',
            args: [[existingRecordId], values]);
      } else {
        final newId = await callMethod(model: model, method: 'create',
            args: [{'x_project_task_id': taskId, ...values}]);
        return newId != null;
      }
      return true;
    } catch (_) {}
    return false;
  }

  Future<List<Map<String, dynamic>>> fetchEquipment() => searchRead(
    model: 'maintenance.equipment',
    domain: [],
    fields: ['id', 'name', 'partner_id', 'location', 'serial_no', 'category_id'],
  );

  Future<List<Map<String, dynamic>>> fetchFSMMaterials(int taskId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/materials'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_id': taskId},
        }),
      ).timeout(const Duration(seconds: 20));
      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] != null) {
          final result = decoded['result'] as Map<String, dynamic>;
          if (result['error'] == null) {
            final allMats = List<Map<String, dynamic>>.from(
                result['materials'] as List? ?? []);
            final mats = allMats.where((m) {
              final qty = (m['product_uom_qty'] ?? m['quantity'] ?? m['qty'] ?? 0);
              return (qty is num) ? qty > 0 : true;
            }).toList();
            print('[fetchFSMMaterials] endpoint OK → ${mats.length} materials');
            return mats;
          }
          print('[fetchFSMMaterials] endpoint error: ${result['error']}');
        }
      }
    } catch (e) {
      print('[fetchFSMMaterials] endpoint error: $e — falling back');
    }

    try {
      final taskRows = await searchRead(
        model: 'project.task',
        domain: [['id', '=', taskId]],
        fields: ['id', 'sale_order_id'],
        limit: 1,
      );
      if (taskRows.isNotEmpty) {
        final soField = taskRows.first['sale_order_id'];
        if (soField is List && soField.isNotEmpty) {
          final orderId = soField[0] as int;
          try {
            final lines = await searchRead(
              model: 'sale.order.line',
              domain: [['order_id', '=', orderId], ['task_id', '=', taskId], ['product_id', '!=', false]],
              fields: ['id', 'product_id', 'product_uom_qty', 'qty_delivered', 'price_unit', 'name'],
              limit: 200,
            );
            final nonZeroLines = lines.where((l) {
              final qty = (l['product_uom_qty'] as num? ?? 0);
              return qty > 0;
            }).toList();
            print('[fetchFSMMaterials] SOL fallback → ${nonZeroLines.length} lines');
            return nonZeroLines.map((l) {
              final prod = l['product_id'];
              final qty = (l['product_uom_qty'] ?? l['qty_delivered'] ?? 0);
              return {
                ...l,
                'product_uom_qty': qty,
                'name': prod is List ? prod[1].toString() : (l['name'] ?? ''),
                'default_code': '',
                'list_price': l['price_unit'] ?? 0,
                'image_128': false,
              };
            }).toList();
          } catch (e) {
            print('[fetchFSMMaterials] SOL fallback error: $e');
          }
          print('[fetchFSMMaterials] SOL fallback → 0 lines');
          return [];
        }
      }
    } catch (e) {
      print('[fetchFSMMaterials] SOL fallback error: $e');
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> fetchProductsViaFSM() async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/products'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'id': 1, 'params': {}}),
      ).timeout(const Duration(seconds: 30));
      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] != null) {
          final result = decoded['result'] as Map<String, dynamic>;
          if (result['error'] == null) {
            return List<Map<String, dynamic>>.from(result['products'] as List? ?? []);
          }
        }
      }
    } catch (e) {
      print('[fetchProductsViaFSM] error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchFieldServiceProducts() => searchRead(
    model: 'product.product',
    domain: [['sale_ok', '=', true], ['type', 'in', ['product', 'consu']]],
    fields: ['id', 'name', 'default_code', 'list_price', 'qty_available', 'categ_id', 'image_128', 'type'],
    limit: 2000,
  );

  Future<List<Map<String, dynamic>>> fetchAllProducts() => searchRead(
    model: 'product.product',
    domain: [],
    fields: ['id', 'name', 'default_code', 'list_price', 'qty_available', 'categ_id', 'image_128', 'type'],
    limit: 2000,
  );

  Future<List<Map<String, dynamic>>> fetchMaintenanceRequests() => searchRead(
    model: 'maintenance.request',
    domain: [],
    fields: [
      'id', 'name', 'stage_id', 'priority', 'maintenance_type',
      'equipment_id', 'user_id', 'request_date', 'description',
    ],
  );

  Future<List<Map<String, dynamic>>> fetchTodayTimesheets(int userId) async {
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    try {
      return await searchRead(
        model: 'account.analytic.line',
        domain: [
          ['employee_id.user_id', '=', userId],
          ['date', '=', dateStr],
        ],
        fields: ['id', 'name', 'unit_amount', 'task_id', 'date'],
        limit: 100,
      );
    } catch (_) { return []; }
  }

  Future<int?> _getEmployeeId() async {
    if (_uid == null) return null;
    try {
      final res = await searchRead(
        model: 'hr.employee',
        domain: [['user_id', '=', _uid]],
        fields: ['id'],
        limit: 1,
      );
      if (res.isNotEmpty) return res.first['id'] as int?;
    } catch (_) {}
    return null;
  }

  Future<int?> _getProjectId(int taskId) async {
    try {
      final res = await searchRead(
        model: 'project.task',
        domain: [['id', '=', taskId]],
        fields: ['project_id'],
        limit: 1,
      );
      if (res.isNotEmpty) {
        final p = res.first['project_id'];
        if (p is List && p.isNotEmpty) return p[0] as int?;
      }
    } catch (_) {}
    return null;
  }

  Future<int?> createTimesheetEntry({
    required int taskId,
    required double hours,
    required String description,
  }) async {
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';

    final projectId = await _getProjectId(taskId);
    final employeeId = await _getEmployeeId();

    final vals = <String, dynamic>{
      'task_id': taskId,
      'unit_amount': hours,
      'name': description,
      'date': dateStr,
    };
    if (projectId != null) vals['project_id'] = projectId;
    if (employeeId != null) vals['employee_id'] = employeeId;

    print('[OdooService] createTimesheetEntry task=$taskId hours=$hours project=$projectId employee=$employeeId date=$dateStr vals=$vals');
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final result = await callMethod(
          model: 'account.analytic.line',
          method: 'create',
          args: [vals],
        );
        print('[OdooService] createTimesheetEntry result: $result');
        if (result is int && result > 0) {
          try {
            await callMethod(
              model: 'project.task', method: 'write',
              args: [[taskId], {'effective_hours': hours}],
            );
            print('[OdooService] wrote effective_hours=$hours to task');
          } catch (e) { print('[OdooService] effective_hours write error: $e'); }
          return result;
        }
      } catch (e) {
        print('[OdooService] createTimesheetEntry attempt $attempt error: $e');
        if (attempt < 2) await Future.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }

  String _utcNow() =>
      DateTime.now().toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;

  Future<Map<String, dynamic>?> _fsmTaskRoute(
      String endpoint, Map<String, dynamic> params) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': params,
        }),
      ).timeout(const Duration(seconds: 20));
      final raw = res.body.trim();
      if (raw.toLowerCase().startsWith('<!')) {
        print('[OdooService] $endpoint returned HTML (session expired?)');
        return null;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['error'] != null) {
        print('[OdooService] $endpoint JSON-RPC error: ${decoded['error']}');
        return null;
      }
      final result = decoded['result'];
      if (result is Map<String, dynamic>) {
        if (result['success'] == false || result['error'] != null) {
          print('[OdooService] $endpoint app error: ${result['error']} (success=${result['success']})');
        }
        return result;
      }
      return null;
    } catch (e) {
      print('[OdooService] $endpoint exception: $e');
      return null;
    }
  }

  // ── START TASK (Portal-Safe) ──────────────────────────────────────────────
  // Returns a map: {'success': bool, 'error': String?, 'data': Map?}
  // Callers must check ['error'] == 'no_location' to show the location dialog.
  Future<Map<String, dynamic>> startTaskResult(
    int taskId, {
    double? userLat,
    double? userLng,
  }) async {
    print('[OdooService] startTask($taskId) portal=$_isPortalUser lat=$userLat lng=$userLng');

    final body = <String, dynamic>{'task_id': taskId};
    if (userLat != null) body['user_lat'] = userLat;
    if (userLng != null) body['user_lng'] = userLng;

    final r = await _fsmTaskRoute('/fsm/task/start', body);

    // Server explicitly rejected due to missing location
    if (r != null && r['error'] == 'no_location') {
      print('[OdooService] startTask: no_location');
      return {'success': false, 'error': 'no_location', 'message': r['message']};
    }

    // Server rejected: outside geofence radius
    if (r != null && r['error'] == 'outside_geofence') {
      print('[OdooService] startTask: outside_geofence dist=${r['distance_m']}m restriction=${r['restriction_m']}m');
      return {
        'success': false,
        'error': 'outside_geofence',
        'message': r['message'],
        'distance_m': r['distance_m'],
        'restriction_m': r['restriction_m'],
      };
    }

    if (r != null && r['success'] == true) {
      print('[OdooService] startTask: route OK timer_start=${r['timer_start']}');
      if (_isPortalUser) {
        print('[OdooService] startTask: portal — trusting route success, skip verify');
        return {'success': true, 'error': null, 'data': r};
      }
      final isRunning = await verifyTimerRunning(taskId);
      if (isRunning) {
        print('[OdooService] startTask: verification OK');
        return {'success': true, 'error': null, 'data': r};
      }
      print('[OdooService] startTask: server didn\'t persist timer_start after route success');
      return {'success': false, 'error': 'verify_failed'};
    }

    if (_isPortalUser) {
      final serverErr = r?['error'] ?? 'route returned null (network/session error)';
      print('[OdooService] startTask: portal route FAILED — server said: $serverErr');
      return {'success': false, 'error': serverErr};
    }

    // Internal user fallback
    final ok = await _startTaskInternal(taskId);
    return {'success': ok, 'error': ok ? null : 'internal_fallback_failed'};
  }

  /// Legacy bool wrapper — kept for callers that don't need the error detail.
  Future<bool> startTask(int taskId, {double? userLat, double? userLng}) async {
    final res = await startTaskResult(taskId, userLat: userLat, userLng: userLng);
    return res['success'] == true;
  }

  /// Start task via ORM directly, bypassing the server-side FSM location gate.
  /// Call this only AFTER Flutter-side GPS proximity check has already passed.
  Future<bool> startTaskBypassed(int taskId) async {
    print('[OdooService] startTaskBypassed($taskId) — skipping location gate');
    return await _startTaskInternal(taskId);
  }

  Future<bool> _startTaskInternal(int taskId) async {
    for (final method in ['action_timer_start', 'action_assign_hours']) {
      try {
        await callMethod(
          model: 'project.task', method: method, args: [[taskId]],
          kwargs: {'context': _uid != null
              ? {'uid': _uid, 'active_id': taskId, 'active_ids': [taskId]}
              : {'active_id': taskId}},
        );
        print('[OdooService] startTask ORM: $method OK');
        break;
      } catch (e) { print('[OdooService] startTask ORM $method: $e'); }
    }
    try {
      final now = _utcNow();
      await callMethod(model: 'project.task', method: 'write',
          args: [[taskId], {'timer_start': now}]);
      print('[OdooService] startTask: wrote timer_start=$now');
      return true;
    } catch (e) {
      print('[OdooService] startTask write error: $e');
      return false;
    }
  }

  // ── RESUME TASK (Portal-Safe) ─────────────────────────────────────────────
  Future<bool> resumeTask(int taskId) async {
    print('[OdooService] resumeTask($taskId) portal=$_isPortalUser');

    final r = await _fsmTaskRoute('/fsm/task/resume', {'task_id': taskId});
    if (r != null && r['success'] == true) {
      print('[OdooService] resumeTask: route OK timer_start=${r['timer_start']}');
      // FIX (portal): skip verifyTimerRunning for portal users — same race as startTask.
      if (_isPortalUser) {
        print('[OdooService] resumeTask: portal — trusting route success, skip verify');
        return true;
      }
      final isRunning = await verifyTimerRunning(taskId);
      if (isRunning) {
        print('[OdooService] resumeTask: verification OK');
        return true;
      }
      print('[OdooService] resumeTask: server didn\'t persist timer_start after route success');
      return false;
    }

    if (_isPortalUser) {
      final serverErr = r?['error'] ?? 'route returned null (network/session error)';
      print('[OdooService] resumeTask: portal route FAILED — server said: $serverErr');
      return false;
    }

    return _resumeTaskInternal(taskId);
  }

  Future<bool> _resumeTaskInternal(int taskId) async {
    for (final method in ['action_timer_resume', 'action_timer_start']) {
      try {
        await callMethod(
          model: 'project.task', method: method, args: [[taskId]],
          kwargs: {'context': _uid != null
              ? {'uid': _uid, 'active_id': taskId, 'active_ids': [taskId]}
              : {'active_id': taskId}},
        );
        print('[OdooService] resumeTask ORM: $method OK');
        break;
      } catch (e) { print('[OdooService] resumeTask ORM $method: $e'); }
    }
    try {
      final now = _utcNow();
      await callMethod(model: 'project.task', method: 'write',
          args: [[taskId], {'timer_start': now}]);
      print('[OdooService] resumeTask: wrote timer_start=$now');
      return true;
    } catch (e) {
      print('[OdooService] resumeTask write error: $e');
      return false;
    }
  }

  // ── PAUSE TASK (Portal-Safe) ──────────────────────────────────────────────
  Future<bool> pauseTask(int taskId) async {
    print('[OdooService] pauseTask($taskId) portal=$_isPortalUser');

    final r = await _fsmTaskRoute('/fsm/task/pause', {'task_id': taskId});
    if (r != null && r['success'] == true) {
      print('[OdooService] pauseTask: route OK');
      // FIX (portal): skip verifyTimerRunning for portal users.
      // After a direct write({'timer_start': False}) on the server, reading back
      // timer_start can still return the old value within the same request
      // cycle on some Odoo cache configurations, causing the verify to report
      // "still running" and pauseTask to return false even though it succeeded.
      if (_isPortalUser) {
        print('[OdooService] pauseTask: portal — trusting route success, skip verify');
        return true;
      }
      // Verify timer is cleared on server
      final isRunning = await verifyTimerRunning(taskId);
      if (!isRunning) {
        print('[OdooService] pauseTask: verification OK — timer cleared');
        return true;
      }
      print('[OdooService] pauseTask: timer still running after route success');
      return false;
    }

    final serverErr = r?['error'] ?? 'route returned null (network/session error)';
    print('[OdooService] pauseTask: FAILED — server said: $serverErr');

    if (_isPortalUser) return false;

    // Internal user fallback only
    try {
      await callMethod(model: 'project.task', method: 'action_timer_pause',
          args: [[taskId]],
          kwargs: {'context': _uid != null
              ? {'uid': _uid, 'active_id': taskId, 'active_ids': [taskId]}
              : {}});
      print('[OdooService] pauseTask ORM: action_timer_pause OK');
      return true;
    } catch (e) {
      print('[OdooService] pauseTask ORM error: $e');
      return false;
    }
  }

  // ── STOP TASK (Portal-Safe) ───────────────────────────────────────────────
  Future<bool> stopTask(int taskId) async {
    print('[OdooService] stopTask($taskId) portal=$_isPortalUser');

    final r = await _fsmTaskRoute('/fsm/task/pause', {'task_id': taskId});
    if (r != null && r['success'] == true) {
      print('[OdooService] stopTask: route pause OK');
      final isRunning = await verifyTimerRunning(taskId);
      if (!isRunning) {
        print('[OdooService] stopTask: verification OK');
        return true;
      }
      return false;
    }

    if (_isPortalUser) {
      print('[OdooService] stopTask: portal user — route failed, not falling back to ORM');
      return false;
    }

    for (final vals in [
      {'timer_start': false, 'date_end': _utcNow()},
      {'timer_start': false},
    ]) {
      try {
        await callMethod(model: 'project.task', method: 'write',
            args: [[taskId], vals]);
        print('[OdooService] stopTask: wrote $vals');
        return true;
      } catch (e) { print('[OdooService] stopTask write error: $e'); }
    }
    return !await verifyTimerRunning(taskId);
  }

  Future<bool> saveWorksheet({
    required int taskId,
    required Map<String, bool> checks,
    String? notes,
  }) async {
    if (checks.isEmpty) return false;

    final htmlLines = checks.entries.map((e) =>
    '<li style="list-style:none">${e.value ? '✅' : '☐'} ${e.key}</li>').join('');
    final htmlContent = '<ul>$htmlLines</ul>'
        + (notes != null && notes.trim().isNotEmpty
            ? '<p><b>Notes:</b> ${notes.trim()}</p>'
            : '');

    try {
      final taskFieldDefs = await callMethod(
        model: 'project.task', method: 'fields_get',
        args: [], kwargs: {'attributes': ['type', 'relation', 'string']},
      );
      if (taskFieldDefs is Map) {
        final candidateFields = <String>[];
        for (final entry in (taskFieldDefs as Map).entries) {
          final key = entry.key as String;
          final val = entry.value as Map;
          final ftype = val['type']?.toString() ?? '';
          final fname = (val['string'] ?? key).toString().toLowerCase();
          if ((ftype == 'one2many' || ftype == 'many2one') &&
              (key.contains('worksheet') || fname.contains('worksheet'))) {
            candidateFields.add(key);
          }
        }

        for (final known in ['worksheet_line_ids', 'fsm_worksheet_id', 'worksheet_id']) {
          if (taskFieldDefs.containsKey(known) && !candidateFields.contains(known)) {
            candidateFields.add(known);
          }
        }

        for (final fieldName in candidateFields) {
          try {
            final fdef = taskFieldDefs[fieldName] as Map;
            final ftype = fdef['type']?.toString() ?? '';
            final relModel = fdef['relation']?.toString() ?? '';
            if (relModel.isEmpty) continue;

            if (ftype == 'one2many') {
              final lineFields = await callMethod(
                model: relModel, method: 'fields_get',
                args: [], kwargs: {'attributes': ['type', 'string']},
              );
              if (lineFields is Map) {
                String nameField = 'name';
                for (final f in ['name', 'description', 'title', 'label']) {
                  if (lineFields.containsKey(f)) { nameField = f; break; }
                }
                String? doneField;
                for (final f in ['done', 'is_done', 'checked', 'completed']) {
                  if ((lineFields[f] as Map?)?['type'] == 'boolean') {
                    doneField = f; break;
                  }
                }

                String taskLink = 'task_id';
                for (final f in ['task_id', 'project_task_id', 'fsm_task_id']) {
                  if (lineFields.containsKey(f)) { taskLink = f; break; }
                }

                final existing = await searchRead(
                  model: relModel,
                  domain: [[taskLink, '=', taskId]],
                  fields: ['id'], limit: 200,
                );
                if (existing.isNotEmpty) {
                  await callMethod(model: relModel, method: 'unlink',
                      args: [existing.map((e) => e['id']).toList()]);
                }
                for (final entry in checks.entries) {
                  final data = <String, dynamic>{taskLink: taskId, nameField: entry.key};
                  if (doneField != null) data[doneField] = entry.value;
                  await callMethod(model: relModel, method: 'create', args: [data]);
                }
                return true;
              }
            } else if (ftype == 'many2one') {
              final wsFields = await callMethod(
                model: relModel, method: 'fields_get',
                args: [], kwargs: {'attributes': ['type']},
              );
              if (wsFields is Map) {
                String? noteField;
                for (final f in ['notes', 'description', 'content', 'note', 'worksheet_description']) {
                  if (wsFields.containsKey(f)) { noteField = f; break; }
                }

                final taskData = await searchRead(
                  model: 'project.task',
                  domain: [['id', '=', taskId]],
                  fields: ['id', fieldName], limit: 1,
                );
                if (taskData.isNotEmpty && taskData.first[fieldName] != false) {
                  final wsId = (taskData.first[fieldName] as List)[0];
                  final data = <String, dynamic>{};
                  if (noteField != null) data[noteField] = htmlContent;
                  if (data.isNotEmpty) {
                    await callMethod(model: relModel, method: 'write', args: [[wsId], data]);
                  }
                } else {
                  final data = <String, dynamic>{};
                  if (noteField != null) data[noteField] = htmlContent;
                  final newId = await callMethod(model: relModel, method: 'create', args: [data]);
                  if (newId != null) {
                    await callMethod(model: 'project.task', method: 'write',
                        args: [[taskId], {fieldName: newId}]);
                  }
                }
                return true;
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    for (final worksheetModel in ['project.task.worksheet', 'fsm.worksheet', 'maintenance.worksheet']) {
      try {
        final fields = await callMethod(
          model: worksheetModel, method: 'fields_get',
          args: [], kwargs: {'attributes': ['type']},
        );
        if (fields is Map) {
          final taskField = fields.containsKey('task_id') ? 'task_id' : 'project_task_id';
          if (!fields.containsKey(taskField)) continue;
          String? noteField;
          for (final f in ['notes', 'description', 'content', 'worksheet_description', 'note']) {
            if (fields.containsKey(f)) { noteField = f; break; }
          }
          final existing = await searchRead(
            model: worksheetModel,
            domain: [[taskField, '=', taskId]],
            fields: ['id'], limit: 1,
          );
          final data = <String, dynamic>{taskField: taskId};
          if (noteField != null) data[noteField] = htmlContent;
          if (existing.isNotEmpty) {
            await callMethod(model: worksheetModel, method: 'write',
                args: [[existing.first['id']], data]);
          } else {
            await callMethod(model: worksheetModel, method: 'create', args: [data]);
          }
          return true;
        }
      } catch (_) {}
    }

    try {
      await callMethod(
        model: 'project.task', method: 'message_post',
        args: [[taskId]],
        kwargs: {
          'body': '<p><strong>Maintenance Tasks (Worksheet)</strong></p>$htmlContent',
          'message_type': 'comment',
          'subtype_xmlid': 'mail.mt_note',
        },
      );
      return true;
    } catch (_) {}

    try {
      await callMethod(
        model: 'project.task', method: 'write',
        args: [[taskId], {'description': htmlContent}],
      );
      return true;
    } catch (_) {}

    return false;
  }

  /// Stop the timer, save the timesheet, and zero the counter.
  ///
  /// The task stage is NOT moved to "done" here.
  /// The task is only fully completed when action_fsm_validate is called
  /// from the Odoo backend (e.g. from the Odoo web UI).
  Future<bool> markTaskDone(
    int taskId, {
    double elapsedHours = 0,
    String description = 'Maintenance visit',
    // Optional: pass worksheet data to save atomically in the same request.
    String? worksheetModel,
    Map<String, dynamic>? worksheetValues,
    int? worksheetRecordId,
    // Flutter already verified location — tell server to skip its own gate.
    bool bypassLocationCheck = false,
    // GPS coords of the technician at time of completion
    double? userLat,
    double? userLng,
  }) async {
    print('[OdooService] markTaskDone($taskId) elapsedHours=$elapsedHours portal=$_isPortalUser bypass=$bypassLocationCheck lat=$userLat lng=$userLng');

    final body = <String, dynamic>{
      'task_id': taskId,
      'elapsed_hours': elapsedHours,
      'description': description,
      if (bypassLocationCheck) 'bypass_location_check': true,
      if (userLat != null) 'user_lat': userLat,
      if (userLng != null) 'user_lng': userLng,
    };

    // Include worksheet params only when both model and values are provided.
    if (worksheetModel != null && worksheetValues != null && worksheetValues.isNotEmpty) {
      body['worksheet_model'] = worksheetModel;
      body['worksheet_values'] = worksheetValues;
      if (worksheetRecordId != null) body['worksheet_record_id'] = worksheetRecordId;
      print('[OdooService] markTaskDone: including worksheet model=$worksheetModel '
            'fields=${worksheetValues.keys.toList()} record=$worksheetRecordId');
    }

    final r = await _fsmTaskRoute('/fsm/task/complete', body);

    // Server explicitly rejected due to missing customer location.
    if (r != null && r['error'] == 'no_location') {
      print('[OdooService] markTaskDone: no_location');
      throw Exception('no_location:${r["message"] ?? "Customer location is not set."}');
    }

    // Server rejected: already completed
    if (r != null && r['error'] == 'already_completed') {
      print('[OdooService] markTaskDone: already_completed');
      throw Exception('already_completed:${r["message"] ?? "Task already completed."}');
    }

    // Server rejected: outside geofence radius
    if (r != null && r['error'] == 'outside_geofence') {
      print('[OdooService] markTaskDone: outside_geofence dist=${r['distance_m']}m restriction=${r['restriction_m']}m');
      throw Exception('outside_geofence:${r["message"] ?? "Outside allowed radius."}');
    }

    if (r != null && r['success'] == true) {
      final timesheetId  = r['timesheet_id'];
      final sessionHours = r['session_hours'];
      final ws           = r['worksheet'] as Map?;
      print('[OdooService] markTaskDone: OK ts=$timesheetId session_hours=$sessionHours '
            'worksheet=${ws?["action"]} ws_record=${ws?["record_id"]} ws_err=${ws?["error"]}');
      return true;
    }

    final errorMsg = r?['error'] ?? 'route returned null (network/session error)';
    print('[OdooService] markTaskDone: FAILED — $errorMsg');
    return false;
  }

  Future<String?> _discoverMaterialField() async {
    try {
      final fields = await callMethod(
        model: 'project.task', method: 'fields_get',
        args: [], kwargs: {'attributes': ['string', 'type', 'relation']},
      );
      if (fields is Map) {
        for (final candidate in [
          'material_line_ids', 'product_ids', 'sale_line_ids',
          'task_material_ids', 'component_ids', 'stock_move_ids',
        ]) {
          if (fields.containsKey(candidate)) return candidate;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> addMaterialsBatch({
    required int taskId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/materials/add'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_id': taskId, 'items': items},
        }),
      ).timeout(const Duration(seconds: 30));
      final raw = res.body.trim();
      print('[addMaterialsBatch] endpoint raw: $raw');
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] != null) {
          final result = decoded['result'] as Map<String, dynamic>;
          if (result['success'] == true) return result;
          print('[addMaterialsBatch] endpoint failed: ${result['error']}');
        }
      }
    } catch (e) {
      print('[addMaterialsBatch] endpoint error: $e');
    }

    final results = <Map<String, dynamic>>[];
    for (final item in items) {
      final productId = item['product_id'] as int?;
      final qty = (item['qty'] as num?)?.toDouble() ?? 1.0;
      if (productId == null) continue;
      final err = await addMaterialToTask(
        taskId: taskId,
        productId: productId,
        qty: qty,
      );
      results.add({'product_id': productId, 'qty': qty, 'success': err == null, 'error': err});
    }
    final allOk = results.isNotEmpty && results.every((r) => r['success'] == true);
    return {'success': allOk, 'results': results};
  }

  Future<String?> addMaterialToTask({
    required int taskId,
    required int productId,
    required double qty,
    String productName = '',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/materials/add'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {
            'task_id': taskId,
            'items': [{'product_id': productId, 'qty': qty}],
          },
        }),
      ).timeout(const Duration(seconds: 20));
      final raw = res.body.trim();
      print('[addMaterialToTask] endpoint response: $raw');
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] != null) {
          print('[addMaterialToTask] JSON-RPC error: ${decoded['error']}');
        } else if (decoded['result'] != null) {
          final result = decoded['result'] as Map<String, dynamic>;
          if (result['success'] == true) return null;
          print('[addMaterialToTask] endpoint error: ${result['error']} results: ${result['results']}');
          final firstError = (result['results'] as List? ?? [])
              .where((r) => r['success'] != true)
              .map((r) => r['error']?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .firstOrNull;
          if (firstError != null) throw Exception(firstError);
        }
      }
    } catch (e) {
      print('[addMaterialToTask] sudo endpoint error: $e — fallback');
    }

    if (_isPortalUser) {
      print('[addMaterialToTask] portal user — FSM endpoint failed, no ORM fallback');
      return 'Could not add material. Please check your connection and try again.';
    }

    final errors = <String>[];

    try {
      final taskRows = await searchRead(
        model: 'project.task',
        domain: [['id', '=', taskId]],
        fields: ['id', 'sale_order_id', 'partner_id'],
        limit: 1,
      );
      if (taskRows.isNotEmpty) {
        int? orderId;
        final soField = taskRows.first['sale_order_id'];
        if (soField is List && soField.isNotEmpty) orderId = soField[0] as int;
        if (orderId == null) {
          final pf = taskRows.first['partner_id'];
          if (pf is List && pf.isNotEmpty) {
            final newSo = await callMethod(model: 'sale.order', method: 'create',
                args: [{'partner_id': pf[0] as int}]);
            if (newSo is int) {
              orderId = newSo;
              await callMethod(model: 'project.task', method: 'write',
                  args: [[taskId], {'sale_order_id': orderId}]);
            }
          }
        }
        if (orderId != null) {
          final prods = await searchRead(model: 'product.product',
              domain: [['id', '=', productId]], fields: ['id', 'display_name', 'list_price'], limit: 1);
          final price = prods.isNotEmpty ? (prods.first['list_price'] ?? 0) : 0;
          final name = prods.isNotEmpty ? (prods.first['display_name'] ?? '') : '';
          await callMethod(model: 'sale.order.line', method: 'create',
              args: [{'order_id': orderId, 'product_id': productId,
                'product_uom_qty': qty, 'task_id': taskId,
                'price_unit': price, 'name': name}]);
          return null;
        }
      }
    } catch (e) { errors.add('sale.order.line: $e'); }

    try {
      final matFields = await callMethod(
        model: 'project.task.material', method: 'fields_get',
        args: [], kwargs: {'attributes': ['type']},
      );
      if (matFields is Map) {
        String qtyField = 'product_uom_qty';
        for (final f in ['product_uom_qty', 'quantity', 'qty']) {
          if (matFields.containsKey(f) && matFields[f]['type'] == 'float') {
            qtyField = f; break;
          }
        }
        String prodField = 'product_id';
        for (final f in ['product_id', 'product_template_id']) {
          if (matFields.containsKey(f)) { prodField = f; break; }
        }

        final existing = await searchRead(
          model: 'project.task.material',
          domain: [['task_id', '=', taskId], [prodField, '=', productId]],
          fields: ['id', qtyField],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          final existingQty = (existing.first[qtyField] as num? ?? 0).toDouble();
          await callMethod(
            model: 'project.task.material', method: 'write',
            args: [[existing.first['id']], {qtyField: existingQty + qty}],
          );
        } else {
          await callMethod(
            model: 'project.task.material', method: 'create',
            args: [{'task_id': taskId, prodField: productId, qtyField: qty}],
          );
        }

        try {
          await callMethod(
            model: 'project.task', method: 'write',
            args: [[taskId], {'product_ids': [[4, productId]]}],
          );
        } catch (_) {}

        return null;
      }
    } catch (e) { errors.add('task.material introspect: $e'); }

    for (final method in ['action_fsm_add_product', 'fsm_add_product',
      'action_add_product', 'add_product']) {
      try {
        await callMethod(
          model: 'project.task', method: method, args: [[taskId]],
          kwargs: {'product_id': productId, 'quantity': qty},
        );
        return null;
      } catch (e) { errors.add('task.$method: $e'); }
    }

    try {
      final wizardId = await callMethod(
        model: 'fsm.product.wizard', method: 'create',
        args: [{'task_id': taskId, 'product_id': productId, 'quantity': qty}],
      );
      if (wizardId != null) {
        await callMethod(model: 'fsm.product.wizard',
            method: 'action_confirm', args: [[wizardId]]);
        return null;
      }
    } catch (e) { errors.add('fsm.product.wizard: $e'); }

    try {
      final fsmFieldDefs = await callMethod(
        model: 'fsm.stock.tracking', method: 'fields_get',
        args: [], kwargs: {'attributes': ['type', 'string', 'required']},
      );
      if (fsmFieldDefs is Map) {
        final allFields = (fsmFieldDefs as Map).keys.toList();
        errors.add('fsm.fields=${allFields.take(20).join(",")}');

        String taskField = 'task_id';
        for (final f in ['task_id', 'project_task_id', 'fsm_task_id']) {
          if (fsmFieldDefs.containsKey(f)) { taskField = f; break; }
        }

        final hasTrackingLines = fsmFieldDefs.containsKey('tracking_line_ids');

        if (hasTrackingLines) {
          errors.add('fsm.using tracking_line_ids pattern');
          for (final lineModel in ['fsm.stock.tracking.line', 'fsm.stock.tracking.move']) {
            try {
              final lineFields = await callMethod(model: lineModel,
                  method: 'fields_get', args: [], kwargs: {'attributes': ['type']});
              if (lineFields is Map) {
                String lineQtyField = 'quantity';
                for (final f in ['quantity', 'qty', 'product_uom_qty', 'qty_done']) {
                  if (lineFields.containsKey(f) && lineFields[f]['type'] == 'float') {
                    lineQtyField = f; break;
                  }
                }
                errors.add('fsm.line model=$lineModel qty=$lineQtyField');
                await callMethod(
                  model: 'fsm.stock.tracking', method: 'create',
                  args: [{taskField: taskId, 'product_id': productId,
                    'tracking_line_ids': [[0, 0, {lineQtyField: qty}]]}],
                );
                return null;
              }
            } catch (e) { errors.add('fsm.line.$lineModel: $e'); }
          }

          try {
            await callMethod(model: 'fsm.stock.tracking', method: 'create',
                args: [{taskField: taskId, 'product_id': productId}]);
            return null;
          } catch (e) { errors.add('fsm.stock.tracking no-qty: $e'); }
        } else {
          String qtyField = 'quantity';
          for (final f in ['quantity', 'qty', 'product_uom_qty', 'product_qty',
            'qty_done', 'qty_forecasted', 'reserved_qty']) {
            if (fsmFieldDefs.containsKey(f) && fsmFieldDefs[f]['type'] == 'float') {
              qtyField = f; break;
            }
          }
          errors.add('fsm.using task=$taskField qty=$qtyField');
          try {
            await callMethod(model: 'fsm.stock.tracking', method: 'create',
                args: [{taskField: taskId, 'product_id': productId, qtyField: qty}]);
            return null;
          } catch (e) { errors.add('fsm.stock.tracking create: $e'); }
        }
      }
    } catch (e) { errors.add('fsm.stock.tracking fields_get: $e'); }

    final materialField = await _discoverMaterialField();
    if (materialField != null) {
      for (final qtyField in ['product_uom_qty', 'quantity']) {
        try {
          await callMethod(
            model: 'project.task', method: 'write',
            args: [[taskId], {materialField: [[0, 0, {'product_id': productId, qtyField: qty}]]}],
          );
          return null;
        } catch (e) { errors.add('task.$materialField[$qtyField]: $e'); }
      }
    }

    try {
      final task = await searchRead(model: 'project.task',
          domain: [['id', '=', taskId]], fields: ['id', 'sale_order_id'], limit: 1);
      if (task.isNotEmpty && task.first['sale_order_id'] != false) {
        final soId = (task.first['sale_order_id'] as List)[0];
        await callMethod(model: 'sale.order.line', method: 'create',
            args: [{'order_id': soId, 'product_id': productId,
              'product_uom_qty': qty, 'task_id': taskId}]);
        return null;
      } else { errors.add('no sale_order_id on task'); }
    } catch (e) { errors.add('sale.order.line: $e'); }

    return errors.join(' | ');
  }

  Future<bool> deleteMaterial({
    required int taskId,
    required int materialId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/materials/delete'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_id': taskId, 'material_id': materialId},
        }),
      ).timeout(const Duration(seconds: 15));
      final raw = res.body.trim();
      print('[deleteMaterial] endpoint response: $raw');
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] != null) {
          print('[deleteMaterial] endpoint JSON-RPC error: ${decoded['error']}');
        } else if (decoded['result'] != null) {
          final result = decoded['result'] as Map<String, dynamic>;
          if (result['success'] == true) return true;
          print('[deleteMaterial] endpoint returned success=false: ${result['error']}');
        }
      }
    } catch (e) {
      print('[deleteMaterial] endpoint exception: $e — trying fallback');
    }

    if (_isPortalUser) {
      print('[deleteMaterial] portal user — FSM endpoint failed, no ORM fallback');
      return false;
    }

    try {
      await callMethod(
        model: 'sale.order.line', method: 'write',
        args: [[materialId], {'product_uom_qty': 0}],
      );
      print('[deleteMaterial] fallback set qty=0 on SOL succeeded');
      return true;
    } catch (e) {
      print('[deleteMaterial] fallback set qty=0 on SOL failed: $e');
    }

    return false;
  }

  Future<Map<String, dynamic>?> fetchLastAddedMaterial(int taskId, int productId) async {
    try {
      final res = await searchRead(
        model: 'project.task.material',
        domain: [['task_id', '=', taskId], ['product_id', '=', productId]],
        fields: ['id', 'product_id', 'product_uom_qty'],
        limit: 1,
        order: 'id desc',
      );
      if (res.isNotEmpty) return res.first;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchTaskTimingInfo(int taskId) async {
    // ── 1. Portal-safe dedicated route ──────────────────────────────────
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/task/timer_info'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_id': taskId},
        }),
      ).timeout(const Duration(seconds: 15));
      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] is Map) {
          final result = Map<String, dynamic>.from(
              decoded['result'] as Map<String, dynamic>);
          if (result.containsKey('timer_start')) {
            print('[fetchTaskTimingInfo] route OK: timer_start=${result['timer_start']}');
            return result;
          }
        }
      }
    } catch (e) {
      print('[fetchTaskTimingInfo] route error: $e — ORM fallback');
    }

    // ── 2. ORM fallback (internal users only) ────────────────────────────
    if (_isPortalUser) {
      print('[fetchTaskTimingInfo] portal user with no route response');
      return null;
    }

    String? timerStartValue;
    try {
      final timerRes = await searchRead(
        model: 'project.task',
        domain: [['id', '=', taskId]],
        fields: ['id', 'timer_start'],
        limit: 1,
      );
      if (timerRes.isNotEmpty) {
        final v = timerRes.first['timer_start'];
        if (v != null && v != false && v.toString().isNotEmpty) {
          timerStartValue = v.toString();
        }
      }
    } catch (_) {}

    final fieldSets = [
      ['id', 'name', 'stage_id', 'effective_hours', 'total_hours_spent'],
      ['id', 'name', 'stage_id', 'effective_hours'],
      ['id', 'name', 'stage_id'],
    ];

    for (final fields in fieldSets) {
      try {
        final res = await searchRead(
          model: 'project.task',
          domain: [['id', '=', taskId]],
          fields: fields,
          limit: 1,
        );
        if (res.isNotEmpty) {
          final result = Map<String, dynamic>.from(res.first);
          result['timer_start'] = timerStartValue;
          return result;
        }
      } catch (_) { continue; }
    }

    if (timerStartValue != null) {
      return {'id': taskId, 'timer_start': timerStartValue};
    }
    return null;
  }

  /// Fetch partner location data for a task via the dedicated sudo endpoint.
  /// Portal users cannot searchRead res.partner directly, so this route
  /// returns google_map_link_manual / lat / lng with sudo access.
  Future<Map<String, dynamic>?> fetchTaskLocation(int taskId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/task/location'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_id': taskId},
        }),
      ).timeout(const Duration(seconds: 10));
      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] is Map) {
          final result = Map<String, dynamic>.from(
              decoded['result'] as Map<String, dynamic>);
          if (result['success'] == true) {
            print('[fetchTaskLocation] OK task=$taskId '
                'manual=${result['google_map_link_manual']} '
                'lat=${result['partner_latitude']}');
            return result;
          }
        }
      }
    } catch (e) {
      print('[fetchTaskLocation] error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchSurveyTasks(int userId) async {
    final fieldSets = [
      ['id', 'name', 'stage_id', 'partner_id', 'user_ids',
        'date_deadline', 'priority', 'fs_task_type_id'],
      ['id', 'name', 'stage_id', 'partner_id', 'user_ids',
        'date_deadline', 'priority'],
    ];

    Future<List<Map<String, dynamic>>> tryDomain(List<dynamic> domain) async {
      for (final fields in fieldSets) {
        try {
          return await searchRead(
            model: 'project.task', domain: domain,
            fields: fields, limit: 500, order: 'date_deadline desc',
          );
        } catch (_) {}
      }
      return [];
    }

    try {
      final res = await tryDomain([['user_ids', 'in', [userId]]]);
      if (res.isNotEmpty) return res;
    } catch (_) {}

    try {
      final res = await tryDomain([['user_id', '=', userId]]);
      if (res.isNotEmpty) return res;
    } catch (_) {}

    return [];
  }
  // ── Upload customer signature ─────────────────────────────────────────────
  // Sends base-64 PNG bytes to /fsm/task/signature/save.
  // Returns the ir.attachment id on success, or null on failure.
  Future<({bool success, int? attachmentId, String? error})> uploadSignature({
    required int taskId,
    required Uint8List pngBytes,
  }) async {
    try {
      final b64 = base64Encode(pngBytes);
      final ts  = DateTime.now().toUtc().toIso8601String().replaceAll(':', '').replaceAll('-', '').split('.').first;
      final filename = 'customer_signature_${taskId}_$ts.png';

      final res = await http.post(
        Uri.parse('$baseUrl/fsm/task/signature/save'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'id': 1,
          'params': {
            'task_id':      taskId,
            'signature_b64': b64,
            'filename':     filename,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] is Map) {
          final result = Map<String, dynamic>.from(decoded['result'] as Map);
          if (result['success'] == true) {
            print('[uploadSignature] OK task=$taskId attachment_id=${result['attachment_id']}');
            return (success: true, attachmentId: result['attachment_id'] as int?, error: null);
          }
          final err = result['error']?.toString() ?? 'Unknown error';
          print('[uploadSignature] server error: $err');
          return (success: false, attachmentId: null, error: err);
        }
      }
      print('[uploadSignature] unexpected response status=${res.statusCode}');
      return (success: false, attachmentId: null, error: 'Server error ${res.statusCode}');
    } catch (e) {
      print('[uploadSignature] exception: $e');
      return (success: false, attachmentId: null, error: e.toString());
    }
  }

  // ── Check if task already has a signature ────────────────────────────────
  Future<({bool hasSig, String? sigDate})> checkSignatureStatus(int taskId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/task/signature/status'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_id': taskId},
        }),
      ).timeout(const Duration(seconds: 10));

      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] is Map) {
          final result = Map<String, dynamic>.from(decoded['result'] as Map);
          if (result['success'] == true) {
            return (
              hasSig:  result['has_signature'] == true,
              sigDate: result['signature_date']?.toString(),
            );
          }
        }
      }
    } catch (e) {
      print('[checkSignatureStatus] error: $e');
    }
    return (hasSig: false, sigDate: null);
  }

  // ── Fetch signature PNG bytes for a task ─────────────────────────────────
  // Strategy 0 (primary): /fsm/task/signature/fetch  — uses sudo() on server,
  //   works even for portal users who cannot read project.task via ORM directly.
  // Strategy 1 (fallback): read x_customer_signature field via call_kw
  // Strategy 2 (fallback): ir.attachment search
  Future<Uint8List?> fetchSignatureBytes(int taskId) async {

    // ── Strategy 0: custom fetch endpoint (sudo — portal-user safe) ──────────
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/fsm/task/signature/fetch'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {'task_id': taskId},
        }),
      ).timeout(const Duration(seconds: 15));

      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] is Map) {
          final result = Map<String, dynamic>.from(decoded['result'] as Map);
          if (result['success'] == true && result['has_signature'] == true) {
            final b64 = result['signature_b64'];
            if (b64 is String && b64.isNotEmpty) {
              print('[fetchSignatureBytes] ✅ strategy-0: found via /fetch endpoint');
              return base64Decode(b64);
            }
          }
        }
      }
    } catch (e) {
      print('[fetchSignatureBytes] strategy-0 error: $e');
    }

    // ── Strategy 1: x_customer_signature field via call_kw ───────────────────
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {
            'model': 'project.task',
            'method': 'read',
            'args': [[taskId], ['x_customer_signature']],
            'kwargs': {},
          },
        }),
      ).timeout(const Duration(seconds: 15));

      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] is List) {
          final records = decoded['result'] as List;
          if (records.isNotEmpty) {
            final b64 = records[0]['x_customer_signature'];
            if (b64 is String && b64.isNotEmpty && b64 != 'false') {
              print('[fetchSignatureBytes] ✅ strategy-1: found in x_customer_signature');
              return base64Decode(b64);
            }
          }
        }
      }
    } catch (e) {
      print('[fetchSignatureBytes] strategy-1 error: $e');
    }

    // ── Strategy 2: ir.attachment linked to task ──────────────────────────────
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0', 'method': 'call', 'id': 1,
          'params': {
            'model': 'ir.attachment',
            'method': 'search_read',
            'args': [
              [
                ['res_model', '=', 'project.task'],
                ['res_id', '=', taskId],
                ['mimetype', 'like', 'image'],
              ],
            ],
            'kwargs': {
              'fields': ['id', 'name', 'datas', 'mimetype', 'create_date'],
              'order': 'create_date desc',
              'limit': 5,
            },
          },
        }),
      ).timeout(const Duration(seconds: 15));

      final raw = res.body.trim();
      if (!raw.toLowerCase().startsWith('<!')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['error'] == null && decoded['result'] is List) {
          final attachments = decoded['result'] as List;
          final sigAttach = attachments.firstWhere(
            (a) => (a['name'] as String? ?? '').toLowerCase().contains('signature'),
            orElse: () => attachments.isNotEmpty ? attachments.first : null,
          );
          if (sigAttach != null) {
            final b64 = sigAttach['datas'];
            if (b64 is String && b64.isNotEmpty && b64 != 'false') {
              print('[fetchSignatureBytes] ✅ strategy-2: found in ir.attachment: ${sigAttach['name']}');
              return base64Decode(b64);
            }
          }
        }
      }
    } catch (e) {
      print('[fetchSignatureBytes] strategy-2 error: $e');
    }

    print('[fetchSignatureBytes] ❌ no signature found for task=$taskId');
    return null;
  }

}

class OdooException implements Exception {
  final String message;
  OdooException(this.message);
  @override String toString() => message;
}