import 'dart:convert';
import 'dart:io';
import 'dart:math' show asin, cos, pi, sin, sqrt;
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/di/timer_service.dart';
import '../../../maintenance/ui/screens/maintenance_screen.dart';
import '../../../maintenance/ui/screens/all_tasks_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  final List<Map<String, dynamic>> tasks;
  final String filterType;

  const CustomerDetailScreen({
    super.key,
    required this.customer,
    required this.tasks,
    this.filterType = 'periodic',
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  List<Map<String, dynamic>> _allTasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final odoo = context.read<OdooCubit>();
    final cId  = widget.customer['id'] as int;

    final fromMemory = odoo.myTasks.where((t) {
      final p = t['partner_id'];
      if (p is List && p.isNotEmpty) return p[0] == cId;
      return false;
    }).toList();

    if (fromMemory.isNotEmpty) {
      if (mounted) {
        setState(() {
          _allTasks = fromMemory.where((t) => _matchesFilterType(t)).toList();
          _loading  = false;
        });
      }
      return;
    }

    final fromWidget = widget.tasks.where((t) => _matchesFilterType(t)).toList();
    if (fromWidget.isNotEmpty) {
      if (mounted) {
        setState(() {
          _allTasks = fromWidget;
          _loading  = false;
        });
      }
      return;
    }

    final service = odoo.service;
    if (service == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final fetched = await service.fetchTasksForPartner(
          cId, userId: odoo.loggedUid);
      if (mounted) {
        setState(() {
          _allTasks = fetched.where((t) => _matchesFilterType(t)).toList();
          _loading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesFilterType(Map<String, dynamic> task) {
    final tf = task['fs_task_type_id'];
    final typeName = (tf is List && tf.length > 1)
        ? tf[1].toString().toLowerCase()
        : '';
    switch (widget.filterType) {
      case 'emergency':
        return typeName.contains('urgent') || typeName.contains('emergency');
      case 'survey':
        return typeName.contains('survey');
      case 'spare_parts':
        return typeName.contains('spare');
      case 'periodic':
      default:
        return typeName.contains('periodic') ||
            (!typeName.contains('urgent') &&
             !typeName.contains('emergency') &&
             !typeName.contains('survey') &&
             !typeName.contains('spare'));
    }
  }

  String get _taskTypeName {
    for (final t in widget.tasks) {
      final tf = t['fs_task_type_id'];
      if (tf is List && tf.length > 1) {
        final name = tf[1].toString();
        return name.isNotEmpty
            ? name[0].toUpperCase() + name.substring(1)
            : name;
      }
    }
    switch (widget.filterType) {
      case 'emergency':   return 'Emergency';
      case 'survey':      return 'Survey';
      case 'spare_parts': return 'Spare Parts';
      default:            return 'Periodic Maintenance';
    }
  }

  Map<String, dynamic>? get _startTask {
    if (_allTasks.isEmpty) return null;

    final sorted = List.of(_allTasks)
      ..sort((a, b) => ((b['id'] as int?) ?? 0).compareTo((a['id'] as int?) ?? 0));

    final open = sorted.where((t) {
      final stage = t['stage_id'];
      final name  = (stage is List ? stage[1] : stage).toString().toLowerCase();
      return !name.contains('done') && !name.contains('cancel');
    }).toList();
    return open.isNotEmpty ? open.first : sorted.first;
  }

  String _stageLabel(Map<String, dynamic> task) {
    final stage = task['stage_id'];
    if (stage == null || stage == false) return 'New';
    return (stage is List ? stage[1] : stage).toString();
  }

  Color _stageColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('done') || l.contains('complet')) return Colors.green;
    if (l.contains('cancel'))                         return Colors.red;
    if (l.contains('progress') || l.contains('in ')) return Colors.orange;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> c = widget.customer;
    try {
      final odoo = context.read<OdooCubit>();
      final fulls = odoo.customers.where((x) => x['id'] == c['id']).toList();
      if (fulls.isNotEmpty) c = fulls.first;
    } catch (_) {}

    final name    = c['name']?.toString() ?? 'Customer';
    final phone   = (c['phone']?.toString() ?? '').isNotEmpty
        ? c['phone']!.toString()
        : c['mobile']?.toString() ?? '';
    final address = [c['street'] ?? '', c['city'] ?? '']
        .where((s) => s.toString().isNotEmpty).join(', ');
    final googleMapLink = (c['google_map_link']?.toString() ?? '').trim();
    final googleMapLinkManual = _odooStr(c['google_map_link_manual']);
    final mapUrl = googleMapLink.isNotEmpty
        ? googleMapLink
        : googleMapLinkManual.isNotEmpty
            ? googleMapLinkManual
            : address.isNotEmpty
                ? 'https://maps.google.com/?q=${Uri.encodeComponent(address)}'
                : '';
    final start   = _startTask;
    final hasLogo = c['image_128'] != null && c['image_128'] != false;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Views Details',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(children: [

          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(children: [

              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade200, width: 2)),
                clipBehavior: Clip.antiAlias,
                child: hasLogo
                    ? _buildLogo(c['image_128'].toString())
                    : Center(
                        child: Text(
                          name.split(' ').take(2)
                              .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
                              .join(),
                          style: GoogleFonts.inter(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary),
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              Text(name,
                  style: GoogleFonts.inter(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: AppTheme.textDark),
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(_taskTypeName,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppTheme.textGrey)),
              const SizedBox(height: 20),

              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _actionBtn(Icons.phone_outlined, 'Call',
                    () => _launch('tel:${phone.replaceAll(' ', '')}')),
                _vDivider(),
                _actionBtnImage('', 'WhatsApp',
                    () => _sendWhatsApp(start)),
                _vDivider(),
                _actionBtn(Icons.location_on_outlined, 'Location',
                    () => _checkAndShowLocation(mapUrl)),
              ]),
            ]),
          ),

          const SizedBox(height: 14),

          if (start != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListenableBuilder(
                listenable: TimerService.instance,
                builder: (context, _) {
                  final ts = TimerService.instance;
                  final tid = (start['id'] as int?) ?? 0;
                  final isRunning = ts.isStarted(tid) && !ts.isPaused(tid);
                  final isPaused  = ts.isPaused(tid);
                  final timeLabel = ts.isStarted(tid) ? ts.display(tid) : null;

                  return GestureDetector(
                    onTap: () => _startVisit(start),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              if (timeLabel != null) ...[
                                Row(children: [
                                  Container(width: 6, height: 6,
                                      decoration: BoxDecoration(
                                          color: isRunning ? Colors.greenAccent : Colors.orangeAccent,
                                          shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Text(
                                    isRunning ? 'In Progress · $timeLabel'
                                        : isPaused ? 'Paused · $timeLabel'
                                        : timeLabel,
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5),
                                  ),
                                ]),
                                const SizedBox(height: 3),
                              ] else ...[
                                Text('Start Visit number: #${start['id']}',
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white)),
                                const SizedBox(height: 3),
                              ],
                              Text(start['name']?.toString() ?? '',
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.85)),
                                  overflow: TextOverflow.ellipsis),
                            ],
                          )),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              ts.isStarted(tid)
                                  ? (isPaused ? 'Resume' : 'Continue')
                                  : 'Start Visit',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 22),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${_taskTypeName} History',
                  style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark)),
              if (_allTasks.length > 3)
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AllTasksScreen(
                            customer: widget.customer,
                            tasks   : _allTasks,
                            title   : '${_taskTypeName} History',
                          ))),
                  child: Text('View all',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
            ]),
          ),

          const SizedBox(height: 12),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            )
          else if (_allTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text('No tasks found for this customer.',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppTheme.textGrey)),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _allTasks.take(3).map((t) => _taskTile(t)).toList(),
              ),
            ),

          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _taskTile(Map<String, dynamic> task) {
    final stage = _stageLabel(task);
    final color = _stageColor(stage);
    final deadline = task['date_deadline']?.toString() ?? '';
    String dateDisplay = '';
    if (deadline.isNotEmpty && deadline != 'false' && deadline != 'null') {
      try {
        final d = DateTime.parse(deadline);
        dateDisplay = '${_month(d.month)} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
      } catch (_) { dateDisplay = ''; }
    }

    return GestureDetector(
      onTap: () => _startVisit(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade100)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(stage.toUpperCase(),
                    style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w800, color: color)),
              ),
              const SizedBox(width: 8),
              Text('#${task['id']}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textGrey)),
            ]),
            const SizedBox(height: 6),
            Text(task['name']?.toString() ?? 'Task',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
            if (dateDisplay.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(dateDisplay,
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textGrey)),
            ],
          ])),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
  }

  Widget _buildLogo(String b64) {
    try {
      return Image.memory(base64Decode(b64), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.business, size: 36, color: Colors.grey));
    } catch (_) {
      return const Icon(Icons.business, size: 36, color: Colors.grey);
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

  String _odooStr(dynamic v) {
    if (v == null || v == false) return '';
    final s = v.toString().trim();
    return s == 'false' ? '' : s;
  }

  ({
    String manualLink,
    String googleLink,
    double? custLat,
    double? custLng,
    bool hasAnyLocation,
  }) _resolveLocation(Map<String, dynamic> c, Map<String, dynamic> task) {
    String opt(String k) {
      if (_odooStr(c[k]).isNotEmpty) return _odooStr(c[k]);
      if (_odooStr(task[k]).isNotEmpty) return _odooStr(task[k]);
      return '';
    }

    final manualLink = opt('google_map_link_manual');
    final googleLink = opt('google_map_link');

    double? custLat;
    double? custLng;

    final rawLat = (c['partner_latitude'] != null && c['partner_latitude'] != false)
        ? c['partner_latitude']
        : task['partner_latitude'];
    final rawLng = (c['partner_longitude'] != null && c['partner_longitude'] != false)
        ? c['partner_longitude']
        : task['partner_longitude'];

    if (rawLat != null && rawLat != false) {
      final lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat.toString()) ?? 0.0;
      final lng = rawLng != null && rawLng != false
          ? ((rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng.toString()) ?? 0.0)
          : 0.0;
      if (lat.abs() > 0.0001 && lng.abs() > 0.0001) {
        custLat = lat;
        custLng = lng;
      }
    }

    if (custLat == null) {
      final coords = _latLngFromUrl(googleLink) ?? _latLngFromUrl(manualLink);
      if (coords != null) {
        custLat = coords.lat;
        custLng = coords.lng;
      }
    }

    final hasAnyLocation = manualLink.isNotEmpty || googleLink.isNotEmpty ||
        (custLat != null && custLng != null);

    return (
      manualLink: manualLink,
      googleLink: googleLink,
      custLat: custLat,
      custLng: custLng,
      hasAnyLocation: hasAnyLocation,
    );
  }

  Future<void> _startVisit(Map<String, dynamic> task) async {
    Map<String, dynamic> c = widget.customer;
    final OdooCubit odoo;
    try {
      odoo = context.read<OdooCubit>();
      final full = odoo.customers.where((x) => x['id'] == c['id']).toList();
      if (full.isNotEmpty) c = full.first;
    } catch (_) {
      return;
    }

    final partner = task['partner_id'];
    final loc     = task['fsm_location_id'];
    final cName   = partner is List ? partner[1].toString() : (c['name']?.toString() ?? 'Customer');
    final locName = loc is List ? loc[1].toString() : '';

    var resolved = _resolveLocation(c, task);

    int restrictionM = 0;
    bool serverSaysHasLocation = false;

    if (odoo.service != null) {
      try {
        final taskId = task['id'] as int?;
        if (taskId != null) {
          final taskLocData = await odoo.service!.fetchTaskLocation(taskId);
          if (taskLocData != null) {
            final merged = Map<String, dynamic>.from(c);

            void mergeIfPresent(String key) {
              final v = taskLocData[key];
              if (v != null && v != false && v.toString().trim().isNotEmpty && v.toString() != 'false') {
                merged[key] = v;
              }
            }

            mergeIfPresent('google_map_link_manual');
            mergeIfPresent('google_map_link');
            mergeIfPresent('partner_latitude');
            mergeIfPresent('partner_longitude');

            c = merged;
            resolved = _resolveLocation(c, task);


            serverSaysHasLocation = taskLocData['has_location'] == true;

            final rm = taskLocData['restriction_m'];
            if (rm != null && rm != false) {
              restrictionM = (rm as num).toInt();
            }

            debugPrint('[StartVisit] fetchTaskLocation: serverHasLoc=$serverSaysHasLocation '
                'hasAnyLocation=${resolved.hasAnyLocation} custLat=${resolved.custLat} '
                'manualLink=${resolved.manualLink} restrictionM=$restrictionM');
          }
        }
      } catch (e) {
        debugPrint('[StartVisit] fetchTaskLocation error: $e');
      }
    }


    if (!mounted) return;
    await _showLocationDistanceSheet(
      customerName: cName,
      custLat: resolved.custLat,
      custLng: resolved.custLng,
      manualLink: resolved.manualLink,
      googleLink: resolved.googleLink,
      hasAnyLocation: resolved.hasAnyLocation,
      restrictionM: restrictionM,
      onStartVisit: () => _navigateToMaintenance(task, cName, locName),
    );
  }


  Future<void> _showLocationDistanceSheet({
    required String customerName,
    required double? custLat,
    required double? custLng,
    required String manualLink,
    required String googleLink,
    required VoidCallback onStartVisit,
    bool hasAnyLocation = true,
    int restrictionM = 0,
  }) async {
    if (!mounted) return;

    bool spinnerOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
    void closeSpinner() {
      if (spinnerOpen && mounted) {
        spinnerOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    double? distMetres;
    bool locationPermissionDenied = false;

    if (custLat != null && custLng != null) {
      try {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
          locationPermissionDenied = true;
        } else {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15),
          );
          distMetres = _distanceMetres(pos.latitude, pos.longitude, custLat, custLng);
        }
      } catch (_) {}
    }

    closeSpinner();
    if (!mounted) return;

    final String? mapsNavUrl;
    if (custLat != null && custLng != null) {
      mapsNavUrl = 'https://www.google.com/maps/dir/?api=1&destination=$custLat,$custLng';
    } else if (manualLink.isNotEmpty) {
      mapsNavUrl = manualLink;
    } else if (googleLink.isNotEmpty) {
      mapsNavUrl = googleLink;
    } else {
      mapsNavUrl = null;
    }

    String distanceLabel;
    Color distanceColor;
    IconData distanceIcon;


    final double _kThreshold = restrictionM > 0 ? restrictionM.toDouble() : 500.0;

    final bool canStart;
    String?    blockReason;

    if (!hasAnyLocation) {
      canStart    = false;
      blockReason = 'No location is set for this customer.\nPlease ask the admin to add a GPS location or map link before starting.';
    } else if (custLat == null || custLng == null) {
      canStart    = false;
      blockReason = 'Customer location must include valid latitude/longitude so distance can be validated before starting.';
    } else if (distMetres != null) {
      canStart = distMetres <= _kThreshold;
      if (!canStart) {
        final isKm = distMetres >= 1000;
        final str  = isKm
            ? '${(distMetres / 1000).toStringAsFixed(1)} km'
            : '${distMetres.toStringAsFixed(0)} m';
        final limitStr = _kThreshold >= 1000
            ? '${(_kThreshold / 1000).toStringAsFixed(1)} km'
            : '${_kThreshold.toStringAsFixed(0)} m';
        blockReason = 'You are $str away from the customer.\nYou must be within $limitStr to start.';
      }
    } else if (locationPermissionDenied) {
      canStart    = false;
      blockReason = 'Location permission is required to validate your distance from the customer before starting.';
    } else {
      canStart    = false;
      blockReason = 'Unable to read your current location. Please enable GPS and try again.';
    }

    if (!hasAnyLocation) {
      distanceLabel = 'No location set';
      distanceColor = Colors.red;
      distanceIcon  = Icons.location_off_outlined;
    } else if (locationPermissionDenied) {
      distanceLabel = 'Location permission denied';
      distanceColor = Colors.orange;
      distanceIcon  = Icons.location_disabled_outlined;
    } else if (distMetres == null && custLat == null) {
      distanceLabel = 'Map link set – tap Navigate';
      distanceColor = Colors.orange;
      distanceIcon  = Icons.near_me_outlined;
    } else if (distMetres == null) {
      distanceLabel = 'Could not get your location';
      distanceColor = Colors.orange;
      distanceIcon  = Icons.gps_off_outlined;
    } else if (distMetres != null && distMetres < 1000) {
      distanceLabel = '${distMetres.toStringAsFixed(0)} m away';
      distanceColor = distMetres <= _kThreshold ? Colors.green : Colors.red;
      distanceIcon  = distMetres <= _kThreshold ? Icons.near_me : Icons.directions_car_outlined;
    } else {
      distanceLabel = '${((distMetres ?? 0) / 1000).toStringAsFixed(1)} km away';
      distanceColor = Colors.red;
      distanceIcon  = Icons.directions_car_outlined;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),

            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.location_on, color: AppTheme.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(customerName,
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('Customer Location',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textGrey)),
              ])),
            ]),

            const SizedBox(height: 20),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              decoration: BoxDecoration(
                  color: distanceColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: distanceColor.withOpacity(0.25))),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: distanceColor.withOpacity(0.15),
                      shape: BoxShape.circle),
                  child: Icon(distanceIcon, color: distanceColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Distance to Customer',
                      style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: AppTheme.textGrey, letterSpacing: 0.3)),
                  const SizedBox(height: 3),
                  Text(distanceLabel,
                      style: GoogleFonts.inter(
                          fontSize: 18, fontWeight: FontWeight.w900,
                          color: distanceColor)),
                ])),
              ]),
            ),

            if (!canStart && blockReason != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.block_outlined, color: Colors.red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(blockReason!,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.red.shade700, height: 1.45)),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 16),

            if (mapsNavUrl != null)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await launchUrl(Uri.parse(mapsNavUrl!),
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                  style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.primary.withOpacity(0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  icon: const Icon(Icons.navigation_outlined,
                      color: AppTheme.primary, size: 18),
                  label: Text('Open in Maps',
                      style: GoogleFonts.inter(
                          color: AppTheme.primary, fontWeight: FontWeight.w700)),
                ),
              ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: canStart
                    ? () {
                        Navigator.pop(ctx);
                        onStartVisit();
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: canStart ? AppTheme.primary : Colors.grey.shade300,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                icon: Icon(
                    canStart ? Icons.play_circle_outline : Icons.lock_outline,
                    color: canStart ? Colors.white : Colors.grey.shade500,
                    size: 20),
                label: Text(
                    canStart ? 'Start Visit' : 'Cannot Start — Not at Location',
                    style: GoogleFonts.inter(
                        color: canStart ? Colors.white : Colors.grey.shade600,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToMaintenance(
      Map<String, dynamic> task, String cName, String locName) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MaintenanceScreen(
        task         : task,
        customerName : cName,
        location     : locName,
        serialNumber : 'L1 - ${task['id'] ?? 0}',
        maintenanceId: task['name']?.toString() ?? '#${task['id']}',
      ),
    ));
  }

  void _showNoLocationDialog() {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Icon(Icons.location_off, color: Colors.red, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.t('no_location_title'),
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: AppTheme.textDark)),
          ),
        ]),
        content: Text(
          l.t('no_location_body'),
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('location_ok'),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAndShowLocation(String _ignored) async {
    Map<String, dynamic> c = widget.customer;
    OdooCubit? odoo;
    try {
      odoo = context.read<OdooCubit>();
      final fulls = odoo.customers.where((x) => x['id'] == c['id']).toList();
      if (fulls.isNotEmpty) c = fulls.first;
    } catch (_) {}

    final fallbackTask = widget.tasks.isNotEmpty ? widget.tasks.first : const <String, dynamic>{};
    var resolved = _resolveLocation(c, fallbackTask);

    if (!resolved.hasAnyLocation && odoo?.service != null) {
      try {
        final taskId = (widget.tasks.isNotEmpty ? widget.tasks.first['id'] : null) as int?;
        if (taskId != null) {
          final taskLocData = await odoo!.service!.fetchTaskLocation(taskId);
          if (taskLocData != null) {
            final merged = Map<String, dynamic>.from(c);
            void _m(String k) {
              final v = taskLocData[k];
              if (v != null && v != false && v.toString().trim().isNotEmpty && v.toString() != 'false') merged[k] = v;
            }
            _m('google_map_link_manual'); _m('google_map_link');
            _m('partner_latitude'); _m('partner_longitude');
            c = merged;
            resolved = _resolveLocation(c, fallbackTask);
            // Force hasAnyLocation if server says so
            if (taskLocData['has_location'] == true && !resolved.hasAnyLocation) {
              resolved = (manualLink: resolved.manualLink, googleLink: resolved.googleLink,
                          custLat: resolved.custLat, custLng: resolved.custLng, hasAnyLocation: true);
            }
          }
        }
      } catch (_) {}
    }

    // ORM fallback
    if (!resolved.hasAnyLocation && odoo?.service != null) {
      try {
        final pid = c['id'] as int?;
        if (pid != null) {
          final fresh = await odoo!.service!.fetchPartnersByIds([pid]);
          if (fresh.isNotEmpty) {
            c        = fresh.first;
            resolved = _resolveLocation(c, fallbackTask);
          }
        }
      } catch (_) {}
    }

    // If still no location, the endpoint is not deployed — open Google Maps
    // search for the customer name rather than blocking with an error dialog.
    final navUrl = (resolved.custLat != null && resolved.custLng != null)
        ? 'https://www.google.com/maps/dir/?api=1&destination=${resolved.custLat},${resolved.custLng}'
        : (resolved.manualLink.isNotEmpty ? resolved.manualLink
           : (resolved.googleLink.isNotEmpty ? resolved.googleLink : ''));

    if (navUrl.isNotEmpty) {
      try {
        await launchUrl(Uri.parse(navUrl), mode: LaunchMode.externalApplication);
      } catch (_) {}
    } else {
      _showNoLocationDialog();
    }
  }

  Future<void> _launch(String url) async {
    try { await launchUrl(Uri.parse(url)); } catch (_) {}
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle),
            child: Icon(icon, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
        ]),
      );

  Widget _vDivider() =>
      Container(height: 44, width: 1, color: Colors.grey.shade200);

  // WhatsApp button — yellow circle with real WhatsApp SVG icon
  Widget _actionBtnImage(String assetPath, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                shape: BoxShape.circle),
            child: Center(
              child: SizedBox(
                width: 26, height: 26,
                child: CustomPaint(painter: _WhatsAppIconPainter(color: AppTheme.primary)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
        ]),
      );

  // Send WhatsApp: if signature exists → share image directly to WhatsApp
  Future<void> _sendWhatsApp(Map<String, dynamic>? task) async {
    if (task == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No task found to send signature.',
            style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    // Show loading while fetching signature
    bool spinnerOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
    void closeSpinner() {
      if (spinnerOpen && mounted) {
        spinnerOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    // Fetch signature bytes from server
    // Try the current/active task first, then fall back to checking all history tasks
    Uint8List? sigBytes;
    final taskId = (task['id'] as int?) ?? 0;
    try {
      final odoo = context.read<OdooCubit>();
      sigBytes = await odoo.service?.fetchSignatureBytes(taskId);

      // If not found on the active task, search all tasks for this partner
      if ((sigBytes == null || sigBytes.isEmpty) && _allTasks.isNotEmpty) {
        final sorted = List.of(_allTasks)
          ..sort((a, b) => ((b['id'] as int?) ?? 0).compareTo((a['id'] as int?) ?? 0));
        for (final t in sorted) {
          final tid = (t['id'] as int?) ?? 0;
          if (tid == taskId) continue; // already tried
          sigBytes = await odoo.service?.fetchSignatureBytes(tid);
          if (sigBytes != null && sigBytes.isNotEmpty) {
            print('[sendWhatsApp] ✅ signature found on task #$tid (fallback)');
            break;
          }
        }
      }
    } catch (_) {}

    closeSpinner();
    if (!mounted) return;

    // No signature found
    if (sigBytes == null || sigBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No signature available for task #$taskId.',
            style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    // Save to temp file and share directly to WhatsApp
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/signature_task_$taskId.png');
      await file.writeAsBytes(sigBytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Customer signature — Task #$taskId',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to share signature.',
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }
  String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ── WhatsApp logo painter (real icon shape, drawn with canvas) ─────────────
class _WhatsAppIconPainter extends CustomPainter {
  final Color color;
  _WhatsAppIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    // Outer circle
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, paint);

    // White phone handset inside
    final white = Paint()..color = Colors.white..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Simple phone handset shape
    path.moveTo(s * 0.30, s * 0.25);
    path.quadraticBezierTo(s * 0.25, s * 0.25, s * 0.25, s * 0.35);
    path.lineTo(s * 0.25, s * 0.42);
    path.quadraticBezierTo(s * 0.25, s * 0.52, s * 0.32, s * 0.60);
    path.quadraticBezierTo(s * 0.42, s * 0.72, s * 0.58, s * 0.75);
    path.lineTo(s * 0.65, s * 0.75);
    path.quadraticBezierTo(s * 0.75, s * 0.75, s * 0.75, s * 0.65);
    path.lineTo(s * 0.75, s * 0.60);
    path.quadraticBezierTo(s * 0.75, s * 0.55, s * 0.68, s * 0.54);
    path.lineTo(s * 0.62, s * 0.52);
    path.quadraticBezierTo(s * 0.57, s * 0.51, s * 0.55, s * 0.55);
    path.lineTo(s * 0.53, s * 0.57);
    path.quadraticBezierTo(s * 0.47, s * 0.54, s * 0.43, s * 0.50);
    path.quadraticBezierTo(s * 0.39, s * 0.46, s * 0.37, s * 0.40);
    path.lineTo(s * 0.39, s * 0.38);
    path.quadraticBezierTo(s * 0.43, s * 0.36, s * 0.42, s * 0.31);
    path.lineTo(s * 0.40, s * 0.25);
    path.quadraticBezierTo(s * 0.39, s * 0.20, s * 0.34, s * 0.20);
    path.close();

    canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill);

    // Chat bubble tail (white triangle at bottom-left)
    final tail = Path()
      ..moveTo(s * 0.15, s * 0.90)
      ..lineTo(s * 0.20, s * 0.72)
      ..lineTo(s * 0.33, s * 0.78)
      ..close();
    canvas.drawPath(tail, Paint()..color = color..style = PaintingStyle.fill);
    // Cover the circle edge for clean tail
    canvas.drawPath(tail, Paint()..color = Colors.white..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_WhatsAppIconPainter old) => old.color != color;
}
