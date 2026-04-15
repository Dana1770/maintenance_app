import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../spare_parts/ui/screens/spare_parts_screen.dart';

class MaintenanceGuideScreen extends StatefulWidget {
  const MaintenanceGuideScreen({super.key});

  @override
  State<MaintenanceGuideScreen> createState() => _MaintenanceGuideScreenState();
}

class _MaintenanceGuideScreenState extends State<MaintenanceGuideScreen> {
  int _currentStep = 1;
  final Map<String, bool> _tasks = {
    'Balancing the engine during operation': true,
    'Door shoes': true,
    'Bad link': false,
    'Oil': true,
    'Gas Oil': false,
  };
  final TextEditingController _notesController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Maintenance #39254',
            style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Step $_currentStep of 18',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppTheme.textGrey)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('5% COMPLETE',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 0.05,
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 20),
            // Step content
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stop the elevator car on the first floor.',
                      style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                          height: 1.3)),
                  const SizedBox(height: 12),
                  Text(
                      'Switch the elevator to inspection mode and move the car to the 1st floor. Verify perfect leveling with the floor landing. Secure all entrances with barriers, then strictly follow Lockout/Tagout (LOTO) procedures to isolate power.',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textGrey,
                          height: 1.6)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFFF8F00), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              'Ensure LOTO locks are applied by all technicians on site.',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textDark,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Next Step button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () =>
                    setState(() => _currentStep = (_currentStep % 18) + 1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.arrow_forward,
                    color: Colors.white, size: 18),
                label: Text('Next Step',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
            const SizedBox(height: 24),
            // Maintenance Tasks
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Maintenance Tasks',
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark)),
              ],
            ),
            const SizedBox(height: 4),
            Text('3 of 8 completed',
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppTheme.textGrey)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 3 / 8,
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 14),
            // Full-width task
            _buildFullWidthTask(
                'Balancing the engine during operation', true),
            const SizedBox(height: 10),
            // Two-column tasks
            Row(
              children: [
                Expanded(
                    child: _buildTask('Door shoes', true)),
                const SizedBox(width: 10),
                Expanded(
                    child: _buildTask('Bad link', false)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildTask('Oil', true)),
                const SizedBox(width: 10),
                Expanded(child: _buildTask('Gas Oil', false)),
              ],
            ),
            const SizedBox(height: 16),
            // Navigation
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.arrow_back,
                        size: 16, color: AppTheme.textDark),
                    label: Text('Previous',
                        style: GoogleFonts.inter(
                            color: AppTheme.textDark,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    label: Text('Next Step',
                        style: GoogleFonts.inter(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    icon: const Icon(Icons.arrow_forward,
                        size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Notes
            Text('MAINTENANCE TECHNICIAN NOTES',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textGrey,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _notesController,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Type your observations here...',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 13, color: AppTheme.textGrey),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Spare Parts button
            GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SparePartsScreen())),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.textDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('Spare Parts Management',
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Customer Feedback
            Text('CUSTOMER FEEDBACK',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textGrey,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Client comments...',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 13, color: AppTheme.textGrey),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Signature button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.draw_outlined,
                      color: AppTheme.textDark, size: 20),
                  const SizedBox(width: 8),
                  Text('Customer Signature Required',
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Complete button
            Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text('COMPLETE MAINTENANCE',
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildFullWidthTask(String label, bool checked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: checked ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: checked ? AppTheme.primary : Colors.grey.shade300,
                  width: 2),
            ),
            child: checked
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textDark)),
          ),
        ],
      ),
    );
  }

  Widget _buildTask(String label, bool checked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: checked ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: checked ? AppTheme.primary : Colors.grey.shade300,
                  width: 2),
            ),
            child: checked
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textDark)),
          ),
        ],
      ),
    );
  }
}
