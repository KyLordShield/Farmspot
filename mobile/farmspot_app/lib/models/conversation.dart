/// A buyer <-> seller thread, as returned by GET /api/conversations and
/// POST /api/conversations.
///
/// A thread is always about one listing, so the crop/farm context needed by the
/// inbox row and the chat header travels with it.
class Conversation {
  final String id;
  final String listingId;

  /// The farm being discussed, and where it is.
  final String? farmName;
  final String? barangay;

  /// Whoever is on the other side of the chat: the seller for a buyer, the
  /// buyer for a seller.
  final String? otherPartyName;
  final String? otherPartyPhoto;

  /// The crop this thread is about.
  final String? cropName;
  final String? cropImage;

  final String? lastMessage;
  final DateTime? lastMessageAt;

  /// Messages from the other side that have not been opened yet.
  final int unreadCount;

  /// 'BUYER' or 'SELLER' — which side of this thread the signed-in user is on.
  final String myRole;

  const Conversation({
    required this.id,
    required this.listingId,
    this.farmName,
    this.barangay,
    this.otherPartyName,
    this.otherPartyPhoto,
    this.cropName,
    this.cropImage,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.myRole = 'BUYER',
  });

  bool get isSellerSide => myRole == 'SELLER';

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
      farmName: farm?['name'] as String?,
      barangay: farm?['barangay'] as String?,
      otherPartyName: other?['name'] as String?,
      otherPartyPhoto: other?['photo'] as String?,
      cropName: (cropIcon != null && cropIcon.isNotEmpty) ? cropIcon : categoryName,
      cropImage: listing?['image'] as String?,
      lastMessage: json['last_message'] as String?,
      lastMessageAt: _parseDate(json['last_message_at']),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      myRole: json['my_role'] as String? ?? 'BUYER',
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

/// A single chat message. `isMine` is resolved by the server against the
/// caller's own USR_ID, so the same bubble layout renders correctly for the
/// buyer and the seller without either side knowing its role.
class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final bool isMine;
  final bool isRead;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
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
      isMine: json['is_mine'] as bool? ?? false,
      isRead: json['is_read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
