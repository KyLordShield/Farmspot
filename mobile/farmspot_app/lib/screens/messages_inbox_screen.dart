import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/message_service.dart';
import '../theme.dart';
import 'in_app_messages_screen.dart';

/// The signed-in user's message inbox — one row per thread, newest activity
/// first. Shared by both roles: the API decides whether a row is a thread the
/// user is buying in on or selling in, and the row says which.
class MessagesInboxScreen extends StatefulWidget {
  final VoidCallback? onBack;

  /// Injectable for tests; the real HTTP-backed service is used when omitted.
  final MessagesGateway? gateway;

  const MessagesInboxScreen({super.key, this.onBack, this.gateway});

  @override
  State<MessagesInboxScreen> createState() => _MessagesInboxScreenState();
}

class _MessagesInboxScreenState extends State<MessagesInboxScreen> {
  List<Conversation> _threads = [];
  bool _loading = true;
  String? _error;

  MessagesGateway get _api => widget.gateway ?? MessageService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final threads = await _api.fetchConversations();
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _open(Conversation thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InAppMessagesScreen(
          conversation: thread,
          gateway: widget.gateway,
        ),
      ),
    );
    // Coming back from a thread, its unread badge is stale — refresh.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Messages',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }
    if (_error != null) {
      return _Message(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load messages",
        subtitle: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (_threads.isEmpty) {
      return const _Message(
        icon: Icons.chat_bubble_outline,
        title: 'No messages yet',
        subtitle:
            'Start a conversation from any crop and it will show up here — '
            'as a buyer, a seller, or both.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _threads.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          thickness: 1,
          indent: 84,
          color: Color(0xFFEEF1EC),
        ),
        itemBuilder: (context, i) => _ThreadRow(
          thread: _threads[i],
          onTap: () => _open(_threads[i]),
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  final Conversation thread;
  final VoidCallback onTap;

  const _ThreadRow({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final green = AppColors.primaryGreen;
    final unread = thread.unreadCount;
    final who = thread.otherPartyName?.trim();
    final name = (who == null || who.isEmpty)
        ? (thread.isSellerSide ? 'Buyer' : 'Seller')
        : who;
    final initial =
        name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Listing thumbnail, falling back to the farm's initial.
            _avatar(thread, initial),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 15,
                            fontWeight:
                                unread > 0 ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _when(thread.lastMessageAt),
                        style: const TextStyle(
                            color: Colors.black38, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    thread.cropName == null
                        ? 'Conversation'
                        : 'About ${thread.cropName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.mutedGreen, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.lastMessage ?? 'No messages yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread > 0 ? Colors.black87 : Colors.black54,
                            fontSize: 13,
                            fontWeight: unread > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              unread > 99 ? '99+' : '$unread',                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The listing photo when there is one, otherwise a green circle with the
  /// counterparty's initial — the same treatment the chat header uses.
  Widget _avatar(Conversation thread, String initial) {
    final photo = thread.cropImage;
    if (photo != null && photo.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          photo,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialBubble(initial),
        ),
      );
    }
    return _initialBubble(initial);
  }

  Widget _initialBubble(String initial) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  /// "now" / "5m" / "3h" / "Mon" / "12 Mar" — inbox-scale, so a full timestamp
  /// is only worth the space for older messages.
  static String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return _days[at.weekday - 1];
    return '${at.day} ${_months[at.month - 1]}';
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

/// Full-screen empty / error state shared by the inbox.
class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.searchBackground,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 30, color: AppColors.mutedGreen),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(color: AppColors.primaryGreen),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
