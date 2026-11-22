import 'package:flutter/material.dart';

/// Shared contact details for applicants and people who cannot sign in.
/// Replace the sample details here when the association confirms its contacts.
Future<void> showAssociationContactDialog(
  BuildContext context, {
  bool accountDeactivated = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        accountDeactivated ? 'Account Deactivated' : 'Contact the Association',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              accountDeactivated
                  ? 'Your account has been deactivated. Please contact the association secretary for help.'
                  : 'For help with your farm application or account, contact the association secretary.',
            ),
            const SizedBox(height: 20),
            const Text(
              'Manilyn B. Alferez',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const Text('Association Secretary'),
            const SizedBox(height: 16),
            const Text('Phone', style: TextStyle(color: Colors.black54)),
            const SelectableText('0917 482 6390'),
            const SizedBox(height: 12),
            const Text('Email', style: TextStyle(color: Colors.black54)),
            const SelectableText('manilyn.alferez@example.com'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
