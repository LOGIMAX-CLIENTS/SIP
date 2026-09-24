import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/security/secure_logger.dart';

/// Service to download and cache invoice PDFs locally.
///
/// • Downloads PDF using Dio into the device's temporary directory.
/// • Caches by URL-derived filename — re-opening skips the download.
/// • Throws [InvoiceException] on any failure for clean UI handling.
class InvoiceService {
  InvoiceService._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    responseType: ResponseType.bytes,
  ));

  /// Downloads the PDF from [url] and returns the local [File].
  ///
  /// If the file is already cached, returns it immediately.
  /// [onProgress] reports download progress (0.0 – 1.0).
  static Future<File> downloadInvoice(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    // ── Validate URL ──
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.host.contains('.')) {
      throw const InvoiceException('Invalid invoice URL');
    }

    // ── Build cache path ──
    final tempDir = await getTemporaryDirectory();
    final invoiceDir = Directory(p.join(tempDir.path, 'invoices'));
    if (!invoiceDir.existsSync()) {
      invoiceDir.createSync(recursive: true);
    }

    // Derive a safe filename from the URL path (last segment or hash)
    String fileName = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : '${url.hashCode.abs()}.pdf';
    if (!fileName.toLowerCase().endsWith('.pdf')) {
      fileName = '$fileName.pdf';
    }
    final filePath = p.join(invoiceDir.path, fileName);
    final file = File(filePath);

    // ── Return cached file if it exists and is non-empty ──
    if (file.existsSync() && file.lengthSync() > 0) {
      SecureLogger.d('Invoice loaded from cache');
      return file;
    }

    // ── Download ──
    try {
      SecureLogger.d('Downloading invoice...');
      final response = await _dio.get<List<int>>(
        url,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      if (response.data == null || response.data!.isEmpty) {
        throw const InvoiceException('Empty response from server');
      }

      // Write to cache
      await file.writeAsBytes(response.data!, flush: true);
      SecureLogger.d('Invoice downloaded successfully');
      return file;
    } on DioException catch (e) {
      // ── Timeout ──
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const InvoiceException(
            'Connection timed out. Please check your internet and try again.');
      }
      // ── No network ──
      if (e.type == DioExceptionType.connectionError) {
        throw const InvoiceException(
            'No internet connection. Please check your network.');
      }
      // ── HTTP status errors (404, 401, 500, etc.) ──
      final statusCode = e.response?.statusCode;
      if (statusCode != null) {
        switch (statusCode) {
          case 404:
            throw const InvoiceException(
                'Invoice not available. It may not have been generated yet.');
          case 401:
          case 403:
            throw const InvoiceException(
                'Access denied. Please log in again and retry.');
          case 500:
          case 502:
          case 503:
            throw const InvoiceException(
                'Server is temporarily unavailable. Please try again later.');
          default:
            throw InvoiceException(
                'Unable to download invoice (Error $statusCode).');
        }
      }
      throw const InvoiceException(
          'Failed to download invoice. Please try again.');
    } catch (e) {
      if (e is InvoiceException) rethrow;
      throw const InvoiceException(
          'Something went wrong. Please try again later.');
    }
  }

  /// Clears all cached invoices.
  static Future<void> clearCache() async {
    final tempDir = await getTemporaryDirectory();
    final invoiceDir = Directory(p.join(tempDir.path, 'invoices'));
    if (invoiceDir.existsSync()) {
      invoiceDir.deleteSync(recursive: true);
    }
  }
}

/// Typed exception for invoice download/render failures.
class InvoiceException implements Exception {
  final String message;
  const InvoiceException(this.message);

  @override
  String toString() => message;
}
