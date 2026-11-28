import 'package:flutter/material.dart';
import '../models/conversation.dart';
import '../services/message_service.dart';
import '../services/session_state.dart';
import '../screens/in_app_messages_screen.dart';

class MessageFarmerButton extends StatefulWidget {
  final String farmerId;
  final String? userId;
  final Future<Conversation> Function(String)? startConversation;
  const MessageFarmerButton({
    super.key,
    required this.farmerId,
    this.userId,
    this.startConversation,
  });
  @override
  State<MessageFarmerButton> createState() => _MessageFarmerButtonState();
}

class _MessageFarmerButtonState extends State<MessageFarmerButton> {
  bool _opening = false;
  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      final thread =
          await (widget.startConversation ??
              MessageService.instance.startFarmerConversation)(widget.farmerId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InAppMessagesScreen(conversation: thread),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownId = SessionState.instance.user?['USR_ID']?.toString();
    if (widget.farmerId.trim().isEmpty ||
        (ownId != null && ownId == widget.userId)) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _opening ? null : _open,
        icon: _opening
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chat_bubble_outline, size: 18),
        label: Text(_opening ? 'Opening...' : 'Message Farmer'),
      ),
    );
  }
}
