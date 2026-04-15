import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';
import './maintenance_screen.dart';

class AllTasksScreen extends StatelessWidget {
  final Map<String, dynamic> customer;
  final List<Map<String, dynamic>> tasks;
  final String title;

  const AllTasksScreen({
    super.key,
    required this.customer,
    required this.tasks,
    this.title = 'All Tasks',
  });

  String _stageLabel(Map<String, dynamic> task) {
    final stage = task['stage_id'];
    if (stage == null || stage == false) return 'New';
    return (stage is List ? stage[1] : stage).toString();
  }

  Color _stageColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('done') || l.contains('complet')) return AppTheme.success;
    if (l.contains('cancel')) return Colors.red;
    if (l.contains('progress') || l.contains('in ')) return Colors.orange;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final cName = customer['name']?.toString() ?? '';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title,
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
        centerTitle: true,
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(cName,
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Text('${tasks.length} tasks',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textGrey)),
        ),
        Expanded(
          child: tasks.isEmpty
              ? Center(child: Text('No tasks found.',
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textGrey)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final task = tasks[i];
                    final stage = _stageLabel(task);
                    final color = _stageColor(stage);
                    final deadline = task['date_deadline']?.toString() ?? '';
                    String dateDisplay = '';
                    if (deadline.isNotEmpty) {
                      try {
                        final d = DateTime.parse(deadline);
                        dateDisplay = '${_month(d.month)} ${d.day}, ${d.year}';
                      } catch (_) { dateDisplay = deadline; }
                    }
                    final typeName = () {
                      final t = task['fs_task_type_id'];
                      if (t == null || t == false) return '';
                      return (t is List ? t[1] : t).toString();
                    }();

                    return GestureDetector(
                      onTap: () {
                        String _odooStr(dynamic v) {
                          if (v == null || v == false) return '';
                          final s = v.toString().trim();
                          return s == 'false' ? '' : s;
                        }
                        Map<String, dynamic>? partnerData;
                        try {
                          final odoo = context.read<OdooCubit>();
                          final partnerId = task['partner_id'];
                          int? pId;
                          if (partnerId is List && partnerId.isNotEmpty) pId = partnerId[0] as int;
                          else if (partnerId is int) pId = partnerId;
                          if (pId != null) {
                            final matches = odoo.customers.where((c) => c['id'] == pId).toList();
                            if (matches.isNotEmpty) partnerData = matches.first;
                          }
                        } catch (_) {}

                        // Check all location sources: partner cache → task data
                        final src = partnerData ?? task;
                        final manualLink = _odooStr(src['google_map_link_manual']);
                        final googleLink = _odooStr(src['google_map_link']);

                        // ═══ DEBUG: dump ALL location data ═══
                        debugPrint('════════════════════════════════════════════════════════');
                        debugPrint('[AllTasks.onTap] task_id=${task['id']}');
                        debugPrint('[AllTasks.onTap] partner_id=${task['partner_id']}');
                        debugPrint('[AllTasks.onTap] partnerData found? ${partnerData != null}');
                        if (partnerData != null) {
                          debugPrint('[AllTasks.onTap] partner keys: ${partnerData!.keys.toList()}');
                          debugPrint('[AllTasks.onTap] partner[google_map_link_manual] = "${partnerData!['google_map_link_manual']}"');
                          debugPrint('[AllTasks.onTap] partner[google_map_link]        = "${partnerData!['google_map_link']}"');
                          debugPrint('[AllTasks.onTap] partner[partner_latitude]       = "${partnerData!['partner_latitude']}"');
                          debugPrint('[AllTasks.onTap] partner[partner_longitude]      = "${partnerData!['partner_longitude']}"');
                        }
                        debugPrint('[AllTasks.onTap] task[google_map_link_manual] = "${task['google_map_link_manual']}"');
                        debugPrint('[AllTasks.onTap] task[partner_latitude]       = "${task['partner_latitude']}"');
                        debugPrint('[AllTasks.onTap] src used = ${partnerData != null ? "partner" : "task"}');
                        debugPrint('[AllTasks.onTap] manualLink = "$manualLink"');
                        debugPrint('[AllTasks.onTap] googleLink = "$googleLink"');

                        final hasLatLng = () {
                          final rawLat = src['partner_latitude'];
                          final rawLng = src['partner_longitude'];
                          if (rawLat == null || rawLat == false) return false;
                          if (rawLng == null || rawLng == false) return false;
                          final lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat.toString()) ?? 0.0;
                          final lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng.toString()) ?? 0.0;
                          return lat.abs() > 0.0001 && lng.abs() > 0.0001;
                        }();
                        debugPrint('[AllTasks.onTap] hasLatLng=$hasLatLng');
                        debugPrint('════════════════════════════════════════════════════════');

                        if (manualLink.isEmpty && googleLink.isEmpty && !hasLatLng) {
                          debugPrint('[AllTasks.onTap] ❌ BLOCKING → No location');
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              title: Row(children: [
                                const Icon(Icons.location_off, color: Colors.red, size: 22),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('No Customer Location',
                                      style: GoogleFonts.inter(
                                          fontSize: 16, fontWeight: FontWeight.w700,
                                          color: AppTheme.textDark)),
                                ),
                              ]),
                              content: Text(
                                'This customer does not have a location set.\n\nPlease add the Google Maps link in the customer profile before opening this task.',
                                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey, height: 1.5),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text('OK',
                                      style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primary)),
                                ),
                              ],
                            ),
                          );
                          return;
                        }
                        final partner = task['partner_id'];
                        final cNameTask = partner is List ? partner[1].toString() : cName;
                        final loc  = task['fsm_location_id'];
                        final locN = loc is List ? loc[1].toString() : '';
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => MaintenanceScreen(
                            task          : task,
                            customerName  : cNameTask,
                            location      : locN,
                            serialNumber  : 'L1 - ${task['id']}',
                            maintenanceId : task['name']?.toString() ?? '#${task['id']}',
                          ),
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: color.withOpacity(0.2))),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                                child: Text(stage.toUpperCase(),
                                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
                              ),
                              const SizedBox(width: 8),
                              Text('#${task['id']}',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textGrey)),
                              if (typeName.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Expanded(child: Text(typeName,
                                    style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primary),
                                    overflow: TextOverflow.ellipsis)),
                              ],
                            ]),
                            const SizedBox(height: 6),
                            Text(task['name']?.toString() ?? 'Task',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                            if (dateDisplay.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(dateDisplay, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textGrey)),
                            ],
                          ])),
                          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  String _month(int m) => const ['','Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'][m];
}
