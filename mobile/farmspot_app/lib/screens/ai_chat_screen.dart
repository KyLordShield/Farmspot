import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/ai_chat_service.dart';
import '../theme.dart';

/// FarmSpot AI chat assistant.
///
/// Calls /api/ai/chat on our own Laravel backend, which holds the provider key
/// — the app never talks to the model host directly. [gateway] is injectable
/// so widget tests can supply a fake instead of a live call.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    super.key,
    this.gateway,
  });
  final AiGateway? gateway;

  /// The questions people actually ask most often, offered as one-tap chips so
  /// a new user has somewhere to start instead of a blank box. Deliberately a
  /// mix: some are answered from the user's own records, some are app how-to,
  /// and one is a plain farming question, which is what shows the assistant is
  /// more than a status page.
  static const List<String> suggestions = [
    "What's my farm status?",
    'How do I list my produce?',
    'How do I become a seller?',
    'How do I message a seller?',
    'When should I plant pechay?',
  ];

  /// Finds the horizontal chip strip in tests, where several ListViews exist.
  static const Key suggestionStripKey = Key('ai-suggestion-strip');

  /// Finds the context pill's topic label. It repeats text from the first
  /// question, so a test that wants the pill alone needs to target this rather
  /// than searching the whole screen for the string.
  static const Key topicPillKey = Key('ai-topic-pill');

  /// Finds the pending-reply bubble. A test that wants to assert the
  /// assistant is still working has to target this: the dots are plain
  /// Containers, so there is no text to search for.
  static const Key typingDotsKey = Key('ai-typing-dots');

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

/// A row in the visible transcript. [retryText] is set only on error bubbles,
/// so the bubble can re-ask the question that failed.
class _Msg {
  const _Msg(
    this.text, {
    this.isAssistant = false,
    this.isError = false,
    this.retryText,
  });

  final String text;
  final bool isAssistant;
  final bool isError;
  final String? retryText;
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _messages = [];
  final AiChatSession _session = AiChatSession.instance;
  bool _typing = false;

  /// True once the user has asked something, which retires the chips. A blank
  /// box with no way in is the main reason an assistant like this goes unused.
  bool _asked = false;

  late final AiGateway _gateway = widget.gateway ?? AiChatService.instance;

  @override
  void initState() {
    super.initState();
    // Display-only. It is deliberately not added to the sent history: the
    // system prompt already sets the persona, and a leading assistant turn
    // with no question before it is an odd shape for the provider.
    // Promises only what the assistant can actually deliver. It has no live
    // weather feed and no price feed beyond current marketplace listings, so
    // advertising those here would set up an immediate letdown.
    _messages.add(const _Msg(
      'Kumusta! I\'m FarmSpot ai assist. I can check your farm and listings, '
      'walk you through the app, and help with farming questions.',
      isAssistant: true,
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
    if (text.isEmpty || _typing) return;
    _input.clear();
    await _ask(text);
  }

  /// Re-asks a question that previously failed, dropping the error bubble so
  /// it does not accumulate alongside the retry.
  Future<void> _retry(_Msg failed) async {
    if (_typing) return;
    setState(() => _messages.remove(failed));
    await _ask(failed.retryText!);
  }

  /// Puts the question on screen and sends it.
  ///
  /// On failure the question is pulled back out of the sent history. Otherwise
  /// the model would receive a question that was never answered and might try
  /// to answer two things at once on the next turn.
  Future<void> _ask(String text) async {
    setState(() {
      _messages.add(_Msg(text));
      _typing = true;
      _asked = true;
    });
    _session.history.add(AiTurn('user', text));
    _scrollToEnd();

    try {
      final reply = await _gateway.replyTo(_session.history);
      _session.history.add(AiTurn('assistant', reply));
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg(reply, isAssistant: true));
        _typing = false;
      });
    } catch (error) {
      _session.history.removeLast();
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _messages.add(_Msg(
          '$error',
          isAssistant: true,
          isError: true,
          retryText: text,
        ));
        _typing = false;
      });
    }
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

  /// One-tap starter questions, shown above the input until the user asks
  /// something of their own.
  Widget _suggestionChips(Color green, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Text(
            'Try asking',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ),
        SizedBox(
          // Explicit width: the surrounding Column centres its children with
          // loose constraints, so a horizontal ListView would otherwise size
          // itself to its full content width and run off the screen instead of
          // scrolling.
          width: double.infinity,
          height: 38,
          child: ListView.separated(
            key: AiChatScreen.suggestionStripKey,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: AiChatScreen.suggestions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final question = AiChatScreen.suggestions[i];
              return Material(
                color: Colors.white,
                shape: StadiumBorder(
                  side: BorderSide(color: green.withValues(alpha: 0.3)),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _typing ? null : () => _ask(question),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(
                        question,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: green,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
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
            // Context pill: "Via Farmspot • Assistant".
            //
            // This was a fixed "Cabbage Inquiry", which labelled every thread as
            // a question about one crop. Showing the user's first question
            // instead was worse: it echoed their message back at the top of the
            // screen, and a long one ran off the edge. The label is now static,
            // and Flexible below guarantees it can never overflow whatever
            // somebody types.
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
                mainAxisSize: MainAxisSize.min,
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
                  const Flexible(
                    child: Text(
                      'Assistant',
                      key: AiChatScreen.topicPillKey,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
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
                  final message = _messages[i];
                  return _Bubble(
                    text: message.text,
                    isAssistant: message.isAssistant,
                    isError: message.isError,
                    onTap: message.isError && !_typing
                        ? () => _retry(message)
                        : null,
                  );
                },
              ),
            ),
            // Starter questions, retired as soon as the user asks anything.
            if (!_asked) ...[
              _suggestionChips(green, muted),
              const SizedBox(height: 8),
            ],
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
                    // Dims while the assistant is working, so it is obvious the
                    // tap did land rather than being ignored.
                    color: _typing ? green.withValues(alpha: 0.4) : green,
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

/// The three dots shown in the assistant bubble while a reply is pending.
///
/// A wave rather than a blink. All three dots run the same sine cycle, each a
/// fixed fraction of a phase ahead of the one before it, so they rise and fall
/// in sequence. Fading them together in unison instead reads as a spinner, not
/// as somebody typing.
///
/// One controller drives all three so the offsets cannot drift apart over a
/// long wait. The phase is taken modulo one rather than through an `Interval`,
/// because sine is continuous as it wraps: the cycle joins up seamlessly and
/// there is no snap back to the start on every pass.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  /// Slow enough to read as deliberate typing. Faster than this and the wave
  /// looks like a glitch rather than a person.
  static const Duration _cycle = Duration(milliseconds: 1000);

  /// How far ahead of the previous dot each one sits, as a fraction of the
  /// cycle. Roughly a fifth of a cycle, which splits the three dots evenly
  /// around the wave instead of bunching two of them together.
  static const double _phaseStep = 0.22;

  late final AnimationController _wave =
      AnimationController(vsync: this, duration: _cycle)..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wave,
      builder: (context, _) {
        return Row(
          key: AiChatScreen.typingDotsKey,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_wave.value + i * _phaseStep) % 1.0;
            // -1 at the bottom of the dip, 1 at the top of the rise.
            final rise = math.sin(phase * 2 * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Transform.translate(
                offset: Offset(0, -3 * rise),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    // Brighter at the top of the wave, so the leading dot leads
                    // the eye as well as the movement.
                    color: AppColors.mutedGreen
                        .withValues(alpha: 0.45 + 0.55 * ((rise + 1) / 2)),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Rounded chat bubble. Assistant = white (left), user = green (right).
/// `dots: true` renders the animated three-dot typing indicator instead of
/// text. [isError] tints the bubble red and makes it tappable, which is how a
/// failed turn is retried.
class _Bubble extends StatelessWidget {
  const _Bubble({
    this.text,
    required this.isAssistant,
    this.dots = false,
    this.isError = false,
    this.onTap,
  });
  final String? text;
  final bool isAssistant;
  final bool dots;
  final bool isError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final green = AppColors.primaryGreen;
    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              color: isError ? const Color(0xFFFDEDEC) : (isAssistant ? Colors.white : green),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isAssistant ? 4 : 16),
                bottomRight: Radius.circular(isAssistant ? 16 : 4),
              ),
              border: isError ? Border.all(color: const Color(0xFFF0B7B1)) : null,
            ),
            child: dots
                ? const _TypingDots()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: isError
                              ? const Color(0xFF9C2A20)
                              : (isAssistant ? Colors.black87 : Colors.white),
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                size: 13, color: Color(0xFF9C2A20)),
                            const SizedBox(width: 4),
                            Text('Tap to retry',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF9C2A20))),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
