import 'package:flutter/material.dart';
import '../theme.dart';

/// FarmSpot AI chat assistant — UI only (no backend). Messages echo locally.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key, this.initialTopic = 'Cabbage Inquiry'});
  final String initialTopic;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<(String, bool)> _messages = []; // (text, isAssistant)
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _messages.add((
      'Kumusta! I\'m FarmSpot ai assist. Ask me anything about your crops, '
      'weather, or local market prices.',
      true,
    ));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add((text, false));
      _typing = true;
    });
    _input.clear();
    _scrollToEnd();
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _typing = false;
      final short = text.length > 42 ? '${text.substring(0, 42)}…' : text;
      _messages.add((
        'Got it — "$short". The ai assist service isn\'t wired up yet, so this '
        'is just a preview of the chat UI. It will answer for real once the '
        'backend lands.',
        true,
      ));
    });
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

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header: back arrow, green AI avatar, lowercase "ai assist".
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
                    decoration: const BoxDecoration(
                      color: AppColors.primaryGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('AI',
                          style: TextStyle(
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
                        const Text('ai assist',
                            style: TextStyle(
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
                            Text('online',
                                style: TextStyle(
                                    color: muted, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Context pill: "Via Farmspot • <topic>".
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.storefront_outlined,
                      size: 14, color: AppColors.primaryGreen),
                  const SizedBox(width: 5),
                  Text('Via Farmspot',
                      style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                        color: AppColors.mutedGreen, shape: BoxShape.circle),
                  ),
                  Text(widget.initialTopic,
                      style: TextStyle(color: muted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Conversation list.
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: _messages.length + (_typing ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _messages.length) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: _Bubble(dots: true, isAssistant: true),
                      ),
                    );
                  }
                  final (text, isAssistant) = _messages[i];
                  return _Bubble(text: text, isAssistant: isAssistant);
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
                            color: Colors.white, size: 22),
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

/// Rounded chat bubble. Assistant = white (left), user = green (right).
/// `dots: true` renders the three-dot "typing" indicator instead of text.
class _Bubble extends StatelessWidget {
  const _Bubble({this.text, required this.isAssistant, this.dots = false});
  final String? text;
  final bool isAssistant;
  final bool dots;

  @override
  Widget build(BuildContext context) {
    final green = AppColors.primaryGreen;
    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isAssistant ? Colors.white : green,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isAssistant ? 4 : 16),
            bottomRight: Radius.circular(isAssistant ? 16 : 4),
          ),
        ),
        child: dots
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (i) => Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: const BoxDecoration(
                        color: AppColors.mutedGreen,
                        shape: BoxShape.circle),
                  ),
                ),
              )
            : Text(
                text!,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: isAssistant ? Colors.black87 : Colors.white,
                ),
              ),
      ),
    );
  }
}