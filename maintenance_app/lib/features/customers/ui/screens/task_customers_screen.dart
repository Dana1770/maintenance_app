import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';
import './customer_detail_screen.dart';
import './periodic_customers_screen.dart';
import './emergency_customers_screen.dart';
import './satisfaction_screen.dart';
// import 'spare_parts_tasks_screen.dart'; // SPARE PARTS — commented out
import '../../../maintenance/ui/screens/maintenance_screen.dart';

class TaskCustomersScreen extends StatefulWidget {
  final String title;
  // "periodic" | "emergency" | "survey" | "spare_parts"
  final String filterType;
  final List<Map<String, dynamic>> tasks;

  const TaskCustomersScreen({
    super.key,
    required this.title,
    required this.filterType,
    required this.tasks,
  });

  @override
  State<TaskCustomersScreen> createState() => _TaskCustomersScreenState();
}

class _TaskCustomersScreenState extends State<TaskCustomersScreen> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final odoo = context.read<OdooCubit>();
      if (odoo.tasksState == LoadState.idle) await odoo.fetchMyTasks();
      if (odoo.customersState == LoadState.idle ||
          (odoo.customersState == LoadState.loaded &&
              odoo.customers.isEmpty)) {
        await odoo.fetchCustomers();
      }
    });

  }



  // ── Unique customers derived from the filtered task list ─────────────────
  List<Map<String, dynamic>> _buildCustomers(OdooCubit odoo) {
    final tasks = widget.tasks.toList();
    final Map<int, Map<String, dynamic>> seen = {};

    for (final task in tasks) {
      final partner = task['partner_id'];
      if (partner == null || partner == false) continue;
      final id   = (partner as List)[0] as int;
      final name = partner[1].toString();
      if (!seen.containsKey(id)) {
        final full = odoo.customers.where((c) => c['id'] == id).toList();
        seen[id] = full.isNotEmpty
            ? full.first
            : {'id': id, 'name': name, 'city': '', 'street': '', 'phone': ''};
      }
    }

    var list = seen.values.toList();

    // Search: customer name / address OR task name for this customer
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) {
        final nameMatch = c['name'].toString().toLowerCase().contains(q);
        final cityMatch = (c['city'] ?? '').toString().toLowerCase().contains(q);
        final streetMatch = (c['street'] ?? '').toString().toLowerCase().contains(q);
        // task name match for this customer
        final taskMatch = _tasksForPartner(c['id'] as int).any(
                (t) => (t['name'] ?? '').toString().toLowerCase().contains(q));
        return nameMatch || cityMatch || streetMatch || taskMatch;
      }).toList();
    }

    return list;
  }

  // ── Tasks for a specific partner ─────────────────────────────────────────
  List<Map<String, dynamic>> _tasksForPartner(int partnerId) =>
      widget.tasks.where((t) {
        final p = t['partner_id'];
        if (p == null || p == false) return false;
        return (p as List)[0] == partnerId;
      }).toList();

  // ── Colours ──────────────────────────────────────────────────────────────
  Color _badgeColor() {
    switch (widget.filterType) {
      case 'emergency':   return const Color(0xFFFF5722);
    // case 'spare_parts': return const Color(0xFF3F51B5); // SPARE PARTS — commented out
    // case 'survey':      return AppTheme.success;               // SURVEY — commented out
      default:            return AppTheme.primary;
    }
  }

  String _badgeLabel() {
    switch (widget.filterType) {
      case 'emergency':   return 'EMERGENCY';
    // case 'spare_parts': return 'SPARE PARTS'; // SPARE PARTS — commented out
    // case 'survey':      return 'SURVEY';      // SURVEY — commented out
      default:            return 'PERIODIC';
    }
  }



  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final odoo      = context.watch<OdooCubit>();
    final customers = _buildCustomers(odoo);
    final isLoading = odoo.tasksState     == LoadState.loading ||
        odoo.customersState == LoadState.loading;

    final badgeColor = _badgeColor();
    final badgeLabel = _badgeLabel();


    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title,
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppTheme.textDark)),
        centerTitle: true,
      ),
      body: Column(
        children: [

          // ── Search bar + filter selector (same row) ─────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                // Search field
                Expanded(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: Row(children: [
                      const SizedBox(width: 14),
                      Icon(Icons.search, color: AppTheme.textGrey, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v.toLowerCase()),
                          style: GoogleFonts.inter(
                              fontSize: 14, color: AppTheme.textDark),
                          decoration: InputDecoration(
                            hintText: 'Search clients…',
                            hintStyle: GoogleFonts.inter(
                                fontSize: 13, color: AppTheme.textGrey),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_search.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.close,
                              size: 16, color: AppTheme.textGrey),
                          onPressed: () => setState(() => _search = ''),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                        ),
                    ]),
                  ),
                ),

                const SizedBox(width: 10),

                // Filter selection button (popup menu)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'periodic':
                        _navigateTo(context, const PeriodicCustomersScreen());
                        break;
                      case 'emergency':
                        _navigateTo(context, const EmergencyCustomersScreen());
                        break;
                    // case 'survey': // SURVEY — commented out
                    //   _navigateTo(context, const SatisfactionScreen());
                    //   break;
                    // case 'spare_parts': // SPARE PARTS — commented out
                    //   _navigateTo(context, const SparePartsTasksScreen());
                    //   break;
                    }
                  },
                  offset: const Offset(0, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  itemBuilder: (_) => [
                    _filterMenuItem('periodic',    'Periodic',    AppTheme.primary,             Icons.autorenew),
                    _filterMenuItem('emergency',   'Emergency',   const Color(0xFFFF5722),       Icons.warning_amber_rounded),
                    // _filterMenuItem('survey',      'Survey',      AppTheme.success,        Icons.rate_review_outlined),    // SURVEY — commented out
                    // _filterMenuItem('spare_parts', 'Spare Parts', const Color(0xFF3F51B5), Icons.build_outlined), // SPARE PARTS — commented out
                  ],
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          badgeLabel,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Customer count ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Text(
                '${customers.length} customer${customers.length == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textGrey),
              ),
            ]),
          ),

          // ── Customer list ───────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: () async {
                await odoo.fetchMyTasks();
                await odoo.fetchCustomers();
              },
              child: isLoading
                ? const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.primary))
                : customers.isEmpty
                ? _emptyState(odoo)
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: customers.length,
              separatorBuilder: (_, __) =>
              const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final c      = customers[i];
                final cTasks = _tasksForPartner(c['id'] as int);
                final city   = (c['city'] == null || c['city'] == false) ? '' : c['city'].toString();
                final street = (c['street'] == null || c['street'] == false) ? '' : c['street'].toString();
                final addr   = [street, city]
                    .where((s) => s.isNotEmpty)
                    .join(', ');

                // Highlight matching task names in card
                final matchingTasks = _search.isNotEmpty
                    ? cTasks
                    .where((t) => (t['name'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_search))
                    .map((t) => (t['name'] ?? '').toString())
                    .take(2)
                    .toList()
                    : <String>[];

                return _CustomerTile(
                  customer      : c,
                  address       : addr,
                  tasks         : cTasks,
                  badgeLabel    : badgeLabel,
                  badgeColor    : badgeColor,
                  filterType    : widget.filterType,
                  matchingTasks : matchingTasks,
                  searchQuery   : _search,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CustomerDetailScreen(
                        customer  : c,
                        tasks     : cTasks,
                        filterType: widget.filterType,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ) ],
      ),
    );
  }

  Widget _emptyState(OdooCubit odoo) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline,
              size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _search.isNotEmpty
                ? 'No customers match your filter.'
                : odoo.tasksError != null
                ? 'Error: ${odoo.tasksError}'
                : widget.tasks.isEmpty
                ? 'No tasks assigned to you yet.'
                : 'No customers found.',
            style: GoogleFonts.inter(
                color: AppTheme.textGrey, fontSize: 14, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              odoo.fetchMyTasks();
              odoo.fetchCustomers();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            icon: const Icon(Icons.refresh,
                color: Colors.white, size: 16),
            label: Text('Refresh',
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );

  void _navigateTo(BuildContext ctx, Widget screen) =>
      Navigator.pushReplacement(
          ctx, MaterialPageRoute(builder: (_) => screen));

  PopupMenuItem<String> _filterMenuItem(
      String value, String label, Color color, IconData icon) {
    final isActive = widget.filterType == value;
    return PopupMenuItem<String>(
      value: value,
      enabled: !isActive,
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(isActive ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? color : AppTheme.textDark)),
        if (isActive) ...[
          const Spacer(),
          Icon(Icons.check_circle, size: 16, color: color),
        ],
      ]),
    );
  }
}

// ── Customer tile ─────────────────────────────────────────────────────────
class _CustomerTile extends StatelessWidget {
  final Map<String, dynamic>       customer;
  final String                     address;
  final List<Map<String, dynamic>> tasks;
  final String                     badgeLabel;
  final Color                      badgeColor;
  final String                     filterType;
  final List<String>               matchingTasks;
  final String                     searchQuery;
  final VoidCallback               onTap;

  const _CustomerTile({
    required this.customer,
    required this.address,
    required this.tasks,
    required this.badgeLabel,
    required this.badgeColor,
    required this.filterType,
    required this.matchingTasks,
    required this.searchQuery,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name     = customer['name']?.toString() ?? 'Unknown';
    final initials = name.isNotEmpty
        ? name.split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(children: [
                // Avatar
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.12),
                      shape: BoxShape.circle),
                  child: Center(
                    child: Text(initials,
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: badgeColor)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(name,
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textDark),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(badgeLabel,
                              style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ]),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(Icons.location_on_outlined,
                              size: 12, color: AppTheme.textGrey),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(address,
                                style: GoogleFonts.inter(
                                    fontSize: 11, color: AppTheme.textGrey),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ],
                      // Matching task name pills
                      if (matchingTasks.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: matchingTasks.map((taskName) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.task_alt,
                                      size: 10,
                                      color: AppTheme.primary
                                          .withOpacity(0.7)),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(taskName,
                                        style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primary),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.grey.shade400, size: 20),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(children: [
                Icon(Icons.assignment_outlined,
                    size: 12, color: AppTheme.textGrey),
                const SizedBox(width: 4),
                Text(
                  tasks.isEmpty
                      ? 'No tasks'
                      : '${tasks.length} task${tasks.length == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppTheme.textGrey),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}