import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String address;
  final String phone;
  final String photoUrl;

  const EditProfileScreen({
    super.key,
    this.firstName = '',
    this.lastName = '',
    this.address = '',
    this.phone = '',
    this.photoUrl = '',
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _picker = ImagePicker();

  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _addressCtrl;

  // Newly-picked photo (previewed locally, uploaded on Save). Bytes are read
  // once at pick time so the avatar preview doesn't re-read the file each
  // rebuild (same memory pattern the add-crop preview uses).
  XFile? _newPhoto;
  Uint8List? _newBytes;

  bool _isSaving = false;
  String? _saveError;

  String get _currentName => '${widget.firstName} ${widget.lastName}'.trim();

  @override
  void initState() {
    super.initState();
    _lastNameCtrl = TextEditingController(text: widget.lastName);
    _firstNameCtrl = TextEditingController(text: widget.firstName);
    _mobileCtrl = TextEditingController(text: widget.phone);
    _addressCtrl = TextEditingController(text: widget.address);
  }

  @override
  void dispose() {
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo Library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() {
      _newPhoto = picked;
      _newBytes = bytes;
      _saveError = null;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    final mobile = _mobileCtrl.text.trim();
    final address = _addressCtrl.text.trim();

    final nameChanged = _currentName != '$first $last'.trim();
    final mobileChanged = mobile != widget.phone.trim();
    final addressChanged = address != widget.address.trim();

    // Nothing changed (and nothing to upload) — just close, nothing to save.
    if (!nameChanged && !mobileChanged && !addressChanged && _newPhoto == null) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    // Only the fields that actually changed are sent; untouched ones are left
    // alone on the server (matches AuthService.updateProfile's contract).
    if (nameChanged || mobileChanged || addressChanged) {
      final result = await AuthService.updateProfile(
        name: nameChanged ? '$first $last'.trim() : null,
        mobileNumber: mobileChanged ? mobile : null,
        address: addressChanged ? address : null,
      );

      if (!mounted) return;
      if (result.error != null) {
        setState(() {
          _isSaving = false;
          _saveError = result.error;
        });
        return;
      }
    }

    if (_newPhoto != null) {
      final result = await AuthService.uploadProfilePhoto(_newPhoto!);

      if (!mounted) return;
      if (result.error != null) {
        setState(() {
          _isSaving = false;
          _saveError = result.error;
        });
        return;
      }
    }

    if (!mounted) return;
    // Successful save — pop true so ProfileScreen re-pulls the authoritative
    // user (name/address/phone/photo all refreshed in one fetch).
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    _buildAvatar(),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const CircleAvatar(
                            radius: 10,
                            backgroundColor: AppColors.primaryGreen,
                            child: Icon(Icons.camera_alt, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _pickPhoto,
                  child: const Text(
                    'Change Photo',
                    style: TextStyle(color: AppColors.primaryGreen, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field('Lastname', _lastNameCtrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field('FirstName', _firstNameCtrl),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _field('mobile number', _mobileCtrl, keyboardType: TextInputType.phone),
          const SizedBox(height: 14),
          _field('address', _addressCtrl),
          if (_saveError != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _saveError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Avatar preview: a newly picked photo wins over the existing server photo,
  /// which in turn wins over the initials fallback.
  Widget _buildAvatar() {
    final initial = widget.firstName.isNotEmpty
        ? widget.firstName[0].toUpperCase()
        : '?';

    if (_newBytes != null) {
      return CircleAvatar(
        radius: 34,
        backgroundColor: AppColors.primaryGreen,
        backgroundImage: MemoryImage(_newBytes!),
      );
    }

    if (widget.photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 34,
        backgroundColor: AppColors.primaryGreen,
        backgroundImage: ResizeImage(NetworkImage(widget.photoUrl), width: 160),
      );
    }

    return CircleAvatar(
      radius: 34,
      backgroundColor: AppColors.primaryGreen,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryGreen),
        ),
      ),
    );
  }
}