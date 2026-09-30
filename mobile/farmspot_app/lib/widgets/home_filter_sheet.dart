import 'package:flutter/material.dart';

import '../models/crop_category.dart';
import '../models/home_filters.dart';
import '../theme.dart';

/// The Filter button and the sheet it opens.
///
/// Both live here rather than in home_screen.dart for one reason: the button
/// has to be testable on its own, and a screen-level method is not. The screen
/// owns the filter *state*; these two own the *presentation* of it.
///
/// Styling is lifted from the sheet on search_results_screen.dart so the two
/// filter surfaces in the app look like the same control.
class HomeFilterButton extends StatelessWidget {
  /// The filters currently applied. Decides the quiet vs active appearance.
  final HomeFilters filters;

  /// The display name of [HomeFilters.categoryId], resolved by the screen.
  ///
  /// The category chips that used to name the selected category on screen are
  /// gone, so without this the applied category would be invisible except by
  /// reopening this sheet. Null when no category is applied, or before the
  /// category list has loaded.
  final String? categoryName;

  final VoidCallback onTap;

  /// Finds the button in tests. The Home feed has several icon buttons, and a
  /// test that hunts for `Icons.tune` would also match the sort control.
  static const Key buttonKey = Key('home-filter-button');

  const HomeFilterButton({
    super.key,
    required this.filters,
    required this.onTap,
    this.categoryName,
  });

  /// "1 category" says nothing useful on its own, so the resolved name is used
  /// when there is one.
  String? get _summary => filters.summaryFor(categoryName: categoryName);

  @override
  Widget build(BuildContext context) {
    final active = filters.isActive;
    final tint = active ? AppColors.warningAmber : AppColors.primaryGreen;
    final summary = _summary;

    return Semantics(
      key: buttonKey,
      button: true,
      label: summary == null
          ? 'Filters, none applied'
          : 'Filters, applied: $summary',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFDF3E0) : const Color(0xFFE3EEDD),
            borderRadius: BorderRadius.circular(12),
            border: active ? Border.all(color: tint) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 16, color: tint),
              const SizedBox(width: 5),
              // "Filter" rather than "Filters": the button opens one sheet, and
              // the singular reads better beside a single tune icon.
              Text(
                'Filter',
                style: TextStyle(
                  color: tint,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 5),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The popup behind [HomeFilterButton].
///
/// Unlike the single-group category sheet on the search screen, this one holds
/// three groups at once, so tapping an option does NOT close it — a buyer
/// setting category, availability and sort would otherwise have to reopen the
/// sheet three times. Edits are local until Apply returns them.
///
/// Returns the chosen [HomeFilters], or null if dismissed without applying.
Future<HomeFilters?> showHomeFilterSheet(
  BuildContext context, {
  required HomeFilters current,
  required List<CropCategory> categories,
}) {
  return showModalBottomSheet<HomeFilters>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => HomeFilterSheet(initial: current, categories: categories),
  );
}

class HomeFilterSheet extends StatefulWidget {
  final HomeFilters initial;
  final List<CropCategory> categories;

  const HomeFilterSheet({
    super.key,
    required this.initial,
    required this.categories,
  });

  @override
  State<HomeFilterSheet> createState() => _HomeFilterSheetState();
}

class _HomeFilterSheetState extends State<HomeFilterSheet> {
  late HomeFilters _draft = widget.initial;

  void _update(HomeFilters next) => setState(() => _draft = next);

  /// Only the parts the buyer touched, so an untouched sheet is a no-op and
  /// does not trigger a pointless reload of the feed.
  bool get _changed => _draft != widget.initial;

  /// Reset clears the draft back to nothing, which is usually *different* from
  /// what was already applied — so _changed stays true and the button rightly
  /// keeps saying "Apply filters". What must not happen is Reset staying on
  /// screen afterwards, offering to clear something already clear.
  bool get _canReset => _draft != HomeFilters.none;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        // Three groups of options are taller than a phone screen on a small
        // device. Capping the body and letting the list scroll keeps the
        // Apply row reachable instead of letting the sheet run off the bottom.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Filter listings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGreen,
                          ),
                        ),
                      ),
                      if (_canReset)
                        TextButton(
                          onPressed: () => _update(HomeFilters.none),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.errorTerracotta,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Reset',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Narrow the feed by crop, by availability, and choose how '
                    'it is ordered.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  _sectionLabel('Category'),
                  _radioRow(
                    label: 'All categories',
                    selected: _draft.categoryId == null,
                    onTap: () => _update(_draft.copyWith(clearCategory: true)),
                  ),
                  for (final category in widget.categories)
                    _radioRow(
                      label: category.name,
                      selected: _draft.categoryId == category.id,
                      onTap: () =>
                          _update(_draft.copyWith(categoryId: category.id)),
                    ),
                  const SizedBox(height: 8),
                  _sectionLabel('Availability'),
                  _radioRow(
                    label: 'Any',
                    selected: _draft.availability == null,
                    onTap: () =>
                        _update(_draft.copyWith(clearAvailability: true)),
                  ),
                  for (final option in FeedAvailability.values)
                    _radioRow(
                      label: option.label,
                      selected: _draft.availability == option,
                      onTap: () =>
                          _update(_draft.copyWith(availability: option)),
                    ),
                  const SizedBox(height: 8),
                  _sectionLabel('Sort by'),
                  for (final option in HomeSortMode.values)
                    _radioRow(
                      label: option.label,
                      // Sort always has a value, so this can never be "none".
                      selected: _draft.sort == option,
                      onTap: () => _update(_draft.copyWith(sort: option)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: Text(
                    _changed ? 'Apply filters' : 'Done',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.mutedGreen,
      ),
    ),
  );

  Widget _radioRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.black87, fontSize: 15),
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? AppColors.primaryGreen : Colors.black26,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
