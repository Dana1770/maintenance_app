import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';
import '../../../../core/shared_widgets/error_banner.dart';
import './customer_detail_screen.dart';
import '../../../../core/shared_widgets/odoo_loader.dart';
// import 'satisfaction_screen.dart'; // SURVEY — commented out

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {

  String _priority    = 'all';
  String _search = '';

  static const _chipLabel = {
    'all':    'All',
    'urgent': 'Emergency',
    'normal': 'Periodic',
    // 'survey': 'Survey', // SURVEY — commented out
  };

  static const _chips = [
    {'key': 'all',    'label': 'All',       'color': AppTheme.primary},
    {'key': 'normal', 'label': 'Periodic',  'color': AppTheme.primary},
    {'key': 'urgent', 'label': 'Emergency', 'color': Color(0xFFFF5722)},
    // {'key': 'survey', 'label': 'Survey',    'color': Color(0xFFFFC107)}, // SURVEY — commented out
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<OdooCubit>();
      if (p.customersState == LoadState.idle) p.fetchCustomers();
      if (p.tasksState     == LoadState.idle) p.fetchMyTasks();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _select(String priority) {
    // SURVEY — commented out
    // if (priority == 'survey') {
    //   setState(() => _priority = 'survey');
    //   Navigator.push(
    //     context,
    //     MaterialPageRoute(builder: (_) => const SatisfactionScreen()),
    //   ).then((_) {
    //     if (mounted) setState(() => _priority = 'all');
    //   });
    //   return;
    // }
    setState(() => _priority = priority);
  }

  @override
  Widget build(BuildContext context) {
    final odoo = context.watch<OdooCubit>();
    final list = _buildList(odoo);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Views',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primary),
            onPressed: () { odoo.fetchCustomers(); odoo.fetchMyTasks(); },
          ),
        ],
      ),
      body: Column(
        children: [
          if (odoo.customersState == LoadState.error)
            ErrorBanner(
              message: odoo.customersError ?? 'Error',
              onRetry: () => odoo.fetchCustomers(),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 14),
                    Icon(Icons.search, color: AppTheme.textGrey, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _search = v.toLowerCase()),
                        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textDark),
                        decoration: InputDecoration(
                          hintText: 'Search clients…',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_search.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.close, size: 16, color: AppTheme.textGrey),
                        onPressed: () => setState(() => _search = ''),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                  ]),
                ),

                const SizedBox(height: 12),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _chips.asMap().entries.map((entry) {
                      final chip  = entry.value;
                      final key   = chip['key']   as String;
                      final label = chip['label'] as String;
                      final color = chip['color'] as Color;
                      final sel   = _priority == key;
                      final count = _taskCountForKey(key, odoo);

                      return Padding(
                        padding: EdgeInsets.only(
                            right: entry.key < _chips.length - 1 ? 8 : 0),
                        child: GestureDetector(
                          onTap: () => _select(key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? color : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel
                                      ? color
                                      : Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(label,
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: sel
                                            ? Colors.white
                                            : AppTheme.textGrey)),
                                if (count > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? Colors.white.withOpacity(0.3)
                                          : color.withOpacity(0.15),
                                      borderRadius:
                                      BorderRadius.circular(10),
                                    ),
                                    child: Text('$count',
                                        style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: sel
                                                ? Colors.white
                                                : color)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),

          if (odoo.customersState != LoadState.loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${list.length} customer${list.length == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textGrey),
                ),
              ),
            ),

          Expanded(
            child: odoo.customersState == LoadState.loading
                ? const OdooLoader()
                : list.isEmpty
                ? _emptyState(odoo)
                : ListView.builder(
              padding:
              const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: list.length,
              itemBuilder: (_, i) =>
                  _card(context, list[i], odoo),
            ),
          ),
        ],
      ),

    );
  }

  int _taskCountForKey(String key, OdooCubit odoo) {
    switch (key) {
      case 'urgent': return odoo.emergencyTasks.length;
      case 'normal': return odoo.periodicTasks.length;
    // case 'survey': return odoo.surveyTasks.length; // SURVEY — commented out
      default:       return 0;
    }
  }

  List<Map<String, dynamic>> _buildList(OdooCubit odoo) {

    final emergencyIds = _partnerIds(odoo.emergencyTasks);
    final periodicIds  = _partnerIds(odoo.periodicTasks);
    // final surveyIds    = _partnerIds(odoo.surveyTasks);    // SURVEY — commented out
    // final spareIds     = _partnerIds(odoo.sparePartsTasks); // SPARE PARTS — commented out

    var list = odoo.customers.map((p) {
      final id = p['id'] as int;

      String type = 'PERIODIC';
      if (emergencyIds.contains(id))     type = 'EMERGENCY';
      // else if (spareIds.contains(id))    type = 'SPARE PARTS'; // SPARE PARTS — commented out
      // else if (surveyIds.contains(id))   type = 'SURVEY'; // SURVEY — commented out
      else if (periodicIds.contains(id)) type = 'PERIODIC';

      final street   = p['street']?.toString() ?? '';
      final city     = p['city']?.toString()   ?? '';
      final location = [street, city].where((s) => s.isNotEmpty).join(', ');

      final allCustomerTasks = odoo.myTasks.where((t) {
        final pt = t['partner_id'];
        return pt is List && pt[0] == id;
      }).toList();

      List<Map<String, dynamic>> filteredTasks;
      if (_priority == 'all') {
        filteredTasks = allCustomerTasks;
      } else {

        final Set<dynamic> bucketTaskIds;
        switch (_priority) {
          case 'urgent': bucketTaskIds = odoo.emergencyTasks.map((t) => t['id']).toSet(); break;
          case 'normal': bucketTaskIds = odoo.periodicTasks.map((t) => t['id']).toSet();  break;
        // case 'survey': bucketTaskIds = odoo.surveyTasks.map((t) => t['id']).toSet(); // SURVEY — commented out
          default:       bucketTaskIds = {};
        }
        filteredTasks = allCustomerTasks
            .where((t) => bucketTaskIds.contains(t['id']))
            .toList();
      }

      return <String, dynamic>{
        'id': id,
        'name': p['name'] ?? '',
        'location': location,
        'street': street,
        'city': city,
        'phone': p['phone'] ?? '',
        'email': p['email'] ?? '',
        'type': type,
        'tasks': filteredTasks,
        'allTasks': allCustomerTasks,
        'source': 'partner',
      };
    }).toList();

    for (final eq in odoo.equipment) {
      list.add({
        'id': eq['id'],
        'name': eq['name'] ?? '',
        'location': eq['location'] ?? '',
        'street': '', 'city': '',
        'type': 'PERIODIC',
        'tasks': <Map<String, dynamic>>[],
        'allTasks': <Map<String, dynamic>>[],
        'source': 'equipment',
      });
    }

    switch (_priority) {
      case 'urgent':
        list = list.where((c) => emergencyIds.contains(c['id'])).toList();
        break;
      case 'normal':
        list = list.where((c) =>
        periodicIds.contains(c['id']) &&
            !emergencyIds.contains(c['id'])).toList();
        break;
    // case 'survey': // SURVEY — commented out
    //   list = list.where((c) => surveyIds.contains(c['id'])).toList();
    //   break;
      default:
        break;
    }

    if (_search.isNotEmpty) {
      list = list.where((c) =>
      c['name'].toString().toLowerCase().contains(_search) ||
          c['location'].toString().toLowerCase().contains(_search)).toList();
    }

    return list;
  }

  Set<int> _partnerIds(List<Map<String, dynamic>> tasks) {
    final ids = <int>{};
    for (final t in tasks) {
      final p = t['partner_id'];
      if (p is List && p.isNotEmpty) ids.add(p[0] as int);
    }
    return ids;
  }

  Widget _emptyState(OdooCubit odoo) {
    final label = _chipLabel[_priority] ?? 'selected';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _search.isNotEmpty
                ? 'No results for "$_search"'
                : 'No customers match your filter.',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textGrey),
            textAlign: TextAlign.center,
          ),
          if (_priority != 'all') ...[
            const SizedBox(height: 6),
            Text('No $label tasks found.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textGrey)),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              odoo.fetchCustomers();
              odoo.fetchMyTasks();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('Refresh',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> c,
      OdooCubit odoo) {
    final type        = c['type'] as String;
    final isEmergency = type == 'EMERGENCY';
    // final isSurvey    = type == 'SURVEY'; // SURVEY — commented out
    final Color badgeColor = isEmergency
        ? const Color(0xFFFF5722)
    // SURVEY — commented out: : isSurvey ? AppTheme.primary
        : AppTheme.textDark;

    final name     = c['name'] as String;
    final address  = c['location'] as String;
    final tasks    = c['tasks'] as List<Map<String, dynamic>>;
    final initials = name.isNotEmpty
        ? name.split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerDetailScreen(
            customer: c,
            tasks: tasks,
            filterType: isEmergency
                ? 'emergency'
            // SURVEY — commented out: : isSurvey ? 'survey'
                : 'periodic',
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
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
                          child: Text(type,
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
                    ]),
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
        ]),
      ),
    );
  }
}