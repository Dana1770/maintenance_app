import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/odoo_cubit.dart';
import './task_customers_screen.dart';

class EmergencyCustomersScreen extends StatelessWidget {
  const EmergencyCustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<OdooCubit>().emergencyTasks;
    return TaskCustomersScreen(
      title: 'Views',
      filterType: 'emergency',
      tasks: tasks,
    );
  }
}
