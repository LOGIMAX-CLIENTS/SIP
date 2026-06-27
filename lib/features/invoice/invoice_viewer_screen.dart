import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/theme/app_theme.dart';

/// Full-screen in-app PDF viewer for invoices.
///
/// Receives [filePath] (local cached PDF) via route arguments.
/// Renders the PDF using Syncfusion's `SfPdfViewer.file()`.
class InvoiceViewerScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const InvoiceViewerScreen({
    super.key,
    required this.filePath,
    this.title = 'Invoice',
  });

  @override
  State<InvoiceViewerScreen> createState() => _InvoiceViewerScreenState();
}

class _InvoiceViewerScreenState extends State<InvoiceViewerScreen> {
  late final PdfViewerController _pdfViewerController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _validateFile();
  }

  void _validateFile() {
    final file = File(widget.filePath);
    if (!file.existsSync() || file.lengthSync() == 0) {
      setState(() {
        _errorMessage = 'Invoice file not found or corrupted.';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20.sp),
          color: Colors.white,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w600,
            fontSize: 18.sp,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.download_rounded, size: 22.sp),
            color: Colors.white,
            tooltip: 'Download / Share',
            onPressed: () async {
              final file = XFile(widget.filePath);
              await Share.shareXFiles(
                [file],
                subject: 'startGOLD Invoice',
              );
            },
          ),
          SizedBox(width: 8.w),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.87, -0.5),
              end: Alignment(0.87, 0.5),
              colors: [Color(0xFF003716), Color(0xFF167525)],
              stops: [0.0223, 0.9399],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _errorMessage != null
          ? _buildErrorState(isDark)
          : Stack(
              children: [
                SfPdfViewer.file(
                  File(widget.filePath),
                  controller: _pdfViewerController,
                  canShowScrollHead: true,
                  canShowScrollStatus: true,
                  enableDoubleTapZooming: true,
                  onDocumentLoaded: (details) {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  },
                  onDocumentLoadFailed: (details) {
                    if (mounted) {
                      setState(() {
                        _isLoading = false;
                        _errorMessage =
                            'Failed to load PDF: ${details.description}';
                      });
                    }
                  },
                ),
                if (_isLoading)
                  Container(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.85),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 40.r,
                            height: 40.r,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.primaryGreen,
                              ),
                            ),
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            'Loading Invoice...',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 14.sp,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_rounded,
              size: 64.sp,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            SizedBox(height: 20.h),
            Text(
              'Unable to Load Invoice',
              style: GoogleFonts.playfairDisplay(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              _errorMessage ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                color: isDark ? Colors.white54 : Colors.black45,
                height: 1.5,
              ),
            ),
            SizedBox(height: 28.h),
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B882C), Color(0xFF003716)],
                  ),
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(
                    'Go Back',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
