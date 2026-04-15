import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';

class MaintenanceRequestsScreen extends StatefulWidget {
  /// 0 = Periodic tab, 1 = Emergency tab
  final int initialTab;
  const MaintenanceRequestsScreen({super.key, this.initialTab = 0});
  @override
  State<MaintenanceRequestsScreen> createState() =>
      _MaintenanceRequestsScreenState();
}

class _MaintenanceRequestsScreenState
    extends State<MaintenanceRequestsScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tab;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 3, vsync: this, initialIndex: widget.initialTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final odoo = context.read<OdooCubit>();
      if (odoo.tasksState    == LoadState.idle) odoo.fetchMyTasks();
      if (odoo.requestsState == LoadState.idle) odoo.fetchRequests();
    });
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final odoo = context.watch<OdooCubit>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background, elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: Text('Maintenance',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppTheme.textDark)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primary),
            onPressed: () {
              odoo.fetchMyTasks();
              odoo.fetchRequests();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textGrey,
          indicatorColor: AppTheme.primary,
          labelStyle:
          GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
          GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
          tabs: [
            // Tab 0 — Periodic tasks
            Tab(text: 'Periodic (${odoo.periodicTasks.length})'),
            // Tab 1 — Emergency tasks
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Emergency (${odoo.emergencyTasks.length})',
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                if (odoo.emergencyTasks.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(
                        color: Color(0xFFFF5722), shape: BoxShape.circle),
                  ),
                ],
              ]),
            ),
            // Tab 2 — Maintenance Requests from Odoo
            Tab(text: 'Requests (${odoo.maintenanceRequests.length})'),
          ],
        ),
      ),
      body: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              const SizedBox(width: 12),
              Icon(Icons.search, color: AppTheme.textGrey, size: 18),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 13, color: AppTheme.textGrey),
                  border: InputBorder.none, isDense: true,
                ),
              )),
            ]),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _taskList(odoo, odoo.periodicTasks,   isEmergency: false),
              _taskList(odoo, odoo.emergencyTasks,  isEmergency: true),
              _requestList(odoo),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Tab 0 & 1 : project.task list ─────────────────────────────────────────
  Widget _taskList(
      OdooCubit odoo,
      List<Map<String, dynamic>> tasks, {
        required bool isEmergency,
      }) {
    if (odoo.tasksState == LoadState.loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (odoo.tasksState == LoadState.error) {
      return _errorView(odoo.tasksError ?? 'Error', odoo.fetchMyTasks);
    }

    final filtered = _search.isEmpty
        ? tasks
        : tasks.where((t) {
      final name = (t['name'] ?? '').toString().toLowerCase();
      final proj = t['project_id'] is List
          ? (t['project_id'] as List)[1].toString().toLowerCase()
          : '';
      return name.contains(_search) || proj.contains(_search);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isEmergency ? '🎉 No emergency tasks!' : 'No periodic tasks assigned',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textGrey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _taskCard(filtered[i], isEmergency),
    );
  }

  Widget _taskCard(Map<String, dynamic> t, bool isEmergency) {
    final stage   = t['stage_id'] is List
        ? (t['stage_id'] as List)[1].toString() : '—';
    final project = t['project_id'] is List
        ? (t['project_id'] as List)[1].toString() : '';
    final partner = t['partner_id'] is List
        ? (t['partner_id'] as List)[1].toString() : '';
    final deadline = t['date_deadline']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isEmergency
            ? Border.all(
            color: const Color(0xFFFF5722).withOpacity(0.35), width: 1.5)
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title + badge
        Row(children: [
          Expanded(
            child: Text(t['name']?.toString() ?? 'Untitled',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppTheme.textDark)),
          ),
          const SizedBox(width: 8),
          _priorityBadge(isEmergency),
        ]),
        const SizedBox(height: 8),
        if (project.isNotEmpty)
          _infoChip(Icons.folder_outlined, project),
        if (partner.isNotEmpty)
          _infoChip(Icons.person_outline, partner),
        if (deadline.isNotEmpty)
          _infoChip(Icons.calendar_today_outlined,
              'Due: ${deadline.split(' ').first}'),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _stageBadge(stage),
          Text('#${t['id']}',
              style: GoogleFonts.inter(
                  fontSize: 10, color: Colors.grey.shade400)),
        ]),
      ]),
    );
  }

  // ── Tab 2: maintenance.request list ──────────────────────────────────────
  Widget _requestList(OdooCubit odoo) {
    if (odoo.requestsState == LoadState.loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (odoo.requestsState == LoadState.error) {
      return _errorView(odoo.requestsError ?? 'Error', odoo.fetchRequests);
    }

    final requests = _search.isEmpty
        ? odoo.maintenanceRequests
        : odoo.maintenanceRequests.where((r) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      final equip = r['equipment_id'] is List
          ? (r['equipment_id'] as List)[1].toString().toLowerCase()
          : '';
      return name.contains(_search) || equip.contains(_search);
    }).toList();

    if (requests.isEmpty) {
      return Center(
        child: Text('No maintenance requests found',
            style: GoogleFonts.inter(
                fontSize: 14, color: AppTheme.textGrey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: requests.length,
      itemBuilder: (_, i) => _requestCard(requests[i]),
    );
  }

  Widget _requestCard(Map<String, dynamic> r) {
    final stage     = r['stage_id'] is List
        ? (r['stage_id'] as List)[1].toString() : '—';
    final equipment = r['equipment_id'] is List
        ? (r['equipment_id'] as List)[1].toString() : '';
    final assignee  = r['user_id'] is List
        ? (r['user_id'] as List)[1].toString() : '';
    final date      = r['request_date']?.toString() ?? '';
    final priority  = r['priority']?.toString() ?? '0';
    final isHigh    = priority == '1' || priority == '2' || priority == '3';
    final type      = (r['maintenance_type']?.toString() ?? '').replaceAll('_', ' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isHigh
            ? Border.all(
            color: const Color(0xFFFF5722).withOpacity(0.3), width: 1.5)
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(r['name']?.toString() ?? 'Untitled',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppTheme.textDark)),
          ),
          if (type.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(type.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
            ),
        ]),
        const SizedBox(height: 8),
        if (equipment.isNotEmpty)
          _infoChip(Icons.build_outlined, equipment),
        if (assignee.isNotEmpty)
          _infoChip(Icons.person_outline, assignee),
        if (date.isNotEmpty)
          _infoChip(Icons.calendar_today_outlined,
              date.split(' ').first),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _stageBadge(stage),
          Row(children: [
            // Priority stars
            ...List.generate(
              int.tryParse(priority) ?? 0,
                  (_) => const Icon(Icons.star,
                  size: 12, color: Color(0xFFFF5722)),
            ),
            const SizedBox(width: 6),
            Text('#${r['id']}',
                style: GoogleFonts.inter(
                    fontSize: 10, color: Colors.grey.shade400)),
          ]),
        ]),
      ]),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _priorityBadge(bool isEmergency) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: isEmergency
          ? const Color(0xFFFF5722)
          : AppTheme.primary.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(isEmergency ? '🚨 URGENT' : 'PERIODIC',
        style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: isEmergency ? Colors.white : AppTheme.primary)),
  );

  Widget _stageBadge(String stage) {
    final lower = stage.toLowerCase();
    Color bg = AppTheme.primary.withOpacity(0.1);
    Color fg = AppTheme.primary;
    if (lower.contains('done') || lower.contains('complet') ||
        lower.contains('closed')) {
      bg = Colors.green.withOpacity(0.1);
      fg = Colors.green.shade700;
    } else if (lower.contains('progress') || lower.contains('in-progress')) {
      bg = Colors.orange.withOpacity(0.1);
      fg = Colors.orange.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(stage,
          style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _infoChip(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Icon(icon, size: 12, color: AppTheme.textGrey),
      const SizedBox(width: 5),
      Expanded(
        child: Text(text,
            style: GoogleFonts.inter(
                fontSize: 12, color: AppTheme.textGrey),
            overflow: TextOverflow.ellipsis),
      ),
    ]),
  );

  Widget _errorView(String msg, VoidCallback retry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, color: AppTheme.error, size: 40),
        const SizedBox(height: 12),
        Text(msg,
            style: GoogleFonts.inter(
                color: AppTheme.error, fontSize: 13),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: retry,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary),
          child: Text('Retry',
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    ),
  );
}