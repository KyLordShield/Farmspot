import 'package:flutter/material.dart';

/// Keeps a large catalog scrollable while selection survives search changes.
class SourcingCropPicker extends StatefulWidget {
  final List<String> catalog;
  final Map<String, List<String>> aliases;
  final Set<String> selected;
  const SourcingCropPicker({
    super.key,
    required this.catalog,
    required this.aliases,
    required this.selected,
  });
  @override
  State<SourcingCropPicker> createState() => _SourcingCropPickerState();
}

class _SourcingCropPickerState extends State<SourcingCropPicker> {
  late final Set<String> _selected = Set.of(widget.selected);
  final _search = TextEditingController();
  String _query = '';
  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalize(_query);
    final results = widget.catalog
        .where(
          (crop) => [
            crop,
            ...?widget.aliases[crop],
          ].any((name) => _normalize(name).contains(query)),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose crops',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search crops, e.g. Tomato or Kamatis',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${_selected.length} of 50 selected · ${results.length} crops found',
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text('No crops found. Try another name.'),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final crop = results[index];
                        final checked = _selected.contains(crop);
                        return CheckboxListTile(
                          title: Text(crop),
                          value: checked,
                          subtitle: widget.aliases[crop]?.isNotEmpty == true
                              ? Text(widget.aliases[crop]!.join(', '))
                              : null,
                          onChanged: !checked && _selected.length >= 50
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _selected.add(crop);
                                  } else {
                                    _selected.remove(crop);
                                  }
                                }),
                        );
                      },
                    ),
            ),
            if (_selected.length >= 50)
              const Text('Your list is full. Remove a crop to select another.'),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Add selected'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
