import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';
import './parts_search_screen.dart';

class _CartItem {
  final Map<String, dynamic> product;
  int quantity;
  String importance; 
  _CartItem({required this.product, this.quantity = 1, this.importance = 'Regular'});
}

class AddSparePartScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  const AddSparePartScreen({super.key, required this.task});

  @override
  State<AddSparePartScreen> createState() => _AddSparePartScreenState();
}

class _AddSparePartScreenState extends State<AddSparePartScreen> {
  final List<_CartItem> _cart = [];
  final _causeCtrl = TextEditingController();
  List<File> _faultImages = [];
  bool _saving = false;

  @override
  void dispose() {
    _causeCtrl.dispose();
    super.dispose();
  }

  
  void _addToCart(Map<String, dynamic> product) {
    final id = product['id'];
    final existing = _cart.where((i) => i.product['id'] == id).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.quantity++);
    } else {
      setState(() => _cart.add(_CartItem(product: product)));
    }
  }

  Future<void> _pickProduct() async {
    final result = await Navigator.push<dynamic>(
        context, MaterialPageRoute(builder: (_) => const PartsSearchScreen()));
    if (result == null) return;
    if (result is List) {
      for (final p in result) {
        _addToCart(p as Map<String, dynamic>);
      }
    } else if (result is Map<String, dynamic>) {
      _addToCart(result);
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null && mounted) {
        setState(() => _faultImages.add(File(picked.path)));
      }
    } catch (_) {}
  }

  
  Future<void> _done() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please add at least one part.')));
      return;
    }
    setState(() => _saving = true);

    final odoo   = context.read<OdooCubit>();
    final taskId = widget.task['id'] as int;

    if (odoo.service == null) {
      if (mounted) setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No Odoo connection')));
      return;
    }

    final items = _cart.map((i) => {
      'product_id': i.product['id'] as int,
      'qty':        i.quantity.toDouble(),
    }).toList();

    int savedCount = 0;

    try {
      final res = await odoo.service!.addMaterialsBatch(
          taskId: taskId, items: items);

      if (res['success'] == true) {
        savedCount = _cart.length;
      } else if (res['results'] != null) {
        final results = res['results'] as List;
        savedCount = results.where((r) => r['success'] == true).length;
        if (savedCount == 0) {
          throw Exception(res['error'] ?? 'batch failed');
        }
      } else {
        throw Exception(res['error'] ?? 'endpoint unavailable');
      }
    } catch (_) {
      for (final item in _cart) {
        try {
          final err = await odoo.service!.addMaterialToTask(
            taskId:      taskId,
            productId:   item.product['id'] as int,
            qty:         item.quantity.toDouble(),
            productName: item.product['name']?.toString() ?? '',
          );
          if (err == null) savedCount++;
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (savedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save parts — check Odoo connection',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '$savedCount part${savedCount > 1 ? 's' : ''} added to Odoo ✓',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));

    Navigator.pop(context, {'added': savedCount});
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
        title: Text('Add Spare Parts',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppTheme.textDark)),
        centerTitle: true,
        actions: [
          if (_cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('${_cart.length}',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [

          
          if (_cart.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Selected Parts',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark)),
            ),
            const SizedBox(height: 8),
            ..._cart.map((item) => _cartItemRow(item)),
          ],

          const SizedBox(height: 16),

          
          GestureDetector(
            onTap: _pickProduct,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Center(
                    child: Icon(Icons.add,
                        size: 28, color: AppTheme.primary),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(
                  _cart.isEmpty
                      ? 'Select a spare part'
                      : 'Add another part',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary),
                )),
                Icon(Icons.chevron_right,
                    color: Colors.grey.shade400, size: 22),
              ]),
            ),
          ),

          const SizedBox(height: 20),

          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Cause of Failure',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark)),
              const SizedBox(height: 10),
              Container(
                height: 100,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200)),
                child: TextField(
                  controller: _causeCtrl,
                  maxLines: null,
                  decoration: InputDecoration(
                      hintText: 'Describe what happened...',
                      hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade400),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14)),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Image of Fault',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark)),
              const SizedBox(height: 10),
              Row(children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.orange.shade100)),
                    child: Center(
                      child: Icon(Icons.add_a_photo_outlined,
                          size: 28,
                          color: Colors.orange.shade400),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ..._faultImages.map((f) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(f,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2, right: 2,
                      child: GestureDetector(
                        onTap: () => setState(
                            () => _faultImages.remove(f)),
                        child: Container(
                          width: 20, height: 20,
                          decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              size: 12,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                )),
              ]),
            ]),
          ),

          const SizedBox(height: 32),

          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_saving || _cart.isEmpty) ? null : _done,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor:
                        AppTheme.primary.withOpacity(0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                child: _saving
                    ? const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _cart.isEmpty
                                ? 'Select parts first'
                                : 'Add ${_cart.length} Part${_cart.length > 1 ? 's' : ''} to Task',
                            style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle_outline,
                              color: Colors.white, size: 20),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  
  Widget _cartItemRow(_CartItem item) {
    final name = item.product['name']?.toString() ?? 'Part';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100)),
      child: Row(children: [
        
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.inventory_2_outlined,
              size: 22, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),

        
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            
            Row(children: [
              _importanceBadge(item, 'Regular'),
              const SizedBox(width: 6),
              _importanceBadge(item, 'Urgent'),
            ]),
          ],
        )),

        
        Row(children: [
          _qtyBtn(Icons.remove, () {
            setState(() {
              if (item.quantity > 1) item.quantity--;
              else _cart.remove(item);
            });
          }),
          SizedBox(
            width: 32,
            child: Text('${item.quantity}',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark)),
          ),
          _qtyBtn(Icons.add, () => setState(() => item.quantity++)),
        ]),
      ]),
    );
  }

  Widget _importanceBadge(_CartItem item, String label) {
    final selected = item.importance == label;
    return GestureDetector(
      onTap: () => setState(() => item.importance = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: selected
                ? (label == 'Urgent'
                    ? const Color(0xFFFFECEC)
                    : AppTheme.primary.withOpacity(0.1))
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected
                    ? (label == 'Urgent'
                        ? const Color(0xFFE53935)
                        : AppTheme.primary)
                    : AppTheme.textGrey)),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: const BoxDecoration(
          color: AppTheme.primary, shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: Colors.white),
    ),
  );
}
