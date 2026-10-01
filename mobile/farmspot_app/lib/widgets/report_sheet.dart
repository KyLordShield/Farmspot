import 'package:flutter/material.dart';

import '../models/report.dart';
import '../services/report_service.dart';
import '../theme.dart';
import 'app_feedback.dart';

/// Opens the report sheet and files the report the user chose.
///
/// Returns true when a report was filed (or was already on file), false when
/// the user backed out. Callers use the return value only to decide whether to
/// close something; the sheet shows its own confirmation, because a snack bar
/// thrown over a dismissed sheet is the one outcome that reliably gets missed.
Future<bool> showReportSheet(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,

  /// What the user is reporting, e.g. "this listing" or "Ana Reyes". Shown in
  /// the sheet's subtitle so the reason list has context.
  required String subjectName,

  /// Pre-selected reason. The chat screen knows when a long-press is usually
  /// about one specific thing, so it can pass `fraudOrScam` and save a tap.
  ReportReason? initialReason,

  /// Injected for tests; defaults to the real backend.
  ReportsGateway? gateway,
}) async {
  final receipt = await showModalBottomSheet<ReportReceipt>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    // The details field is the point of this sheet, and the keyboard covers
    // the lower half of the screen. Scroll-controlled plus a capped body keeps
    // both the reason list and the submit button reachable above it.
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReportSheet(
      targetType: targetType,
      targetId: targetId,
      subjectName: subjectName,
      initialReason: initialReason,
      gateway: gateway,
    ),
  );

  return receipt != null;
}

/// Reason picker plus optional free-text detail, then a single submit.
///
/// Deliberately *not* a confirm dialog: a report is a statement about someone
/// else, and picking a reason from a list with a visible explanation is what
/// makes it useful to a moderator. "Report" with an instant yes/no would
/// collect accusations with no content behind them.
class ReportSheet extends StatefulWidget {
  final ReportTargetType targetType;
  final String targetId;
  final String subjectName;
  final ReportReason? initialReason;
  final ReportsGateway? gateway;

  const ReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.subjectName,
    this.initialReason,
    this.gateway,
  });

  /// Keys the tests drive. Exposed as statics, matching `HomeFilterButton`.
  static const Key submitButtonKey = Key('report-submit');
  static const Key detailsFieldKey = Key('report-details');
  static const Key titleKey = Key('report-sheet-title');

  /// The scrollable holding the reasons and the details field. Named because a
  /// test has to scroll *this* list to reach a reason near the bottom, and
  /// guessing "the last Scrollable" would break the moment the sheet gained a
  /// second one.
  static const Key bodyListKey = Key('report-body-list');

  /// The failure banner, shown under the details field when a submit is
  /// rejected. Keyed so a test can scroll it into view — it sits at the very
  /// bottom of a scrolling list, so it may not be built yet.
  static const Key errorKey = Key('report-error');

  static Key reasonOptionKey(String code) => Key('report-reason-$code');

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final TextEditingController _details = TextEditingController();

  bool _submitting = false;
  String? _error;

  ReportsGateway get _gateway => widget.gateway ?? ReportService.instance;

  @override
  void initState() {
    super.initState();
    _reason = widget.initialReason;
    // Watch the counter so the submit button greys out the moment the text
    // passes the server's limit, rather than after a round trip returns 422.
    _details.addListener(_onDetailsChanged);
  }

  @override
  void dispose() {
    _details.removeListener(_onDetailsChanged);
    _details.dispose();
    super.dispose();
  }

  void _onDetailsChanged() => setState(() {});

  int get _detailsLength => _details.text.trim().length;

  bool get _canSubmit =>
      _reason != null &&
      _detailsLength <= ReportDraft.maxDetails &&
      !_submitting;

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final receipt = await _gateway.submit(ReportDraft(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: reason,
        details: _details.text,
      ));

      if (!mounted) return;

      // The two success paths get different wording on purpose. A duplicate
      // means the team already has this complaint, and saying "thanks" again
      // would imply a fresh report was opened when none was.
      Navigator.of(context).pop(receipt);
      showFarmSpotSnackBar(
        context,
        receipt.duplicate
            ? 'You already reported this. Our team is reviewing it.'
            : 'Report sent. Our team will review it.',
      );
    } catch (error) {
      if (!mounted) return;
      // Keep the sheet open with the user's text and choices intact: losing a
      // written explanation to a failed upload is the worst thing this flow
      // could do, so they can fix their connection and retry.
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Flexible(child: _buildBody()),
            _buildSubmitRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Report ${widget.targetType.label.toLowerCase()}',
            key: ReportSheet.titleKey,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tell us what is wrong with ${widget.subjectName}. A moderator will review it.',
            style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.3),
          ),
          const SizedBox(height: 4),
          // Reporting is a queue, not an instant ban. Saying so up front is the
          // honest framing, and it also sets the expectation that the listing or
          // message stays visible until someone looks at it.
          const Text(
            'Nothing is hidden automatically.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.mutedGreen,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      key: ReportSheet.bodyListKey,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      children: [
        ...ReportReason.all.map(_buildReasonOption),
        const SizedBox(height: 12),
        _buildDetailsField(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _buildError(),
        ],
      ],
    );
  }

  Widget _buildReasonOption(ReportReason reason) {
    final selected = reason == _reason;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ReportSheet.reasonOptionKey(reason.code),
        onTap: _submitting ? null : () => setState(() => _reason = reason),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryGreen.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryGreen : const Color(0xFFE2E6E2),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.primaryGreen : Colors.black38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reason.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    if (reason.hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        reason.hint!,
                        style: const TextStyle(fontSize: 12, color: Colors.black45, height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsField() {
    final over = _detailsLength > ReportDraft.maxDetails;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Anything else? (optional)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            // A live counter rather than a silent cutoff: the limit is the
            // server's, and a moderator reading "the seller was rude" learns
            // more from a sentence than from a chosen reason alone.
            Text(
              '$_detailsLength / ${ReportDraft.maxDetails}',
              style: TextStyle(
                fontSize: 12,
                color: over ? Colors.red : Colors.black38,
                fontWeight: over ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: ReportSheet.detailsFieldKey,
          controller: _details,
          enabled: !_submitting,
          maxLines: 4,
          minLines: 3,
          maxLength: ReportDraft.maxDetails,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'What happened? Anything that helps a moderator decide.',
            hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E6E2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E6E2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryGreen),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      key: ReportSheet.errorKey,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFB3261E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB3261E), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          key: ReportSheet.submitButtonKey,
          onPressed: _canSubmit ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primaryGreen.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.white70,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'Send report',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
        ),
      ),
    );
  }
}
