import 'package:flutter/material.dart';
import '../utils/address_areas.dart';

/// Offline suggestions directly under the active address/barangay input.
class AddressAreaField extends StatefulWidget {
  const AddressAreaField({
    super.key,
    required this.controller,
    required this.maxLength,
    required this.fieldBuilder,
    this.barangayOnly = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final int maxLength;
  final Widget Function(FocusNode focusNode) fieldBuilder;
  final bool barangayOnly;
  final ValueChanged<String>? onChanged;
  @override
  State<AddressAreaField> createState() => _AddressAreaFieldState();
}

class _AddressAreaFieldState extends State<AddressAreaField> {
  final _focusNode = FocusNode();
  String? _selectedText;
  final _suggestionsKey = GlobalKey();
  String _lastText = '';
  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_focusChanged);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(AddressAreaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
      _selectedText = null;
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    if (_lastText != widget.controller.text) {
      _lastText = widget.controller.text;
      _revealSuggestions();
    }
  }

  void _focusChanged() {
    if (_focusNode.hasFocus) _selectedText = null;
    _refresh();
    if (_focusNode.hasFocus) _revealSuggestions();
  }

  void _revealSuggestions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      final target = _suggestionsKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.removeListener(_focusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _select(String area) {
    final value = widget.barangayOnly
        ? area
        : AddressAreas.withArea(widget.controller.text, area);
    if (value.characters.length > widget.maxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Keep the address within ${widget.maxLength} characters. Shorten the house or street details and try again.',
          ),
        ),
      );
      return;
    }
    _selectedText = value;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text.trim();
    final areas = !_focusNode.hasFocus || text.isEmpty || text == _selectedText
        ? <String>[]
        : AddressAreas.suggestions(text).take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.fieldBuilder(_focusNode),
        if (areas.isNotEmpty)
          Container(
            key: _suggestionsKey,
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFDDDFDD)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                shrinkWrap: true,
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: areas.length,
                itemBuilder: (context, index) => ListTile(
                  dense: true,
                  title: Text(
                    areas[index],
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () => _select(areas[index]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
