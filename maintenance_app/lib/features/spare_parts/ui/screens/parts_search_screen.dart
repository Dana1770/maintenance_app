import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/odoo_cubit.dart';

class PartsSearchScreen extends StatefulWidget {
  const PartsSearchScreen({super.key});
  @override
  State<PartsSearchScreen> createState() => _PartsSearchScreenState();
}

class _PartsSearchScreenState extends State<PartsSearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<int> _selectedIds = {};
  final Map<int, Map<String, dynamic>> _selectedParts = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> parts) {
    if (_query.isEmpty) return parts;
    final q = _query.toLowerCase();
    return parts.where((p) =>
        p['name'].toString().toLowerCase().contains(q) ||
        (p['default_code'] ?? '').toString().toLowerCase().contains(q) ||
        _categoryName(p).toLowerCase().contains(q)).toList();
  }

  String _categoryName(Map<String, dynamic> p) {
    final c = p['categ_id'];
    if (c == null || c == false) return '';
    return (c is List ? c[1] : c).toString();
  }

  void _toggleSelection(Map<String, dynamic> p) {
    final id = p['id'] as int;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectedParts.remove(id);
      } else {
        _selectedIds.add(id);
        _selectedParts[id] = p;
      }
    });
  }

  void _confirmSelection() {
    Navigator.pop(context, _selectedParts.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final odoo      = context.watch<OdooCubit>();
    final allParts  = odoo.spareParts;
    final parts     = _filtered(allParts);
    final isLoading = odoo.sparePartsState == LoadState.loading;
    final count     = _selectedIds.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Parts',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
        centerTitle: true,
        actions: [
          if (count > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('$count',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: count == 0
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              onPressed: _confirmSelection,
              icon: const Icon(Icons.check, color: Colors.white),
              label: Text(
                'Add $count Part${count > 1 ? "s" : ""}',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white),
              ),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              const SizedBox(width: 14),
              Icon(Icons.search, color: AppTheme.textGrey, size: 20),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textDark),
                decoration: InputDecoration(
                    hintText: 'Searching for a spare part or serial number',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey),
                    border: InputBorder.none,
                    isDense: true),
              )),
              if (_query.isNotEmpty)
                GestureDetector(
                  onTap: () { _searchCtrl.clear(); setState(() => _query = ''); },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(Icons.close, size: 18, color: AppTheme.textGrey),
                  ),
                ),
            ]),
          ),
        ),

        if (!isLoading && allParts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _query.isEmpty ? 'RECENTLY VIEWED & POPULAR' : 'SEARCH RESULTS',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textGrey,
                    letterSpacing: 0.8),
              ),
            ),
          ),

        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : allParts.isEmpty
                  ? _emptyState()
                  : parts.isEmpty
                      ? _noResults()
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: parts.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 86,
                              color: Colors.grey.shade100),
                          itemBuilder: (_, i) => _partTile(parts[i]),
                        ),
        ),
      ]),
    );
  }

  Widget _partTile(Map<String, dynamic> p) {
    final id       = p['id'] as int;
    final name     = p['name']?.toString() ?? '';
    final code     = p['default_code']?.toString() ?? '';
    final categ    = _categoryName(p);
    final onHand   = (p['qty_available'] as num?)?.toInt() ?? 0;
    final hasImg   = p['image_128'] != null && p['image_128'] != false;
    final selected = _selectedIds.contains(id);

    return GestureDetector(
      onTap: () => _toggleSelection(p),
      child: Container(
        color: selected ? AppTheme.primary.withOpacity(0.05) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withOpacity(0.12)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10)),
            clipBehavior: Clip.antiAlias,
            child: hasImg
                ? _buildImage(p['image_128'].toString())
                : _partIcon(categ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark)),
              const SizedBox(height: 2),
              if (categ.isNotEmpty)
                Text(categ,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary)),
              if (code.isNotEmpty)
                Text(code,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppTheme.textGrey)),
            ],
          )),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? AppTheme.primary : Colors.grey.shade300,
                size: 22,
              ),
              if (onHand > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$onHand on hand',
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          color: Colors.green.shade600,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _buildImage(String b64) {
    try {
      return Image.memory(base64Decode(b64), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _partIcon(''));
    } catch (_) {
      return _partIcon('');
    }
  }

  Widget _partIcon(String categ) {
    IconData icon = Icons.inventory_2_outlined;
    final c = categ.toLowerCase();
    if (c.contains('door'))     icon = Icons.door_front_door_outlined;
    if (c.contains('motor') || c.contains('electric')) icon = Icons.electrical_services;
    if (c.contains('cable') || c.contains('rail'))     icon = Icons.linear_scale;
    if (c.contains('brake') || c.contains('safety'))  icon = Icons.security;
    if (c.contains('pulley') || c.contains('gear'))   icon = Icons.settings;
    return Center(child: Icon(icon, size: 26, color: Colors.grey.shade400));
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.inventory_2_outlined, size: 52, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text('No spare parts loaded',
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600,
              color: AppTheme.textGrey)),
      const SizedBox(height: 6),
      Text('Check your connection and try again',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey)),
    ]),
  );

  Widget _noResults() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text('No parts found for "$_query"',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600,
              color: AppTheme.textGrey)),
    ]),
  );
}
