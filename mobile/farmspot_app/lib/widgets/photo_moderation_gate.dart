import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/photo_moderation.dart';

/// Modal screening prevents saving/navigating while selected photos are checked.
Future<List<XFile>> screenPhotos(
  BuildContext context,
  List<XFile> photos, {
  Future<bool> Function(XFile)? check,
  Future<PhotoModerationResult> Function(XFile) inspect =
      PhotoModeration.inspect,
  bool showDebugResults = true,
}) async {
  if (photos.isEmpty || !context.mounted) return [];
  final accepted = <XFile>[];
  var blocked = 0;
  var failed = 0;
  final debugResults = kDebugMode && showDebugResults
      ? <_PhotoCheckDebug>[]
      : null;
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
      final timer = Stopwatch()..start();
      try {
        final result = check == null ? await inspect(photo) : null;
        final allowed = result?.allowed ?? await check!(photo);
        debugResults?.add(
          _PhotoCheckDebug(
            number: progress.value + 1,
            score: result?.score,
            allowed: allowed,
            elapsedMs: result?.elapsedMilliseconds ?? timer.elapsedMilliseconds,
          ),
        );
        if (allowed) {
          accepted.add(photo);
        } else {
          blocked++;
        }
      } catch (_) {
        failed++;
        debugResults?.add(
          _PhotoCheckDebug(
            number: progress.value + 1,
            allowed: false,
            elapsedMs: timer.elapsedMilliseconds,
            failed: true,
          ),
        );
      } finally {
        timer.stop();
      }
      progress.value++;
    }
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    // The route can finish its disposal on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => progress.dispose());
  }
  if (!context.mounted) return [];
  if (kDebugMode && debugResults != null) {
    await _showDebugResults(context, debugResults);
    if (!context.mounted) return [];
  }
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

class _PhotoCheckDebug {
  final int number;
  final double? score;
  final bool allowed;
  final int elapsedMs;
  final bool failed;

  const _PhotoCheckDebug({
    required this.number,
    this.score,
    required this.allowed,
    required this.elapsedMs,
    this.failed = false,
  });

  String get decision => failed
      ? 'CHECK FAILED — BLOCKED'
      : allowed
      ? 'ALLOWED'
      : 'BLOCKED';
  String get scoreText => score?.toStringAsFixed(4) ?? 'unavailable';
  String get summary =>
      'Photo $number: score=$scoreText '
      'threshold=${PhotoModeration.blockThreshold} '
      'decision=$decision elapsedMs=$elapsedMs';
}

Future<void> _showDebugResults(
  BuildContext context,
  List<_PhotoCheckDebug> results,
) async {
  var copied = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Photo check results (debug)'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Block at ${PhotoModeration.blockThreshold.toStringAsFixed(2)} or above.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Photos are numbered in selection order. '
              'Scores are model outputs, not a guarantee of safety.',
            ),
            for (final result in results) ...[
              const Divider(height: 24),
              Text(
                'Photo ${result.number} — ${result.decision}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(
                'Score: ${result.scoreText}\n'
                'Check time: ${result.elapsedMs} ms',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: results.map((result) => result.summary).join('\n'),
                ),
              );
              if (dialogContext.mounted) setDialogState(() => copied = true);
            },
            child: Text(copied ? 'Copied' : 'Copy results'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}
