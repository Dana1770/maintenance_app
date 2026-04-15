import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/odoo_cubit.dart';
import '../../../customers/ui/screens/task_customers_screen.dart';

/// Spare Parts entry point — shows only tasks with type "spare parts" from Odoo.
class SparePartsTasksScreen extends StatelessWidget {
  const SparePartsTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<OdooCubit>().sparePartsTasks;
    return TaskCustomersScreen(
      title      : 'Views',
      filterType : 'spare_parts',
      tasks      : tasks,
    );
  }
}
