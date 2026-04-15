import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/odoo_cubit.dart';
import './task_customers_screen.dart';

/// Survey / Satisfaction screen — delegates to TaskCustomersScreen
/// so it shares the same 4-chip navigation bar as Periodic & Emergency.
class SatisfactionScreen extends StatelessWidget {
  const SatisfactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<OdooCubit>().surveyTasks;
    return TaskCustomersScreen(
      title      : 'Views',
      filterType : 'survey',
      tasks      : tasks,
    );
  }
}
