import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/message_service.dart';
import '../theme.dart';

/// In-app buyer <-> seller chat.
///
/// The thread is real: history comes from the server and the screen re-reads
/// it every [pollInterval] while it is open, so a reply on the other device
/// appears without a manual refresh. Sending posts to the server and renders
/// the stored row, so what you see is what was actually saved.
///
/// The same screen serves both roles — the server marks each message `is_mine`
/// against the caller's own USR_ID, so the bubble layout needs no role input.
class InAppMessagesScreen extends StatefulWidget {
  final Conversation conversation;

  /// Injectable for tests; the real HTTP-backed service is used when omitted.
  final MessagesGateway? gateway;

  const InAppMessagesScreen({
    super.key,
    required this.conversation,
    this.gateway,
  });

  @override
  State<InAppMessagesScreen> createState() => _InAppMessagesScreenState();
}

class _InAppMessagesScreenState extends State<InAppMessagesScreen> {
  /// How often to ask the server for anything new while the chat is open.
  static const Duration pollInterval = Duration(seconds: 4);

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<ChatMessage> _messages = [];
  Timer? _poll;

  bool _loading = true;
  bool _sending = false;
  String? _error;
  bool _atBottom = true;

  MessagesGateway get _api => widget.gateway ?? MessageService.instance;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 80;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  Future<void> _load() async {
    try {
      final messages = await _api.fetchMessages(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _loading = false;
        _error = null;
      });
      _scrollToEnd(jump: true);
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (_) => _pollOnce());
  }

  /// Asks only for messages newer than the last one held, so an idle chat
  /// costs one small indexed query. A failed poll is deliberately silent: the
  /// thread is still on screen and the next tick will catch up.
  Future<void> _pollOnce() async {
    if (!mounted) return;
    final lastId = _messages.isEmpty ? null : _messages.last.id;
    try {
      final fresh = await _api.fetchMessages(widget.conversation.id,
          after: lastId);
      if (!mounted || fresh.isEmpty) return;
      setState(() => _messages.addAll(fresh));
      if (_atBottom) _scrollToEnd();
    } catch (_) {
      // Offline or server hiccup — retry on the next tick.
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final saved = await _api.sendMessage(widget.conversation.id, text);
      if (!mounted) return;
      // Render the server's copy (real id and timestamp) instead of a local
      // guess, so the next poll's `after` cursor lines up with the database.
      setState(() {
        _messages.add(saved);
        _input.clear();
        _sending = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorTerracotta,
        ),
      );
    }
  }

  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (jump) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final green = AppColors.primaryGreen;
    final muted = AppColors.mutedGreen;
    final bg = AppColors.searchBackground;
    final thread = widget.conversation;
    final who = thread.otherPartyName?.trim();
    final name = (who == null || who.isEmpty)
        ? (thread.isSellerSide ? 'Buyer' : 'Seller')
        : who;
    final initial = name.characters.first.toUpperCase();

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header: back arrow, counterparty, and the In-app badge.
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 2),
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: green,
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          // Honest presence: the server does not track online
                          // status, so say what is actually true.
                          thread.farmName == null
                              ? 'In-app conversation'
                              : thread.farmName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.infoSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 12, color: AppColors.infoSage),
                        SizedBox(width: 4),
                        Text('In-app',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.infoSage,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Context pill: which crop this thread is about.
            if (thread.cropName != null || thread.barangay != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE3E8E1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_basket_outlined,
                        size: 14, color: AppColors.primaryGreen),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text('About: ${thread.cropName ?? 'this crop'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ),
                    if (thread.barangay != null &&
                        thread.barangay!.isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                            color: AppColors.mutedGreen, shape: BoxShape.circle),
                      ),
                      Flexible(
                        child: Text(thread.barangay!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Expanded(child: _buildThread(green, muted)),
            _buildInput(green, bg),
          ],
        ),
      ),
    );
  }

  Widget _buildThread(Color green, Color muted) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 34, color: AppColors.mutedGreen),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _load,
                child: const Text('Try again',
                    style: TextStyle(color: AppColors.primaryGreen)),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 32, color: green.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                widget.conversation.isSellerSide
                    ? 'No messages yet. Ask the buyer about the crop.'
                    : 'No messages yet. Send the seller a question.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final message = _messages[i];
        final previous = i == 0 ? null : _messages[i - 1];
        // A day divider when the date changes, so a long thread stays readable.
        final showDate = previous == null ||
            !_sameDay(previous.createdAt, message.createdAt);
        return Column(
          children: [
            if (showDate) _DayDivider(at: message.createdAt),
            _MessageBubble(
              text: message.content,
              isMine: message.isMine,
              time: _timeLabel(message.createdAt),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInput(Color green, Color bg) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_sending,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(color: Colors.black38),
                filled: true,
                fillColor: bg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _sending ? green.withValues(alpha: 0.5) : green,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sending ? null : _send,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.send_rounded, size: 20, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _timeLabel(DateTime at) {
    final t = at.toLocal();
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$hour:${t.minute.toString().padLeft(2, '0')} '
        '${t.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// "Today" / "Yesterday" / "12 Mar" separator.
class _DayDivider extends StatelessWidget {
  final DateTime at;

  const _DayDivider({required this.at});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final label = diff == 0
        ? 'Today'
        : diff == 1
            ? 'Yesterday'
            : '${at.day} ${months[at.month - 1]}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.mutedGreen,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A single chat bubble: mine on the right in green, theirs on the left in
/// white, each with a small timestamp.
class _MessageBubble extends StatelessWidget {
  final String text;
  final bool isMine;
  final String time;

  const _MessageBubble({
    required this.text,
    required this.isMine,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final green = AppColors.primaryGreen;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: isMine ? green : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              boxShadow: isMine
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x11000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isMine ? Colors.white : Colors.black87,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(time,
                style: const TextStyle(color: Colors.black38, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
