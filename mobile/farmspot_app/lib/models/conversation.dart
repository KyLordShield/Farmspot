import 'report.dart';

/// A buyer <-> seller thread, as returned by GET /api/conversations and
/// POST /api/conversations.
///
/// A thread is always about one listing, so the crop/farm context needed by the
/// inbox row and the chat header travels with it.
class Conversation {
  final String id;
  final String listingId;

  /// The farm being discussed, and where it is.
  final String? farmId;
  final String? farmName;
  final String? barangay;

  /// Whoever is on the other side of the chat: the seller for a buyer, the
  /// buyer for a seller.
  final String? otherPartyName;
  final String? otherPartyPhoto;

  /// USR_ID of [otherPartyName]. Needed to report the person behind the
  /// conversation; a name alone cannot be reported against.
  final String? otherPartyId;

  /// FMR_ID of the seller's farmer record on this thread, whichever side of
  /// the thread the viewer is on. This is the id for a report against the
  /// *seller* as a farmer, as opposed to against their user account.
  final String? sellerFarmerId;

  /// The crop this thread is about.
  final String? cropName;
  final String? cropImage;

  final String? lastMessage;
  final DateTime? lastMessageAt;

  /// Messages from the other side that have not been opened yet.
  final int unreadCount;

  /// 'BUYER' or 'SELLER' — which side of this thread the signed-in user is on.
  final String myRole;
  final String? otherPartyStatus;

  const Conversation({
    required this.id,
    required this.listingId,
    this.farmId,
    this.farmName,
    this.barangay,
    this.otherPartyName,
    this.otherPartyPhoto,
    this.otherPartyId,
    this.sellerFarmerId,
    this.cropName,
    this.cropImage,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.myRole = 'BUYER',
    this.otherPartyStatus,
  });

  bool get isSellerSide => myRole == 'SELLER';
  bool get otherPartyIsActive => otherPartyStatus == 'ACTIVE';

  /// The report target for the other person in this thread, or null when the
  /// server did not send a usable id.
  ///
  /// The two sides are not symmetric, and this is the one place that has to
  /// know it. A buyer reporting a seller can accuse either the *account*
  /// (USR_ID) or the *farmer* (FMR_ID) — a seller who is a scammer is a
  /// different report from a seller account being compromised — so the farmer
  /// id is preferred when it exists, because it is the accusation that a
  /// moderator can act on for the person's whole selling history.
  ///
  /// A seller reporting a buyer has no such choice: a buyer has no farmer
  /// record, so it is always the account.
  CounterpartyReportTarget? get counterpartyReportTarget {
    final userId = (otherPartyId ?? '').trim();
    final name = (otherPartyName ?? '').trim().isNotEmpty
        ? otherPartyName!.trim()
        : (isSellerSide ? 'this buyer' : 'this seller');

    if (!isSellerSide) {
      final farmerId = (sellerFarmerId ?? '').trim();
      if (farmerId.isNotEmpty) {
        return CounterpartyReportTarget(
          type: ReportTargetType.farmer,
          id: farmerId,
          name: name,
        );
      }
    }

    if (userId.isEmpty) return null;

    return CounterpartyReportTarget(
      type: ReportTargetType.user,
      id: userId,
      name: name,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] as Map?;
    final farm = json['farm'] as Map?;
    final other = json['other_party'] as Map?;

    // The server sends the same listing contract as the feed, so the crop name
    // is derived the same way: the seller-typed name wins over the category.
    final cropIcon = (listing?['crop_icon'] as String?)?.trim();
    final categoryName = (listing?['category'] as Map?)?['name'] as String?;

    return Conversation(
      id: json['id'] as String,
      listingId: (json['listing_id'] ?? listing?['id']) as String? ?? '',
      farmId: (farm?['id'] ?? json['farm_id']) as String?,
      farmName: farm?['name'] as String?,
      barangay: farm?['barangay'] as String?,
      otherPartyName: other?['name'] as String?,
      otherPartyPhoto: other?['photo'] as String?,
      otherPartyId: other?['id'] as String?,
      sellerFarmerId: json['seller_farmer_id'] as String?,
      cropName: (cropIcon != null && cropIcon.isNotEmpty) ? cropIcon : categoryName,
      cropImage: listing?['image'] as String?,
      lastMessage: json['last_message'] as String?,
      lastMessageAt: _parseDate(json['last_message_at']),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      myRole: json['my_role'] as String? ?? 'BUYER',
      otherPartyStatus: other?['status'] as String?,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

/// A resolved "who is being reported" for the other side of a conversation.
class CounterpartyReportTarget {
  final ReportTargetType type;
  final String id;
  final String name;

  const CounterpartyReportTarget({
    required this.type,
    required this.id,
    required this.name,
  });
}

/// A single chat message. `isMine` is resolved by the server against the
/// caller's own USR_ID, so the same bubble layout renders correctly for the
/// buyer and the seller without either side knowing its role.
class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;

  /// Cloudinary URL of the photo this message carries, null for text.
  final String? imageUrl;

  /// The pin a seller shared, when this is a location message. Both are set
  /// together or not at all, so [hasLocation] is the single check the UI needs.
  final double? latitude;
  final double? longitude;
  final String? locationLabel;

  /// The farm behind a shared location. When present the recipient opens the
  /// same directions screen a listing's Directions button does; the label is
  /// normally the farm's name.
  final String? farmId;

  final bool isMine;
  final bool isRead;
  final DateTime createdAt;

  /// True when this is a photo message (with or without a caption).
  bool get hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;

  /// True when this message carries a tappable map pin.
  bool get hasLocation => latitude != null && longitude != null;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.farmId,
    required this.isMine,
    required this.isRead,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationLabel: json['location_label'] as String?,
      farmId: json['farm_id'] as String?,
      isMine: json['is_mine'] as bool? ?? false,
      isRead: json['is_read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
