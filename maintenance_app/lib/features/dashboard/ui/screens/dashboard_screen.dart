import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../auth/logic/session_cubit.dart';
import '../../../../core/di/odoo_cubit.dart';
import '../../../../core/di/timer_service.dart';
import '../../../customers/ui/screens/periodic_customers_screen.dart';
import '../../../customers/ui/screens/emergency_customers_screen.dart';
import '../../../customers/ui/screens/satisfaction_screen.dart';
import '../../../profile/ui/screens/profile_screen.dart';
import '../../../spare_parts/ui/screens/spare_parts_tasks_screen.dart';
import '../../../auth/ui/screens/login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OdooCubit>().fetchAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l       = AppLocalizations.of(context);
    final session = context.watch<SessionCubit>();
    final odoo    = context.watch<OdooCubit>();

    return ListenableBuilder(
      listenable: TimerService.instance,
      builder: (context, _) => _buildBody(context, l, session, odoo),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l,
      SessionCubit session, OdooCubit odoo) {
    final total    = odoo.totalTasks;
    final done     = odoo.doneTasks;
    final hours    = odoo.todayHoursSpent;
    final hoursStr = hours == 0 ? '0h'
        : hours < 1 ? '${(hours * 60).round()}m'
        : '${hours.toStringAsFixed(1)}h';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => odoo.fetchAll(),
          color: AppTheme.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Top bar ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const ProfileScreen())),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(
                                  color: AppTheme.primary.withOpacity(0.3),
                                  blurRadius: 8, offset: const Offset(0, 3))]),
                          child: const Icon(Icons.person, color: Colors.white, size: 22),
                        ),
                      ),
                      Text('Dashboard',
                          style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800,
                              color: AppTheme.textDark)),
                      GestureDetector(
                        onTap: () => showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => const _AppDrawer(),
                        ),
                        child: const Icon(Icons.menu, color: AppTheme.textDark, size: 26),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back!',
                            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800,
                                color: AppTheme.textDark)),
                        const SizedBox(height: 4),
                        odoo.tasksState == LoadState.loading
                            ? Text('Loading tasks...',
                            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey))
                            : Text('You have $total task${total == 1 ? '' : 's'} pending for today.',
                            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    _statBox('COMPLETED', done.toString(), '+${done > 0 ? done * 5 : 20}%', AppTheme.success),
                    const SizedBox(width: 10),
                    _statBox('HOURS', hoursStr, '+5%', AppTheme.primary),
                    const SizedBox(width: 10),
                    _statBox('RATINGS', '4.8', '+0.2%', const Color(0xFF2196F3)),
                  ]),
                ),
                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: _actionCard(
                        icon: Icons.calendar_today_rounded,
                        label: 'Periodic',
                        count: odoo.periodicTasks.length,
                        iconBg: const Color(0xFFFFF8E1),
                        iconColor: AppTheme.primary,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PeriodicCustomersScreen())),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _actionCard(
                        icon: Icons.emergency_rounded,
                        label: 'Emergency',
                        count: odoo.emergencyTasks.length,
                        iconBg: const Color(0xFFFFF0EB),
                        iconColor: const Color(0xFFFF5722),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const EmergencyCustomersScreen())),
                      )),
                    ]),
                    // const SizedBox(height: 12),
                    // Row(children: [
                    //   Expanded(child: _actionCard(
                    //     icon: Icons.build_rounded,
                    //     label: 'Spare Parts',
                    //     count: odoo.sparePartsTasks.length,
                    //     iconBg: const Color(0xFFEFF3FF),
                    //     iconColor: const Color(0xFF3F51B5),
                    //     onTap: () => Navigator.push(context,
                    //         MaterialPageRoute(builder: (_) => const SparePartsTasksScreen())),
                    //   )),
                    //   const SizedBox(width: 12),
                    //   Expanded(child: _actionCard(
                    //     icon: Icons.sentiment_satisfied_alt_rounded,
                    //     label: 'Satisfaction',
                    //     count: odoo.surveyTasks.length,
                    //     iconBg: const Color(0xFFEFFAF1),
                    //     iconColor: AppTheme.success,
                    //     onTap: () => Navigator.push(context,
                    //         MaterialPageRoute(builder: (_) => const SatisfactionScreen())),
                    //   )),
                    // ]),
                  ]),
                ),
                const SizedBox(height: 12),

                const SizedBox(height: 20),

                // ── Today's statistics ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Today's statistics",
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700,
                              color: AppTheme.textDark)),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          final worked = odoo.tasksWorkedToday;
                          if (worked.isEmpty) return;
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => _WorkedTasksSheet(tasks: worked),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(18)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('RESPONSE TIME',
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                                        color: Colors.white.withOpacity(0.75), letterSpacing: 0.6)),
                                const SizedBox(height: 6),
                                odoo.tasksState == LoadState.loading
                                    ? const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : Text(odoo.responseTimeDisplay,
                                    style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900,
                                        color: Colors.white)),
                              ]),
                              Container(width: 48, height: 48,
                                  decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                                  child: const Icon(Icons.timer_outlined, color: Colors.white, size: 26)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statBox(String label, String value, String trend, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 8, offset: const Offset(0, 2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
              color: AppTheme.textGrey, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900,
              color: AppTheme.textDark)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.trending_up, size: 12, color: color),
            const SizedBox(width: 3),
            Text(trend, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
                color: color)),
          ]),
        ]),
      ),
    );
  }

  Widget _actionCard({required IconData icon, required String label, required VoidCallback onTap,
    int count = 0, required Color iconBg, required Color iconColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 10),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 10, offset: const Offset(0, 2))]),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(width: 56, height: 56,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 26)),
            if (count > 0)
              Positioned(top: -4, right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
                    child: Text('$count', style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                  )),
          ]),
          const SizedBox(height: 12),
          Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700,
              color: AppTheme.textDark), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ── App Drawer ────────────────────────────────────────────────────────────────
class _AppDrawer extends StatelessWidget {
  const _AppDrawer();
  @override
  Widget build(BuildContext context) {
    final l       = AppLocalizations.of(context);
    final session = context.watch<SessionCubit>();
    return Container(
      decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Row(children: [
            Container(width: 52, height: 52,
                decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                child: const Icon(Icons.person, color: Colors.white, size: 28)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(session.name.isNotEmpty ? session.name : 'Technician',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700,
                      color: AppTheme.textDark)),
            ])),
          ]),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          _item(context, icon: Icons.dashboard_outlined, label: 'Dashboard',
              onTap: () => Navigator.pop(context)),
          _item(context, icon: Icons.calendar_today_outlined, label: 'Periodic',
              onTap: () { Navigator.pop(context); Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PeriodicCustomersScreen())); }),
          _item(context, icon: Icons.emergency_outlined, label: 'Emergency',
              onTap: () { Navigator.pop(context); Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EmergencyCustomersScreen())); }),
          // _item(context, icon: Icons.build_outlined, label: 'Spare Parts',
          //     onTap: () { Navigator.pop(context); Navigator.push(context,
          //         MaterialPageRoute(builder: (_) => const SparePartsTasksScreen())); }),
          // _item(context, icon: Icons.sentiment_satisfied_alt_outlined, label: 'Satisfaction',
          //     onTap: () { Navigator.pop(context); Navigator.push(context,
          //         MaterialPageRoute(builder: (_) => const SatisfactionScreen())); }),
          _item(context, icon: Icons.person_outline, label: 'Profile',
              onTap: () { Navigator.pop(context); Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen())); }),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _item(context, icon: Icons.logout, label: 'Logout', color: AppTheme.error,
              onTap: () async {
                context.read<OdooCubit>().reset();
                await context.read<SessionCubit>().logout();
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.pushAndRemoveUntil(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
                }
              }),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, {required IconData icon, required String label,
    required VoidCallback onTap, Color? color}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(width: 40, height: 40,
          decoration: BoxDecoration(
              color: (color ?? AppTheme.primary).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color ?? AppTheme.primary, size: 20)),
      title: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600,
          color: color ?? AppTheme.textDark)),
      trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
      onTap: onTap,
    );
  }
}

// ── Worked Tasks Sheet ────────────────────────────────────────────────────────
class _WorkedTasksSheet extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;
  const _WorkedTasksSheet({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Today\'s Responses',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 8),
          Text('Tasks contributing to your response time today',
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textGrey)),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final t = tasks[i];
                final pName = (t['partner_id'] is List && (t['partner_id'] as List).length > 1)
                    ? (t['partner_id'] as List)[1].toString()
                    : 'Unknown Customer';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.task_alt, color: AppTheme.primary, size: 20),
                  ),
                  title: Text(t['name'] ?? 'Task', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text(pName, style: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                  onTap: () => Navigator.pop(ctx),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
