import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';
import './add_spare_part_screen.dart';

class TaskSparePartsScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  const TaskSparePartsScreen({super.key, required this.task});

  @override
  State<TaskSparePartsScreen> createState() => _TaskSparePartsScreenState();
}

class _TaskSparePartsScreenState extends State<TaskSparePartsScreen> {
  List<Map<String, dynamic>> _materials = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final odoo = context.read<OdooCubit>();
    if (odoo.service == null) { setState(() => _loading = false); return; }
    try {
      final mats = await odoo.service!.fetchFSMMaterials(widget.task['id'] as int);
      if (mounted) setState(() { _materials = mats; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteMaterial(Map<String, dynamic> m) async {
    final materialId = m['id'];
    if (materialId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Part',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          'Remove "${_prodName(m)}" from this task?',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppTheme.textGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove',
                style: GoogleFonts.inter(
                    color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final odoo    = context.read<OdooCubit>();
    final taskId  = widget.task['id'] as int;
    bool success  = false;

    try {
      final res = await odoo.service!.deleteMaterial(
          taskId: taskId, materialId: materialId as int);
      success = res == true;
    } catch (_) {}

    if (!mounted) return;

    if (success) {
      // Reload from server to ensure UI is in sync with Odoo
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Part removed ✓',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not remove part',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  String _prodName(Map<String, dynamic> m) {
    final prod = m['product_id'];
    return prod is List ? prod[1].toString() : m['name']?.toString() ?? 'Part';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18,
              color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Spare Parts (${_materials.length})',
            style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primary),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, color: AppTheme.error, size: 48),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(_error!,
            style: GoogleFonts.inter(color: AppTheme.error),
            textAlign: TextAlign.center),
      ),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
        style:
            ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
      ),
    ]),
  );

  Widget _buildBody() {
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(children: [
            if (_materials.isEmpty) _buildEmpty(),
            ..._materials.map((m) => _partCard(m)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _goAddPart,
              child: Column(children: [
                Container(
                  width: 64, height: 64,
                  decoration: const BoxDecoration(
                      color: AppTheme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.add,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 8),
                Text('Add New Part',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textGrey)),
              ]),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
            child: Text('Save',
                style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ),
      ),
    ]);
  }

  Widget _buildEmpty() => Container(
    margin: const EdgeInsets.only(bottom: 24),
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16)),
    child: Column(children: [
      Icon(Icons.inventory_2_outlined,
          size: 52, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text('No parts added yet',
          style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textGrey)),
      const SizedBox(height: 4),
      Text('Tap + below to add a spare part',
          style: GoogleFonts.inter(
              fontSize: 12, color: Colors.grey.shade400)),
    ]),
  );

  Future<void> _goAddPart() async {
    final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
            builder: (_) => AddSparePartScreen(task: widget.task)));
    if (result != null && mounted) await _load();
  }

  Widget _partCard(Map<String, dynamic> m) {
    final name     = _prodName(m);
    final qty      = m['product_uom_qty'] ?? m['quantity'] ?? m['qty'] ?? 1;
    final code     = m['default_code']?.toString() ?? '';
    final imgData  = m['image_128'] ?? m['image_1920'] ?? m['image'];
    final isUrgent = (m['importance']?.toString().toLowerCase() == 'urgent') ||
                     (m['priority']?.toString() == '1');
    final price    = (m['price_unit'] ?? m['list_price'] ?? 0) as num;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
          child: _buildImage(imgData, name),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            if (isUrgent) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFECEC),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('URGENT',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFE53935),
                        letterSpacing: 0.5)),
              ),
              const SizedBox(height: 6),
            ],
            Text(name,
                style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark)),
            const SizedBox(height: 4),
            if (code.isNotEmpty)
              Text('S/N: $code',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppTheme.textGrey)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('Qty: $qty',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary)),
                ),
                Row(children: [
                  TextButton(
                    onPressed: () => _showPartDetail(m),
                    style: TextButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    child: Text('Details',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _deleteMaterial(m),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFE53935)),
                    ),
                  ),
                ]),
              ],
            ),
            if (price > 0) ...[
              const SizedBox(height: 4),
              Text('${price.toStringAsFixed(2)} SR',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppTheme.textGrey)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildImage(dynamic imgData, String name) {
    if (imgData != null &&
        imgData != false &&
        imgData.toString().isNotEmpty) {
      try {
        final bytes = base64Decode(imgData.toString());
        return Image.memory(bytes,
            width: double.infinity,
            height: 160,
            fit: BoxFit.cover);
      } catch (_) {}
    }
    return Container(
      height: 160,
      width: double.infinity,
      color: AppTheme.primary.withOpacity(0.08),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        Icon(Icons.precision_manufacturing_outlined,
            size: 48, color: AppTheme.primary.withOpacity(0.3)),
        const SizedBox(height: 8),
        Text(name,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppTheme.textGrey),
            textAlign: TextAlign.center,
            maxLines: 2),
      ]),
    );
  }

  void _showPartDetail(Map<String, dynamic> m) {
    final name  = _prodName(m);
    final qty   = m['product_uom_qty'] ?? m['quantity'] ?? 1;
    final code  = m['default_code']?.toString() ?? '';
    final price = (m['price_unit'] ?? m['list_price'] ?? 0) as num;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text(name,
              style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark)),
          const SizedBox(height: 16),
          if (code.isNotEmpty) _detailRow('Serial / Code', code),
          _detailRow('Quantity', qty.toString()),
          if (price > 0)
            _detailRow('Price', '${price.toStringAsFixed(2)} SR'),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textGrey,
                fontWeight: FontWeight.w500)),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark)),
      ],
    ),
  );
}
