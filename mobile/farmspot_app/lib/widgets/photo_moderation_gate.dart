import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../services/photo_moderation.dart';

/// Modal screening prevents saving/navigating while selected photos are checked.
Future<List<XFile>> screenPhotos(
  BuildContext context,
  List<XFile> photos, {
  Future<bool> Function(XFile) check = PhotoModeration.isAllowed,
}) async {
  if (photos.isEmpty || !context.mounted) return [];
  final accepted = <XFile>[];
  var blocked = 0;
  var failed = 0;
  final progress = ValueNotifier<int>(0);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, count, _) => Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text('Checking photos… $count/${photos.length}')),
            ],
          ),
        ),
      ),
    ),
  );
  final navigator = Navigator.of(context, rootNavigator: true);
  navigator.push(route);
  try {
    // Sequential checks cap peak memory and keep inference off the UI isolate.
    for (final photo in photos) {
      try {
        if (await check(photo)) {
          accepted.add(photo);
        } else {
          blocked++;
        }
      } catch (_) {
        failed++;
      }
      progress.value++;
    }
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    // The route can finish its disposal on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => progress.dispose());
  }
  if (!context.mounted) return [];
  if (blocked > 0 || failed > 0) {
    final message = [
      if (blocked > 0)
        '$blocked photo(s) may contain adult content and were not added.',
      if (failed > 0)
        '$failed photo(s) could not be checked. Try another JPEG or PNG photo.',
    ].join(' ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
  return accepted;
}
