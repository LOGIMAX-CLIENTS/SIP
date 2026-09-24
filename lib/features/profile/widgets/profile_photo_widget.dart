import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../../core/security/app_lifecycle_observer.dart';

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

class _ProfilePhotoWidgetState extends State<ProfilePhotoWidget>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  /// True once the picking/cropping is finished but the app lock is still
  /// suppressed, waiting for the resume that dismissing the last picker
  /// triggers. The camera and the cropper each pause and resume the app, so
  /// the suppression cannot be lifted on the first resume, and it cannot be
  /// lifted a frame after the crop future completes either -- iOS delivers
  /// that final resume a beat later, which is how the lock was still firing.
  bool _awaitingResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Never leave the lock suppressed because this screen went away mid-flow.
    if (_awaitingResume) {
      _awaitingResume = false;
      AppLifecycleObserver.suppressAppLock = false;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingResume) {
      // A frame later, so every other observer -- including the one that
      // decides whether to show the lock -- has already seen this resume.
      WidgetsBinding.instance.addPostFrameCallback((_) => _releaseAppLock());
    }
  }

  void _releaseAppLock() {
    if (!_awaitingResume) return;
    _awaitingResume = false;
    AppLifecycleObserver.suppressAppLock = false;
  }

  /// The profile API returns "" — not null — for a customer with no photo,
  /// so a null check alone let `NetworkImage("")` through and every such
  /// customer got "Invalid argument(s): No host specified in URI file:///"
  /// thrown on paint, once per rebuild.
  bool get _hasPhotoUrl =>
      widget.initialPhotoUrl != null && widget.initialPhotoUrl!.trim().isNotEmpty;

  Future<void> _pickImage(ImageSource source) async {
    // The camera and the cropper each present their own view controller, and
    // iOS reports the app as backgrounded while they are up. Without this the
    // lifecycle observer treats coming back as a return from the background
    // and throws up the MPIN lock -- on top of a modal that is still
    // dismissing, so screen_protector fastens its anti-screenshot overlay to
    // the wrong view and the screen stays black once the modal has gone. Same
    // suppression the payment and KYC flows already use for the same reason.
    AppLifecycleObserver.suppressAppLock = true;
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );

      if (kDebugMode) {
        debugPrint('[ProfilePhoto] pickImage returned: ${image?.path}');
      }

      if (image == null) {
        if (kDebugMode) {
          debugPrint('[ProfilePhoto] Camera / gallery dismissed without photo');
        }
        return;
      }

      final file = File(image.path);
      final sizeInBytes = await file.length();
      final sizeInMb = sizeInBytes / (1024 * 1024);

      if (sizeInMb > 5) {
        if (mounted) {
          AppToast.show(context, 'Image is too large. Maximum allowed size is 5MB.', type: ToastType.error);
        }
        return;
      }

      // On iOS, TOCropViewController (used by image_cropper) frequently fails to render
      // or presents a black screen overlay on iOS 17+. The captured image is already
      // scaled to 1024x1024 and displayed within a circular avatar, so on iOS we directly
      // use the picked file to avoid black screen and freezing issues.
      if (Platform.isIOS) {
        if (mounted) {
          setState(() {
            _selectedImage = file;
          });
          widget.onPhotoSelected(file);
        }
        return;
      }

      await _cropImage(file);
    } catch (e) {
      if (kDebugMode) debugPrint('[ProfilePhoto] Error picking image: $e');
      if (mounted) {
        AppToast.show(context, 'Unable to open camera/photos. Please check permissions.', type: ToastType.error);
      }
    } finally {
      _awaitingResume = true;
      Future.delayed(const Duration(seconds: 1), _releaseAppLock);
    }
  }

  Future<void> _cropImage(File imageFile) async {
    File finalImage = imageFile;
    try {
      // The iOS side presents its own view controller and answers over a
      // method channel; on iOS 26 with image_cropper 11 it sometimes
      // presented nothing and never answered at all, so this await hung
      // forever and the photo below was never handed on to be uploaded --
      // no crop screen, no error, no upload, nothing. Bound the wait so a
      // silent plugin can only cost the crop, never the photo.
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
            resetAspectRatioEnabled: false,
          ),
        ],
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[ProfilePhoto] Cropper did not answer in 60s — using original image');
          }
          return null;
        },
      );

      if (croppedFile != null) {
        finalImage = File(croppedFile.path);
      } else {
        if (kDebugMode) debugPrint('[ProfilePhoto] Cropper returned null, using original image');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ProfilePhoto] Error cropping image, using original: $e');
      finalImage = imageFile;
    }

    if (mounted) {
      setState(() {
        _selectedImage = finalImage;
      });
      widget.onPhotoSelected(finalImage);
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
              title: Text('Take Photo',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppTheme.arcticBlue),
              title: Text('Choose from Gallery',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.grey),
              title: Text('Cancel',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp, fontWeight: FontWeight.w500)),
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
                  : (_hasPhotoUrl
                      ? NetworkImage(widget.initialPhotoUrl!) as ImageProvider
                      : null),
              child: _selectedImage == null && !_hasPhotoUrl
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

