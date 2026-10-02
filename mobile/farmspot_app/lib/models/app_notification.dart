/// One row of the notification inbox, as returned by
/// GET /api/notifications and PATCH /api/notifications/{id}/read.
///
/// Named `AppNotification` rather than `Notification` because Flutter's
/// `Notification` (a `Listenable` for the toasts/snackbars) is already taken,
/// and shadowing it in a screen that shows snackbars is a trap.
class AppNotification {
  /// NOTIF_ID, e.g. "NOT001".
  final String id;

  /// Raw NOTIF_TYPE, e.g. "LISTING_EXPIRING_SOON". Kept as the string rather
  /// than an enum because the server owns the taxonomy: an unknown value from a
  /// newer backend must still render a row instead of throwing here. The icon
  /// and tap behaviour are resolved from it in `utils/notification_icons.dart`.
  final String type;

  /// Short headline.
  final String title;

  /// One sentence of plain language.
  final String body;

  /// NOTIF_REF_ID — the record this is about, normally an LST_ID. Null for
  /// events with nothing to open. This is what the app deep-links on.
  final String? refId;

  /// Whether the user has opened it. A real bool from the server, so the UI
  /// can use it directly instead of comparing against 0.
  final bool isRead;

  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.refId,
    this.isRead = false,
    this.createdAt,
  });

  /// Whether there is a [refId] to open at all. The column is nullable, so an
  /// event like a completed setup has nothing to deep-link to.
  bool get hasTarget => refId != null && refId!.trim().isNotEmpty;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      refId: json['ref_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  /// The same row marked read.
  ///
  /// Used to update the list the instant a row is tapped, without waiting for
  /// the round trip — the badge and the row's styling have to change on the
  /// first frame or the tap reads as broken on a slow connection.
  AppNotification asRead() => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    refId: refId,
    isRead: true,
    createdAt: createdAt,
  );
}
