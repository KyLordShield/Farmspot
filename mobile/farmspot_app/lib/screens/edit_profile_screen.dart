import 'package:flutter/material.dart';
import '../theme.dart';

class EditProfileScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String address;
  final String phone;

  const EditProfileScreen({
    super.key,
    this.firstName = '',
    this.lastName = '',
    this.address = '',
    this.phone = '',
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _languageCtrl;

  @override
  void initState() {
    super.initState();
    _lastNameCtrl = TextEditingController(text: widget.lastName);
    _firstNameCtrl = TextEditingController(text: widget.firstName);
    _usernameCtrl = TextEditingController();
    _mobileCtrl = TextEditingController(text: widget.phone);
    _addressCtrl = TextEditingController(text: widget.address);
    _passwordCtrl = TextEditingController();
    _languageCtrl = TextEditingController(text: 'English');
  }

  @override
  void dispose() {
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _usernameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _passwordCtrl.dispose();
    _languageCtrl.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop({
      'firstName': _firstNameCtrl.text.trim().isEmpty
          ? widget.firstName
          : _firstNameCtrl.text.trim(),
      'lastName': _lastNameCtrl.text.trim().isEmpty
          ? widget.lastName
          : _lastNameCtrl.text.trim(),
      'address': _addressCtrl.text.trim().isEmpty
          ? widget.address
          : _addressCtrl.text.trim(),
      'phone': _mobileCtrl.text.trim().isEmpty
          ? widget.phone
          : _mobileCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.firstName.isNotEmpty
        ? widget.firstName[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
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
                    CircleAvatar(
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
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const CircleAvatar(
                          radius: 8,
                          backgroundColor: Colors.green,
                          child: Icon(Icons.circle, size: 0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    // Placeholder — wire up image picker later.
                  },
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
          _field('user name', _usernameCtrl),
          const SizedBox(height: 14),
          _field('mobile number', _mobileCtrl, keyboardType: TextInputType.phone),
          const SizedBox(height: 14),
          _field('address', _addressCtrl),
          const SizedBox(height: 14),
          _field('password', _passwordCtrl, obscure: true),
          const SizedBox(height: 14),
          _field('Language', _languageCtrl),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
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
