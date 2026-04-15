import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/odoo_cubit.dart';
import './task_customers_screen.dart';

/// Periodic tab: shows customers from tasks where fs_task_type_id name contains "periodic"
class PeriodicCustomersScreen extends StatelessWidget {
  const PeriodicCustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<OdooCubit>().periodicTasks;
    return TaskCustomersScreen(
      title: 'Views',
      filterType: 'periodic',
      tasks: tasks,
    );
  }
}
