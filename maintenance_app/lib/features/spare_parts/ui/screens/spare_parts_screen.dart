import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';

class SparePartsScreen extends StatefulWidget {
  const SparePartsScreen({super.key});
  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final odoo = context.read<OdooCubit>();
      if (odoo.sparePartsState == LoadState.idle) odoo.fetchSpareParts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final odoo = context.watch<OdooCubit>();

    final all = odoo.spareParts;
    final filtered = _search.isEmpty
        ? all
        : all.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final code = (p['default_code'] ?? '').toString().toLowerCase();
      final cat  = p['categ_id'] is List
          ? (p['categ_id'] as List)[1].toString().toLowerCase()
          : '';
      return name.contains(_search) ||
          code.contains(_search) ||
          cat.contains(_search);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background, elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: Text('Spare Parts',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppTheme.textDark)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primary),
            onPressed: () => odoo.fetchSpareParts(),
          ),
        ],
      ),
      body: Column(children: [
        // Search
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
                  hintText: 'Search by name, code or category...',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 13, color: AppTheme.textGrey),
                  border: InputBorder.none, isDense: true,
                ),
              )),
            ]),
          ),
        ),

        // Source label
        if (odoo.sparePartsState == LoadState.loaded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(children: [
              Icon(Icons.inventory_2_outlined,
                  size: 12, color: AppTheme.textGrey),
              const SizedBox(width: 4),
              Text('${all.length} products · Field Service / Odoo',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppTheme.textGrey)),
            ]),
          ),

        // Body
        Expanded(
          child: odoo.sparePartsState == LoadState.loading
              ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
              : odoo.sparePartsState == LoadState.error
              ? Center(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline,
                color: AppTheme.error, size: 40),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(odoo.sparePartsError ?? 'Error',
                  style: GoogleFonts.inter(
                      color: AppTheme.error, fontSize: 13),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: odoo.fetchSpareParts,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary),
                child: Text('Retry',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700))),
          ]))
              : filtered.isEmpty
              ? Center(child: Text(
              _search.isEmpty
                  ? 'No products found in Odoo'
                  : 'No results for "$_search"',
              style: GoogleFonts.inter(
                  color: AppTheme.textGrey, fontSize: 14)))
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _partCard(filtered[i]),
          ),
        ),
      ]),
    );
  }

  Widget _partCard(Map<String, dynamic> p) {
    final name    = p['name']?.toString() ?? 'Unknown';
    final code    = p['default_code']?.toString() ?? '';
    final price   = p['list_price'];
    final qty     = p['qty_available'];
    final categ   = p['categ_id'] is List
        ? (p['categ_id'] as List)[1].toString() : '';
    final type    = p['type']?.toString() ?? '';

    final qtyNum  = qty is num ? qty.toDouble() : 0.0;
    final inStock = qtyNum > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        // Icon
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.settings_outlined,
              color: AppTheme.primary, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppTheme.textDark),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          if (code.isNotEmpty)
            Text('SKU: $code',
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppTheme.textGrey)),
          if (categ.isNotEmpty)
            Text(categ,
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppTheme.textGrey)),
          if (type.isNotEmpty)
            Text(type == 'product' ? 'Storable' : 'Consumable',
                style: GoogleFonts.inter(
                    fontSize: 10, color: AppTheme.textGrey)),
          const SizedBox(height: 6),
          Row(children: [
            // Price
            if (price != null)
              Text('\$${(price as num).toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: AppTheme.primary)),
            const Spacer(),
            // Stock badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: inStock
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                inStock
                    ? 'In Stock (${qtyNum % 1 == 0 ? qtyNum.toInt() : qtyNum})'
                    : 'Out of Stock',
                style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: inStock
                        ? Colors.green.shade700
                        : Colors.red.shade700),
              ),
            ),
          ]),
        ])),
      ]),
    );
  }
}