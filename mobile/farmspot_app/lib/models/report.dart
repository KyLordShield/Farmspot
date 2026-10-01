/// What a report is about.
///
/// The wire codes are fixed by the backend enum and must not be renamed; the
/// Dart names are the app's own wording so a screen can say "Report message"
/// without a string switch at every call site.
enum ReportTargetType {
  listing('LISTING', 'Crop listing'),
  message('MESSAGE', 'Chat message'),
  farmer('FARMER', 'Farmer'),
  user('USER', 'User account');

  const ReportTargetType(this.code, this.label);

  final String code;

  /// Noun phrase for a sentence like "Report this listing" or a sheet title.
  final String label;

  static ReportTargetType? fromCode(String? code) {
    for (final type in ReportTargetType.values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// One reason a user can pick, matching the backend's `RPT_REASON_CODE` enum.
///
/// A class rather than a bare enum so each option can carry a one-line [hint]
/// explaining what the moderator will do with it. People report "scam" to mean
/// wildly different things; the hint is what makes the choice mean something.
class ReportReason {
  final String code;
  final String label;
  final String? hint;

  const ReportReason(this.code, this.label, {this.hint});

  static const misleadingInfo = ReportReason(
    'MISLEADING_INFO',
    'Misleading or false information',
    hint: 'The crop, price or photos do not match reality',
  );
  static const fakeListing = ReportReason(
    'FAKE_LISTING',
    'Item is not real or not available',
    hint: 'Listed but the seller does not actually have it',
  );
  static const harassment = ReportReason(
    'HARASSMENT',
    'Harassment or bullying',
    hint: 'Abusive, threatening or demeaning behaviour',
  );
  static const inappropriateContent = ReportReason(
    'INAPPROPRIATE_CONTENT',
    'Inappropriate or offensive content',
    hint: 'Content a buyer should not be exposed to',
  );
  static const fraudOrScam = ReportReason(
    'FRAUD_OR_SCAM',
    'Fraud, scam or asking for money',
    hint: 'Includes moving the deal off-platform or asking for payment upfront',
  );
  static const spam = ReportReason(
    'SPAM',
    'Spam or repeated messages',
    hint: 'Repeated or unwanted contact',
  );
  static const unsafeBehavior = ReportReason(
    'UNSAFE_BEHAVIOR',
    'Unsafe or off-platform behaviour',
    hint: 'Pressuring you to meet somewhere unsafe or go off-platform',
  );
  static const other = ReportReason('OTHER', 'Something else');

  /// The order shown in the sheet. Ordered from specific to catch-all so
  /// "Something else" is a deliberate last resort, not the first thing anyone
  /// reaches for by accident.
  static const List<ReportReason> all = [
    fraudOrScam,
    fakeListing,
    misleadingInfo,
    harassment,
    inappropriateContent,
    unsafeBehavior,
    spam,
    other,
  ];

  static ReportReason? fromCode(String? code) {
    for (final reason in ReportReason.all) {
      if (reason.code == code) return reason;
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is ReportReason && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Everything needed to file one report, gathered by the sheet before it calls
/// the API.
///
/// Kept as a value object so a screen can hold a draft across sheet open/close
/// and a test can assert on the exact payload without touching the network.
class ReportDraft {
  final ReportTargetType targetType;
  final String targetId;
  final ReportReason reason;
  final String details;

  const ReportDraft({
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.details = '',
  });

  /// The POST /api/reports body.
  ///
  /// `details` is sent as an empty string rather than omitted when blank: the
  /// server treats both the same, and a stable shape keeps the request
  /// assertable in tests.
  Map<String, dynamic> toJson() => {
        'target_type': targetType.code,
        'target_id': targetId,
        'reason': reason.code,
        'details': details.trim(),
      };

  /// Details longer than this are refused by the server with a 422, so the
  /// sheet's counter blocks the submit button instead of letting the user type
  /// into a guaranteed failure.
  static const int maxDetails = 1000;

  bool get detailsTooLong => details.trim().length > maxDetails;

  /// Whether the sheet should enable its submit button.
  ///
  /// A target id is required, and it must be a real 6-character id: the server
  /// validates `size:6` and would reject anything else, which is how a
  /// half-populated listing id from a failed request surfaces as a confusing
  /// validation error rather than a crash.
  bool get canSubmit => targetId.trim().isNotEmpty && !detailsTooLong;
}

/// The server's answer to a filed report.
///
/// [duplicate] distinguishes the two success paths, which both mean "we have
/// it" but deserve different wording: a fresh report gets a thank-you, while a
/// repeat should tell the user their earlier report is already with the team
/// rather than implying a new one was just opened.
class ReportReceipt {
  final String id;
  final String? status;
  final DateTime? createdAt;
  final bool duplicate;

  const ReportReceipt({
    required this.id,
    this.status,
    this.createdAt,
    this.duplicate = false,
  });

  factory ReportReceipt.fromJson(Map<String, dynamic> json,
      {required bool duplicate}) {
    return ReportReceipt(
      id: _text(json['id']) ?? '',
      status: _text(json['status']),
      createdAt: DateTime.tryParse(_text(json['created_at']) ?? ''),
      duplicate: duplicate,
    );
  }

  /// Reads a field the API may send as a JSON string or as a number.
  ///
  /// `report.RPT_ID` is the one auto-increment id in this schema — every other
  /// id is char(6) — so it arrives as a number while the rest of this API uses
  /// strings. A plain `as String` cast turned that into a
  /// "type 'int' is not a subtype of type 'String'" crash *after* the report
  /// had already been written, so the sheet showed a failure for a report that
  /// was sitting safely in the moderator's queue and a retry hit the duplicate
  /// path and failed the same way. Never worth crashing over an id.
  static String? _text(Object? value) {
    if (value == null) return null;
    return value is String ? value : value.toString();
  }
}
