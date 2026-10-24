import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/conversation.dart';
import '../models/report.dart';
import '../services/farm_service.dart';
import '../services/message_service.dart';
import '../services/report_service.dart';
import '../theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/report_sheet.dart';
import 'farm_directions_screen.dart';
import 'product_detail_screen.dart' show FullScreenPhotoViewer;
import 'user_profile_screen.dart';

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

  /// Injectable for tests, same reason as [gateway].
  final ReportsGateway? reportsGateway;

  /// Injectable image picker for tests; defaults to the real gallery picker.
  /// Tests hand the screen a stub instead of launching the photo dialog.
  final Future<XFile?> Function(ImageSource source)? pickImage;

  /// Injectable farm list for tests; defaults to the seller's own farms from
  /// the backend, the same call the My Farm switcher uses.
  final Future<List<Map<String, dynamic>>> Function()? loadMyFarms;

  const InAppMessagesScreen({
    super.key,
    required this.conversation,
    this.gateway,
    this.reportsGateway,
    this.pickImage,
    this.loadMyFarms,
  });

  @override
  State<InAppMessagesScreen> createState() => _InAppMessagesScreenState();

  /// Header action to report the other person in the thread.
  static const Key reportCounterpartyKey = Key('chat-report-counterparty');

  /// The composer button that opens the gallery, for tests.
  static const Key attachPhotoKey = Key('chat-attach-photo');

  /// The composer button that shares one of the seller's farms, for tests.
  static const Key attachLocationKey = Key('chat-attach-location');

  /// One farm row inside the share sheet, for tests.
  static Key shareFarmKey(String farmId) => Key('chat-share-farm-$farmId');

  /// Key of a message bubble, so tests can long-press a specific message.
  static Key bubbleKey(String messageId) => Key('chat-bubble-$messageId');

  /// The farm a shared-location message should navigate to.
  ///
  /// New messages carry a farm id. Messages shared before that was stored only
  /// carry the seller's GPS fix; when their label names the conversation's farm,
  /// treat it as a legacy farm share and use the farm id instead of the stale
  /// point. Anything else stays a coordinate-only pin.
  static String sharedFarmIdFor(
    ChatMessage message,
    Conversation conversation,
  ) {
    final messageFarmId = (message.farmId ?? '').trim();
    if (messageFarmId.isNotEmpty) return messageFarmId;

    final label = (message.locationLabel ?? '').trim().toLowerCase();
    final conversationFarmId = (conversation.farmId ?? '').trim();
    final conversationFarmName =
        (conversation.farmName ?? '').trim().toLowerCase();

    if (label.isNotEmpty &&
        conversationFarmId.isNotEmpty &&
        conversationFarmName.isNotEmpty &&
        label == conversationFarmName) {
      return conversationFarmId;
    }

    return '';
  }
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

  /// True only while a photo is uploading. Text sends are near-instant, so the
  /// progress bar is reserved for the long tail: a photo leaves the phone,
  /// lands on the server, and rides another round-trip to Cloudinary before the
  /// row exists.
  bool _sendingPhoto = false;

  /// True while the seller's farm list is loading for the share sheet.
  bool _loadingFarms = false;

  /// True while a selected farm is being posted to the thread.
  bool _sendingLocation = false;

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

  /// Appends incoming messages, skipping any id already on screen. A poll that
  /// happens to echo a just-sent row must not render a second bubble for it,
  /// and the poll cursor has to stay at the newest id either way.
  void _addMessages(Iterable<ChatMessage> incoming) {
    final known = _messages.map((m) => m.id).toSet();
    setState(() {
      for (final message in incoming) {
        if (known.add(message.id)) {
          _messages.add(message);
        }
      }
    });
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
      _addMessages(fresh);
      if (_atBottom) _scrollToEnd();
    } catch (_) {
      // Offline or server hiccup — retry on the next tick.
    }
  }

  /// Long-press on a message bubble.
  ///
  /// Only the other side's messages are reportable. Your own message is
  /// silently ignored rather than offered-and-rejected: the server refuses it
  /// ("You can only report a message that was sent to you"), so a menu item
  /// there would only ever produce an error the user cannot act on.
  Future<void> _onMessageLongPress(ChatMessage message) async {
    if (message.isMine) return;

    // Pre-selecting the scam reason is a judgement call, not a default: in a
    // buyer<->seller harvest chat, the reason people reach for is almost
    // always money, and the hint text makes it obvious they can pick another.
    await showReportSheet(
      context,
      targetType: ReportTargetType.message,
      targetId: message.id,
      subjectName: 'this message',
      initialReason: ReportReason.fraudOrScam,
      gateway: widget.reportsGateway,
    );
  }

  /// Opens the other person's profile. Available whether the counterparty is a
  /// seller or a buyer — the profile is keyed on the account, which both have.
  /// No-op when the server sent no id for them.
  void _openProfile() {
    final userId = (widget.conversation.otherPartyId ?? '').trim();
    if (userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)),
    );
  }

  /// Report the other person in the thread, from the header.
  ///
  /// This is a separate action from reporting a single message on purpose. A
  /// buyer who is being harassed wants the seller gone from their seller's
  /// side entirely, and a queue entry against one message does not do that.
  Future<void> _reportCounterparty() async {
    final target = widget.conversation.counterpartyReportTarget;
    if (target == null) {
      showFarmSpotSnackBar(
        context,
        'This person cannot be reported right now.',
        isError: true,
      );
      return;
    }

    await showReportSheet(
      context,
      targetType: target.type,
      targetId: target.id,
      subjectName: target.name,
      gateway: widget.reportsGateway,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    if (widget.conversation.otherPartyStatus != null &&
        widget.conversation.otherPartyStatus != 'ACTIVE') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.conversation.otherPartyStatus == 'DEACTIVATED'
              ? 'This user has been deactivated and can no longer receive messages.'
              : 'This user is no longer active and can no longer receive messages.'),
          backgroundColor: AppColors.errorTerracotta,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final saved = await _api.sendMessage(widget.conversation.id, text);
      if (!mounted) return;
      // Render the server's copy (real id and timestamp) instead of a local
      // guess, so the next poll's `after` cursor lines up with the database.
      _addMessages([saved]);
      setState(() {
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

  /// Picks a photo from the gallery and sends it as a message. The photo
  /// uploads to the server and the stored row renders like any other bubble, so
  /// the other side actually sees it instead of a local placeholder.
  ///
  /// The composer locks *before* the gallery opens, not after a photo comes
  /// back. Otherwise a quick second tap on the attach button while the picker
  /// is opening would start a second pick and a second send.
  Future<void> _pickAndSendPhoto() async {
    if (_sending) return;

    if (widget.conversation.otherPartyStatus != null &&
        widget.conversation.otherPartyStatus != 'ACTIVE') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.conversation.otherPartyStatus == 'DEACTIVATED'
              ? 'This user has been deactivated and can no longer receive messages.'
              : 'This user is no longer active and can no longer receive messages.'),
          backgroundColor: AppColors.errorTerracotta,
        ),
      );
      return;
    }

    setState(() => _sending = true);

    // Both branches take the same (ImageSource) shape, so assigning either one
    // here can never produce an arity mismatch at the call below.
    final Future<XFile?> Function(ImageSource) onPick =
        widget.pickImage ?? _pickFromGallery;

    final XFile? picked;
    try {
      picked = await onPick(ImageSource.gallery);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open your photo gallery.'),
          backgroundColor: AppColors.errorTerracotta,
        ),
      );
      return;
    }
    if (!mounted) return;
    if (picked == null) {
      // The gallery was closed without a photo: unlock the composer again.
      setState(() => _sending = false);
      return;
    }

    setState(() => _sendingPhoto = true);
    try {
      final saved =
          await _api.sendMessage(widget.conversation.id, '', image: picked);
      if (!mounted) return;
      _addMessages([saved]);
      setState(() {
        _sending = false;
        _sendingPhoto = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorTerracotta,
        ),
      );
    }
  }

  /// The real gallery picker. Photos are compressed down the same path as the
  /// farm uploads — the server budget (and the peer's data plan) does not want
  /// a 12MP original riding a chat message.
  Future<XFile?> _pickFromGallery(ImageSource source) async {
    try {
      return await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
    } catch (_) {
      return null;
    }
  }

  /// Shares one of the seller's farms so the buyer can tap it and navigate.
  ///
  /// The list is read fresh on every tap: a seller may have just added a farm,
  /// and this picker is the only place the choice is made. Farms without a map
  /// pin are shown but cannot be sent - the recipient would have nowhere to go.
  Future<void> _shareLocation() async {
    if (_sending || _sendingLocation || _loadingFarms) return;

    if (widget.conversation.otherPartyStatus != null &&
        widget.conversation.otherPartyStatus != 'ACTIVE') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.conversation.otherPartyStatus == 'DEACTIVATED'
              ? 'This user has been deactivated and can no longer receive messages.'
              : 'This user is no longer active and can no longer receive messages.'),
          backgroundColor: AppColors.errorTerracotta,
        ),
      );
      return;
    }

    setState(() => _loadingFarms = true);
    List<_ShareableFarm> farms;
    try {
      final rows = await (widget.loadMyFarms ?? FarmService.getFarms)();
      farms = rows
          .map(_ShareableFarm.fromJson)
          .whereType<_ShareableFarm>()
          .toList();
    } catch (_) {
      farms = const [];
    }
    if (!mounted) return;
    setState(() => _loadingFarms = false);

    if (farms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You have no farm to share yet. Set up a farm in My Farm first.',
          ),
        ),
      );
      return;
    }

    final target = await showModalBottomSheet<_ShareableFarm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ShareFarmSheet(
        farms: farms,
        selectedFarmId: widget.conversation.farmId,
      ),
    );
    if (!mounted || target == null) return;

    setState(() => _sendingLocation = true);
    try {
      final saved = await _api.sendFarmLocation(
        widget.conversation.id,
        target.id,
        label: target.name,
      );
      if (!mounted) return;
      _addMessages([saved]);
      setState(() => _sendingLocation = false);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorTerracotta,
        ),
      );
    }
  }

  /// Opens the same directions screen a listing's Directions button uses, so a
  /// shared farm behaves exactly like a farm reached from the marketplace.
  void _openSharedLocation(ChatMessage message) {
    final farmId = InAppMessagesScreen.sharedFarmIdFor(
      message,
      widget.conversation,
    );
    final latitude = message.latitude;
    final longitude = message.longitude;
    final label = (message.locationLabel ?? '').trim();

    if (farmId.isEmpty && (latitude == null || longitude == null)) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FarmDirectionsScreen(
          farmId: farmId.isEmpty ? null : farmId,
          // A farm id is enough: the screen fetches the farm's pin itself. A
          // legacy message with no resolvable farm may only carry coordinates.
          farmPosition: farmId.isEmpty && latitude != null && longitude != null
              ? LatLng(latitude, longitude)
              : null,
          farmName: label.isEmpty ? 'Farm location' : label,
        ),
      ),
    );
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
            // Header: back arrow, counterparty, and the report action.
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
                  Expanded(
                    // Tapping the counterparty opens their profile: photo, name,
                    // contact details and, for a seller, their farms.
                    child: GestureDetector(
                      onTap: _openProfile,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          _HeaderAvatar(
                            initial: initial,
                            photo: thread.otherPartyPhoto,
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
                                if (thread.farmName != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    thread.farmName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TextStyle(color: muted, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                   // Report the other person. Not every thread needs it, but
                   // when someone is being pressured, it's one tap away in the
                   // header. Hidden entirely if there is no resolvable id.
                   if (widget.conversation.counterpartyReportTarget != null)
                     IconButton(
                       key: InAppMessagesScreen.reportCounterpartyKey,
                       onPressed: _reportCounterparty,
                       icon: const Icon(Icons.flag_outlined),
                       tooltip: 'Report this person',
                       color: Colors.black54,
                       iconSize: 20,
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
                      child: Text('${thread.buyRequestId == null ? 'About' : 'Buy request'}: ${thread.cropName ?? 'this crop'}',
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
            // Long-press is the gesture for acting on a message. Wrapped
            // rather than added to the bubble itself so the key lands on the
            // tappable region a test can target.
            GestureDetector(
              key: InAppMessagesScreen.bubbleKey(message.id),
              // Own messages are inert: the server will not accept a report on
              // them, so there is nothing to show.
              onLongPress:
                  message.isMine ? null : () => _onMessageLongPress(message),
              child: _MessageBubble(
                text: message.content,
                imageUrl: message.imageUrl,
                latitude: message.latitude,
                longitude: message.longitude,
                locationLabel: message.locationLabel,
                farmId: message.farmId,
                onLocationTap: message.hasLocation
                    ? () => _openSharedLocation(message)
                    : null,
                isMine: message.isMine,
                time: _timeLabel(message.createdAt),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInput(Color green, Color bg) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The long tail of a photo send warrants an explicit progress bar —
        // otherwise a slow uplink looks like a frozen app.
        if (_sendingPhoto)
          const LinearProgressIndicator(
            minHeight: 3,
            color: AppColors.primaryGreen,
            backgroundColor: AppColors.searchBackground,
          ),
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(
              12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
          child: Row(
            children: [
              // A seller can share one of their farms; the buyer taps it to
              // open directions. Hidden on the buyer side: the farm is already
              // on the listing, so there is nothing of theirs to share.
              if (widget.conversation.isSellerSide)
                IconButton(
                  key: InAppMessagesScreen.attachLocationKey,
                  onPressed: (_sending ||
                          _sendingLocation ||
                          _loadingFarms ||
                          (widget.conversation.otherPartyStatus != null &&
                              widget.conversation.otherPartyStatus != 'ACTIVE'))
                      ? null
                      : _shareLocation,
                  icon: (_sendingLocation || _loadingFarms)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryGreen,
                          ),
                        )
                      : const Icon(Icons.location_on_outlined),
                  color: green,
                  tooltip: 'Share farm location',
                ),
              // Attach a photo. The gallery picker returns a compressed image
              // that rides a multipart upload, so no server config changes hands.
              IconButton(
                key: InAppMessagesScreen.attachPhotoKey,
                onPressed: _sending ? null : _pickAndSendPhoto,
                icon: const Icon(Icons.image_outlined),
                color: green,
                tooltip: 'Send a photo',
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending &&
                      !(widget.conversation.otherPartyStatus != null &&
                          widget.conversation.otherPartyStatus != 'ACTIVE'),
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: (widget.conversation.otherPartyStatus != null &&
                            widget.conversation.otherPartyStatus != 'ACTIVE')
                        ? 'This user is no longer active'
                        : 'Type a message...',
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
                color: (_sending ||
                        (widget.conversation.otherPartyStatus != null &&
                            widget.conversation.otherPartyStatus != 'ACTIVE'))
                    ? green.withValues(alpha: 0.5)
                    : green,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _sending ||
                          (widget.conversation.otherPartyStatus != null &&
                              widget.conversation.otherPartyStatus != 'ACTIVE')
                      ? null
                      : _send,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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

/// The counterparty's face in the chat header: their profile photo in a
/// circle when they have one, otherwise a green circle with their initial.
/// A photo that fails to load (or is still loading) falls back to the initial
/// so the header never shows an empty hole.
class _HeaderAvatar extends StatelessWidget {
  final String initial;
  final String? photo;

  const _HeaderAvatar({required this.initial, this.photo});

  @override
  Widget build(BuildContext context) {
    final url = photo?.trim();
    if (url == null || url.isEmpty) return _initial();
    return ClipOval(
      child: Image.network(
        url,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _initial(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _initial();
        },
      ),
    );
  }

  Widget _initial() {
    return CircleAvatar(
      radius: 21,
      backgroundColor: AppColors.primaryGreen,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}

/// A single chat bubble: mine on the right in green, theirs on the left in
/// white, each with a small timestamp. A photo message renders the image
/// (tap to view it full-screen) with any caption underneath.
class _MessageBubble extends StatelessWidget {
  final String text;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final String? locationLabel;
  final String? farmId;
  final VoidCallback? onLocationTap;
  final bool isMine;
  final String time;

  const _MessageBubble({
    required this.text,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.farmId,
    this.onLocationTap,
    required this.isMine,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final green = AppColors.primaryGreen;
    final url = imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;
    final hasLocation = latitude != null && longitude != null;
    final imageWidth = MediaQuery.of(context).size.width * 0.6;
    const imageHeight = 180.0;

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
            child: hasLocation
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      _locationCard(),
                      if (text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          text,
                          style: TextStyle(
                            color: isMine ? Colors.white : Colors.black87,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  )
                : hasImage
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isMine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FullScreenPhotoViewer(
                                  urls: [url],
                                  initialIndex: 0,
                                ),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                url,
                                width: imageWidth,
                                height: imageHeight,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return _photoPlaceholder(
                                      imageWidth, imageHeight, isMine,
                                      spinner: true);
                                },
                                errorBuilder: (_, _, _) => _photoPlaceholder(
                                    imageWidth, imageHeight, isMine),
                              ),
                            ),
                          ),
                          if (text.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              text,
                              style: TextStyle(
                                color: isMine ? Colors.white : Colors.black87,
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Text(
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

  /// A shared pin, drawn as a card rather than a bare coordinate. The whole
  /// card is the tap target, because "tap the numbers" is not discoverable.
  Widget _locationCard() {
    final label = (locationLabel ?? '').trim();
    final isFarm = (farmId ?? '').trim().isNotEmpty;
    final fg = isMine ? Colors.white : Colors.black87;
    final sub = isMine ? Colors.white70 : Colors.black54;
    final accent = isMine ? Colors.white : AppColors.primaryGreen;

    return Material(
      color: isMine
          ? Colors.white.withValues(alpha: 0.15)
          : const Color(0xFFF2F6F0),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onLocationTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppColors.primaryGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFarm ? Icons.agriculture_outlined : Icons.location_on,
                  size: 19,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.isEmpty ? 'Shared location' : label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to open directions',
                      style: TextStyle(color: sub, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.navigation_outlined, size: 18, color: sub),
            ],
          ),
        ),
      ),
    );
  }

  /// The striped-in placeholder while a photo downloads, or the broken-image
  /// fallback when it cannot. Same footprint either way so a bubble never
  /// jumps while loading.
  Widget _photoPlaceholder(double width, double height, bool isMine,
      {bool spinner = false}) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: isMine
          ? AppColors.primaryGreen.withValues(alpha: 0.08)
          : const Color(0xFFF3F5F1),
      child: spinner
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryGreen,
              ),
            )
          : const Icon(Icons.broken_image_outlined,
              color: AppColors.mutedGreen, size: 32),
    );
  }
}

/// One of the seller's farms, as offered by the share sheet.
///
/// Built from the same raw `GET /api/farms` rows the My Farm switcher uses.
/// The server stores the farm's coordinates, but the app needs them here to
/// tell which farms can actually be sent: a farm without a pin has nowhere for
/// the recipient to navigate to.
class _ShareableFarm {
  const _ShareableFarm({
    required this.id,
    required this.name,
    required this.barangay,
    required this.status,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final String? barangay;
  final String status;
  final double? latitude;
  final double? longitude;

  bool get canNavigate => latitude != null && longitude != null;

  String get statusLabel => switch (status) {
        'APPROVED' => 'Approved',
        'PENDING_REVIEW' => 'Pending review',
        'REJECTED' => 'Rejected',
        _ => status,
      };

  static _ShareableFarm? fromJson(Map<String, dynamic> raw) {
    final id = (raw['FRM_ID'] as String?)?.trim();
    final name = (raw['FRM_NAME'] as String?)?.trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;

    return _ShareableFarm(
      id: id,
      name: name,
      barangay: (raw['FRM_BARANGAY'] as String?)?.trim(),
      status: (raw['FRM_STATUS'] as String?)?.trim() ?? '',
      latitude: _coord(raw['FRM_LATITUDE']),
      longitude: _coord(raw['FRM_LONGITUDE']),
    );
  }

  /// Laravel serialises decimal columns as strings, so accept both.
  static double? _coord(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// Bottom sheet that lets a seller choose which farm location to send.
///
/// A seller can own several farms, so the choice is explicit rather than
/// silently picking the conversation's farm. That farm is pre-selected when it
/// has a pin, but the rest of the seller's farms are one tap away.
class _ShareFarmSheet extends StatefulWidget {
  const _ShareFarmSheet({
    required this.farms,
    this.selectedFarmId,
  });

  final List<_ShareableFarm> farms;
  final String? selectedFarmId;

  @override
  State<_ShareFarmSheet> createState() => _ShareFarmSheetState();
}

class _ShareFarmSheetState extends State<_ShareFarmSheet> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = _initialSelection(widget.farms, widget.selectedFarmId);
  }

  static String? _initialSelection(
    List<_ShareableFarm> farms,
    String? preferredId,
  ) {
    if (preferredId != null) {
      for (final farm in farms) {
        if (farm.id == preferredId && farm.canNavigate) return farm.id;
      }
    }
    for (final farm in farms) {
      if (farm.canNavigate) return farm.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final anyNavigable = widget.farms.any((farm) => farm.canNavigate);
    final selected = _selected == null
        ? null
        : widget.farms.firstWhere((farm) => farm.id == _selected);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.agriculture_outlined,
                    color: AppColors.primaryGreen),
                const SizedBox(width: 8),
                const Text(
                  'Share farm location',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'The buyer can tap the pin to open directions to the farm.',
              style: TextStyle(color: Colors.black54, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            if (!anyNavigable)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'None of your farms has a map location yet. Add a pin to a '
                  'farm in My Farm first.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final farm in widget.farms)
                        InkWell(
                          key: InAppMessagesScreen.shareFarmKey(farm.id),
                          onTap: farm.canNavigate
                              ? () => setState(() => _selected = farm.id)
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  farm.canNavigate
                                      ? (_selected == farm.id
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off)
                                      : Icons.location_off_outlined,
                                  color: farm.canNavigate
                                      ? AppColors.primaryGreen
                                      : Colors.black26,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        farm.name,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: farm.canNavigate
                                              ? Colors.black87
                                              : Colors.black38,
                                        ),
                                      ),
                                      Text(
                                        [
                                          if ((farm.barangay ?? '')
                                              .isNotEmpty)
                                            farm.barangay!,
                                          if (farm.status.isNotEmpty)
                                            farm.statusLabel,
                                          if (!farm.canNavigate)
                                            'No map location yet',
                                        ].join(' · '),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.of(context).pop(selected),
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: const Text('Send location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
