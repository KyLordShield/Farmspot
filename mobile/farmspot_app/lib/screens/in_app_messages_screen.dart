import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';

/// In-app buyer ↔ seller chat — UI only for now (no backend). The seller's
/// short greeting in [_seedMessages] stands in for the real conversation until
/// the messaging service is wired up; messages the buyer types are echoed
/// locally so the layout can be reviewed end to end.
class InAppMessagesScreen extends StatefulWidget {
  final CropListing listing;
  const InAppMessagesScreen({super.key, required this.listing});

  @override
  State<InAppMessagesScreen> createState() => _InAppMessagesScreenState();
}

class _InAppMessagesScreenState extends State<InAppMessagesScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<(String, bool, String)> _messages = []; // (text, isMine, time)

  @override
  void initState() {
    super.initState();
    _seedMessages();
  }

  void _seedMessages() {
    final farm = widget.listing.farmName;
    final crop = widget.listing.cropName;
    _messages.add((
      'Kumusta! Thanks for checking out our $crop. We usually harvest on '
      'Weekends and can set aside a batch for you.',
      false,
      _now(),
    ));
    _messages.add((
      'Can I pick it up tomorrow morning? I can go to $farm.',
      true,
      _now(),
    ));
    _messages.add((
      'Oo, po! 8–10 AM works best. I\'ll message you the exact pickup spot '
      'at the farm.',
      false,
      _now(),
    ));
  }

  static String _now() {
    final t = DateTime.now();
    return '${t.hour % 12 == 0 ? 12 : t.hour % 12}:'
        '${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _messages.add((text, true, _now())));
    _input.clear();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
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
    final farm = widget.listing.farmName;
    final initial = farm.trim().isEmpty ? 'F' : farm.trim().characters.first;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header: back arrow, seller avatar, name + online status.
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
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.lightGreen, width: 2),
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(farm,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: AppColors.primaryGreen,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text('online · replies fast',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(color: muted, fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // In-app chat badge so buyers know messages stay inside the app.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.infoSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 12, color: AppColors.infoSage),
                        const SizedBox(width: 4),
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
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    child: Text('About: ${widget.listing.cropName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                        color: AppColors.mutedGreen, shape: BoxShape.circle),
                  ),
                  Flexible(
                    child: Text(widget.listing.barangay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Conversation list.
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final (text, isMine, time) = _messages[i];
                  return _MessageBubble(
                      text: text, isMine: isMine, time: time);
                },
              ),
            ),
            // Input bar: rounded pill + green send.
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                  12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: const TextStyle(color: Colors.black38),
                        filled: true,
                        fillColor: bg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: green,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _send,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.send_rounded,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single chat bubble: seller (left, white) vs buyer (right, green) with a
/// small timestamp below the bubble.
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