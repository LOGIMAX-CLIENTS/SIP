import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_toast.dart';

class ProfilePhotoWidget extends StatefulWidget {
  final String? initialPhotoUrl;
  final String initials;
  final Function(File) onPhotoSelected;
  final bool isLoading;

  const ProfilePhotoWidget({
    super.key,
    this.initialPhotoUrl,
    required this.initials,
    required this.onPhotoSelected,
    this.isLoading = false,
  });

  @override
  State<ProfilePhotoWidget> createState() => _ProfilePhotoWidgetState();
}

class _ProfilePhotoWidgetState extends State<ProfilePhotoWidget> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      // On Android 13+: image_picker uses the system Photo Picker — no permission needed.
      // On Android ≤ 12: READ_EXTERNAL_STORAGE is declared with maxSdkVersion=32.
      // Camera permission is handled automatically by image_picker.

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final file = File(image.path);
        final sizeInBytes = await file.length();
        final sizeInMb = sizeInBytes / (1024 * 1024);

        if (sizeInMb > 5) {
          if (mounted) {
            AppToast.show(context, 'Image is too large. Maximum allowed size is 5MB.', type: ToastType.error);
          }
          return;
        }
        _cropImage(file);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error picking image: $e');
    }
  }

  Future<void> _cropImage(File imageFile) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 90,
        maxWidth: 512,
        maxHeight: 512,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Photo',
            toolbarColor: AppTheme.arcticBlue,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop Profile Photo',
            aspectRatioLockEnabled: true,
          ),
        ],
      );

      if (croppedFile != null) {
        setState(() {
          _selectedImage = File(croppedFile.path);
        });
        widget.onPhotoSelected(_selectedImage!);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error cropping image: $e');
    }
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.arcticBlue),
              title: Text('Take Photo', style: GoogleFonts.playfairDisplay()),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppTheme.arcticBlue),
              title: Text('Choose from Gallery', style: GoogleFonts.playfairDisplay()),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.grey),
              title: Text('Cancel', style: GoogleFonts.playfairDisplay()),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isLoading ? null : _showPickerOptions,
      child: Stack(
        children: [
          Container(
            width: 100.w,
            height: 100.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: _selectedImage != null
                  ? FileImage(_selectedImage!)
                  : (widget.initialPhotoUrl != null
                      ? NetworkImage(widget.initialPhotoUrl!) as ImageProvider
                      : null),
              child: _selectedImage == null && widget.initialPhotoUrl == null
                  ? Text(
                      widget.initials,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 36.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.arcticBlue,
                      ),
                    )
                  : null,
            ),
          ),
          if (widget.isLoading)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(8.w),
              decoration: const BoxDecoration(
                color: AppTheme.arcticBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 16.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

