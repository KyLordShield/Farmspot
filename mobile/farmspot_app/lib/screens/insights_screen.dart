import '../widgets/loading_pulse.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../insight_colors.dart';
import 'search_results_screen.dart';
import 'seller/add_crop_screen.dart';
import '../widgets/home_widgets.dart';
import '../widgets/seller_widgets.dart';
import '../models/insights.dart';
import '../services/session_state.dart';
import '../services/insights_service.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'seller/my_farm_screen.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    this.loadInsights = InsightsService.fetchInsights,
  });

  final Future<InsightsPayload> Function() loadInsights;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late Future<InsightsPayload> _payloadFuture;
  InsightsPayload? _payload;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 390),
    );
    _payloadFuture = _loadInsights();
  }

  Future<InsightsPayload> _loadInsights() async {
    final payload = await widget.loadInsights();
    if (mounted) {
      if (_payload == null) {
        if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
          _entrance.value = 1;
        } else {
          _entrance.forward();
        }
      }
      _payload = payload;
    }
    return payload;
  }

  /// Pull-to-refresh: fetch fresh insights while keeping current data on screen.
  Future<void> _refresh() async {
    final next = _loadInsights();
    setState(() => _payloadFuture = next);
    try {
      await next;
    } catch (_) {
      // Keep last good data if a pull fails; the retry button still works.
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _handleNavTap(int i) {
    if (i == 2) return;
    // Read live session state: buyer nav has 4 tabs and seller nav 5, so a
    // stale role here routes the tap to the wrong screen.
    final isSeller = SessionState.instance.isSeller;
    switch (i) {
      case 0:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        break;
      case 1:
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const MapScreen()));
        break;
      case 3:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                isSeller ? const MyFarmScreen() : const ProfileScreen(),
          ),
        );
        break;
      case 4:
        if (isSeller) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<InsightsPayload>(
                  future: _payloadFuture,
                  builder: (context, snapshot) {
                    final payload = snapshot.data ?? _payload;
                    if (payload != null) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (snapshot.hasError)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Could not refresh. Showing the last loaded results.',
                              ),
                            ),
                          ..._buildSections(
                            payload,
                          ).indexed.map((item) => _enter(item.$1, item.$2)),
                        ],
                      );
                    }
                    if (snapshot.connectionState != ConnectionState.done) {
                      return _fillScrollable(_buildLoading(context));
                    }
                    return _fillScrollable(
                      _ErrorRetry(
                        message:
                            'Could not load crop insights. Check your connection and try again.',
                        onRetry: () => setState(() {
                          _payloadFuture = _loadInsights();
                        }),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: SessionState.instance,
        builder: (context, _) => SessionState.instance.isSeller
            ? SellerBottomNav(currentIndex: 2, onTap: _handleNavTap)
            : FarmSpotBottomNav(currentIndex: 2, onTap: _handleNavTap),
      ),
    );
  }

  /// Wraps a centered child in a full-height scrollable so the RefreshIndicator
  /// can receive the pull gesture even while loading or showing an error.
  Widget _fillScrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight,
            minWidth: constraints.maxWidth,
          ),
          child: child,
        ),
      ),
    );
  }

  List<Widget> _buildSections(InsightsPayload payload) {
    final data = payload.searchInterest;
    return [
      _SeasonalTrendCard(
        trends: payload.seasonalTrends,
        month: data['month_key'] as String?,
      ),
      const SizedBox(height: 16),
      if (data.isNotEmpty) ...[
        _InterestPanel(data: data, onPick: (row) => _openPrediction(row, data)),
        const SizedBox(height: 16),
      ],
      for (final section in payload.sections) ...[
        _InsightListCard(key: ValueKey(section.type), section: section),
        const SizedBox(height: 12),
      ],
      if (data.isNotEmpty)
        const Text(
          'Estimates based on app searches, not guaranteed.',
          style: TextStyle(color: InsightColors.muted, fontSize: 16),
        ),
    ];
  }

  Widget _enter(int index, Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = (index * .035).clamp(0.0, .35).toDouble();
    final animation = _entrance.drive(
      CurveTween(curve: Interval(delay, 1, curve: Curves.easeOut)),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(0, .025), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }

  Widget _buildLoading(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(liveRegion: true, child: Text('Loading crop insights…')),
        const SizedBox(height: 12),
        for (var index = 0; index < 3; index++) ...[
          LoadingPulse(
            child: Container(
              height: 92,
              padding: const EdgeInsets.all(16),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: .55,
                  child: ColoredBox(
                    color: Color(0xFFE9EDE9),
                    child: SizedBox(height: 12),
                  ),
                ),
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE3E7E4)),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );

  Widget _buildHeader() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    color: AppColors.primaryGreen,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Crop Insights',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Demand & Seasonal Trends',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    ),
  );

  Future<void> _openPrediction(
    Map<String, dynamic> row,
    Map<String, dynamic> data,
  ) async {
    final crop = row['crop'] as String;
    final history = (row['history'] as Map?) ?? const {};
    final seller = SessionState.instance.isSeller;
    final openListing = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .85,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              '${_displayLabel(crop)} may be popular this ${data['month']}.',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _predictionExplanation(row['confidence']),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'These estimates come from FarmSpot searches. Crop availability may change.',
            ),
            if (history.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Past searches by month'),
                children: [
                  for (final entry in history.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.key.toString()),
                      subtitle: Text(
                        entry.value == null
                            ? 'No records'
                            : '${((entry.value as num) * 100).toStringAsFixed(1)}% of crop searches',
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.pop(sheetContext, true),
              child: Text(seller ? 'Add a listing' : 'See listings'),
            ),
          ],
        ),
      ),
    );
    if (openListing != true || !mounted) return;
    if (seller) {
      await Navigator.of(
        context,
      ).push(
        MaterialPageRoute(
          builder: (_) => const AddCropScreen(openCameraOnStart: true),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SearchResultsScreen(query: crop)),
      );
    }
  }
}

const _insightInk = InsightColors.ink;
const _insightMuted = InsightColors.muted;

class _InsightListCard extends StatelessWidget {
  const _InsightListCard({super.key, required this.section});

  final InsightSection section;

  @override
  Widget build(BuildContext context) {
    final (icon, title, description, unit) = switch (section.type) {
      'top_searched' => (
        Icons.search_rounded,
        'Most searched crops',
        'What people looked for in the last 7 days.',
        'search',
      ),
      'by_category' => (
        Icons.category_outlined,
        'Listings by category',
        'Listings marked available now or soon to harvest.',
        'listing',
      ),
      _ => (Icons.bar_chart_rounded, section.title, '', 'result'),
    };
    final entries = section.entries;

    return _InsightCard(
      icon: icon,
      title: title,
      description: description,
      child: entries.isEmpty
          ? Text(
              section.type == 'top_searched'
                  ? 'No searches recorded in the last 7 days.'
                  : 'No counts to show yet.',
              style: const TextStyle(color: _insightMuted),
            )
          : Column(
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: _CountRow(
                      key: ValueKey(entry.label),
                      label: _displayLabel(entry.label),
                      count: entry.value,
                      unit: unit,
                    ),
                  ),
              ],
            ),
    );
  }
}

String _displayLabel(String label) {
  final text = label.trim();
  if (text.isEmpty) return 'Unspecified';
  return text[0].toUpperCase() + text.substring(1);
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    super.key,
    required this.label,
    required this.count,
    required this.unit,
  });

  final String label;
  final int count;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final value = MaterialLocalizations.of(context).formatDecimal(count);
    final countLabel =
        '$value ${count == 1
            ? unit
            : unit == 'search'
            ? 'searches'
            : '${unit}s'}';
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            countLabel,
            textAlign: TextAlign.end,
            style: const TextStyle(color: _insightMuted),
          ),
        ),
      ],
    );
  }
}

class _SeasonalTrendCard extends StatefulWidget {
  const _SeasonalTrendCard({required this.trends, this.month});

  final List<SeasonalTrend> trends;
  final String? month;

  @override
  State<_SeasonalTrendCard> createState() => _SeasonalTrendCardState();
}

class _SeasonalTrendCardState extends State<_SeasonalTrendCard> {
  static const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  int? selected;

  int _monthOf(SeasonalTrend trend) {
    final date = DateTime.tryParse('${trend.period}-01');
    if (date != null) return date.month;
    return months.indexWhere(
          (month) => month.toLowerCase() == trend.title.trim().toLowerCase(),
        ) +
        1;
  }

  @override
  Widget build(BuildContext context) {
    final current =
        DateTime.tryParse('${widget.month}-01')?.month ??
        DateTime.now().toUtc().add(const Duration(hours: 8)).month;
    final month = selected ?? current;
    final matching = widget.trends
        .where((trend) => _monthOf(trend) == month)
        .toList();
    final crops = {
      for (final trend in matching)
        for (final crop in trend.crops) _displayLabel(crop),
    }.toList();
    return _InsightCard(
      icon: Icons.calendar_month_outlined,
      title: 'Seasonal outlook',
      description: 'Common crops by harvest month.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: _CropResults(
              key: ValueKey(month),
              title: 'Common harvests in ${months[month - 1]}',
              crops: crops,
              empty: 'No harvest records for this month.',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: month,
                isExpanded: true,
                iconSize: 16,
                selectedItemBuilder: (context) => [
                  for (final name in months)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        name,
                        semanticsLabel: 'Harvest month: $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: InsightColors.green),
                items: [
                  for (var index = 0; index < months.length; index++)
                    DropdownMenuItem(
                      value: index + 1,
                      child: Text(
                        months[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropResults extends StatelessWidget {
  const _CropResults({
    super.key,
    required this.title,
    required this.crops,
    required this.empty,
  });

  final String title;
  final List<String> crops;
  final String empty;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: InsightColors.tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: InsightColors.muted)),
          const SizedBox(height: 8),
          if (crops.isEmpty) Text(empty),
          for (final crop in crops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                crop,
                style: const TextStyle(
                  color: InsightColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE7DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C173A20),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 17, color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: _insightInk,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(color: _insightMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _InterestPanel extends StatelessWidget {
  const _InterestPanel({required this.data, required this.onPick});

  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onPick;

  @override
  Widget build(BuildContext context) {
    final predictions = insightRows(data, 'predictions');
    final trending = insightRows(data, 'trending');
    final month = data['month'] ?? 'this month';
    final updated = DateTime.tryParse(data['updated_at'] as String? ?? '');
    final elapsed = updated == null ? null : DateTime.now().difference(updated);
    final age = elapsed == null
        ? null
        : elapsed.inDays > 0
        ? '${elapsed.inDays}d ago'
        : elapsed.inHours > 0
        ? '${elapsed.inHours}h ago'
        : elapsed.inMinutes > 0
        ? '${elapsed.inMinutes}m ago'
        : 'just now';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data['is_demo'] != true && age != null) ...[
          Text(
            'Updated $age',
            style: const TextStyle(color: InsightColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
        ],
        _InsightCard(
          icon: Icons.trending_up_rounded,
          title: 'Crop search trends',
          description: 'This month’s outlook and recent weekly search counts.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Predicted for this month',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Crops people may look for in $month. Tap a crop to see why.',
                style: const TextStyle(color: InsightColors.muted),
              ),
              const SizedBox(height: 12),
              if (predictions.isEmpty)
                const Text(
                  'Not enough data to estimate what people may search for this month.',
                )
              else
                _CardGrid(
                  children: [
                    for (final row in predictions)
                      _PredictionTile(
                        key: ValueKey<String>(row['crop'] as String),
                        row: row,
                        onTap: () => onPick(row),
                      ),
                  ],
                ),
              const Divider(height: 32),
              Text(
                'Trending now',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'How many people searched for each crop in the last two full weeks.',
                style: TextStyle(color: InsightColors.muted),
              ),
              const SizedBox(height: 12),
              if (trending.isEmpty)
                const Text('No weekly searches to show yet.')
              else
                _WeeklyComparison(
                  entries: trending,
                  weekLabels:
                      ((data['week_ranges'] ?? data['week_labels']) as List? ??
                              const [])
                          .cast<String>(),
                ),
            ],
          ),
        ),
        if (insightRows(data, 'forecast').isNotEmpty) ...[
          const SizedBox(height: 16),
          _SearchForecast(months: insightRows(data, 'forecast')),
        ],
      ],
    );
  }
}

class _SearchForecast extends StatefulWidget {
  const _SearchForecast({required this.months});

  final List<Map<String, dynamic>> months;

  @override
  State<_SearchForecast> createState() => _SearchForecastState();
}

class _SearchForecastState extends State<_SearchForecast> {
  String? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final month = widget.months.firstWhere(
      (entry) => entry['month_key'] == _selectedMonth,
      orElse: () => widget.months.first,
    );
    final crops = insightRows(month, 'crops');

    return _InsightCard(
      icon: Icons.calendar_month_outlined,
      title: 'Search forecast',
      description: 'What people may search for over the next three months.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: _CropResults(
              key: ValueKey(month['month_key']),
              title: month['month'] as String,
              crops: [
                for (final crop in crops) _displayLabel(crop['crop'] as String),
              ],
              empty: 'Too few past searches to forecast this month yet.',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in widget.months)
                ChoiceChip(
                  label: Text(
                    (entry['month'] as String).characters.take(3).join(),
                    semanticsLabel: entry['month'] as String,
                  ),
                  showCheckmark: false,
                  selected: entry == month,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => setState(() {
                    _selectedMonth = entry['month_key'] as String;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sideBySide =
          children.length > 1 &&
          constraints.maxWidth >= 290 &&
          MediaQuery.textScalerOf(context).scale(16) <= 21;
      final width = sideBySide
          ? (constraints.maxWidth - 10) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _WeeklyComparison extends StatefulWidget {
  const _WeeklyComparison({required this.entries, required this.weekLabels});
  final List<Map<String, dynamic>> entries;
  final List<String> weekLabels;

  @override
  State<_WeeklyComparison> createState() => _WeeklyComparisonState();
}

class _WeeklyComparisonState extends State<_WeeklyComparison> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final format = MaterialLocalizations.of(context).formatDecimal;
    final entries = widget.entries;
    final weekLabels = widget.weekLabels;
    final dated = weekLabels.length >= 3;
    final earlier = dated ? '${weekLabels[1]}\nEarlier week' : 'Week before';
    final latest = dated ? '${weekLabels[2]}\nLatest week' : 'Last full week';
    return Column(
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(
            horizontalInside: BorderSide(color: Color(0xFFE6EBE6)),
          ),
          children: [
            TableRow(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Crop'),
                ),
                Text(
                  earlier,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: InsightColors.muted,
                    fontSize: 12,
                  ),
                ),
                Text(
                  latest,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: InsightColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            for (final entry in _showAll ? entries : entries.take(4))
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                      _displayLabel(entry['crop'] as String),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    format((entry['count'] as int) - (entry['change'] as int)),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    format(entry['count'] as int),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (entries.length > 4)
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(
              _showAll
                  ? 'Show fewer crops'
                  : 'Show all ${entries.length} crops',
            ),
          ),
      ],
    );
  }
}

class _PredictionTile extends StatelessWidget {
  const _PredictionTile({super.key, required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scores = row['scores'] as Map;
    final change = (scores['trend'] as num).toDouble();
    final arrow = change > 0.000001
        ? Icons.arrow_upward
        : change < -0.000001
        ? Icons.arrow_downward
        : Icons.remove;
    final trend = change > 0.000001
        ? 'Rising'
        : change < -0.000001
        ? 'Falling'
        : 'Steady';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: InsightColors.canvas,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _displayLabel(row['crop'] as String),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const ExcludeSemantics(
                      child: Icon(Icons.chevron_right, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _predictionSignal(row['confidence']),
                  style: const TextStyle(color: InsightColors.muted),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ExcludeSemantics(child: Icon(arrow, size: 16)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        trend,
                        style: const TextStyle(color: InsightColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _predictionSignal(Object? confidence) => switch (confidence) {
  'High' => 'Often searched this time of year',
  'Medium' => 'Searched around this time before',
  _ => 'Searched more often recently',
};

String _predictionExplanation(Object? confidence) => switch (confidence) {
  'High' =>
    'People searched for this crop around this time in past years, and it is showing up in recent searches too.',
  'Medium' =>
    'People looked for this crop around this time before. Recent searches suggest interest may be picking up again.',
  _ =>
    'People have recently been looking for this crop. We have only a little past search history to compare with.',
};
