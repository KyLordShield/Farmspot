import 'package:flutter/material.dart';

import '../models/search_suggestions.dart';
import '../services/search_service.dart';
import '../theme.dart';
import '../widgets/lottie_loader.dart';
import '../widgets/search_widgets.dart';
import 'farm_profile_screen.dart';
import 'user_profile_screen.dart';

/// Which slice of a search term the "See all" screen lists.
enum SearchAllType { farms, sellers }

/// The full list behind a search preview's "See all": every matching farm (or
/// seller) for one term, rather than the three or four the preview caps at.
///
/// Reuses GET /api/search with a larger limit, so the preview and the full list
/// can never disagree about what matches. [load] is injectable for tests.
class SearchAllScreen extends StatefulWidget {
  final String query;
  final SearchAllType type;
  final Future<SearchSuggestions> Function(String query) load;

  const SearchAllScreen({
    super.key,
    required this.query,
    required this.type,
    this.load = _defaultLoad,
  });

  static Future<SearchSuggestions> _defaultLoad(String query) =>
      SearchService.fetchSearch(query, limit: 50);

  @override
  State<SearchAllScreen> createState() => _SearchAllScreenState();
}

class _SearchAllScreenState extends State<SearchAllScreen> {
  SearchSuggestions _suggestions = SearchSuggestions.empty;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await widget.load(widget.query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String get _title =>
      widget.type == SearchAllType.farms ? 'Farms' : 'Sellers';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '"${widget.query}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: FarmLottieLoading());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: Colors.black38),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final rows = <Widget>[];

    if (widget.type == SearchAllType.farms) {
      for (final farm in _suggestions.farms) {
        rows.add(
          FarmSearchRow(
            name: farm.name,
            barangay: farm.barangay,
            activeListingsCount: farm.activeListingsCount,
            photoUrl: farm.photoUrl,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FarmProfileScreen(farmId: farm.id),
              ),
            ),
          ),
        );
      }
    } else {
      for (final seller in _suggestions.sellers) {
        rows.add(
          SellerSearchRow(
            name: seller.name,
            farmCount: seller.farmCount,
            activeListingsCount: seller.activeListingsCount,
            photoUrl: seller.photoUrl,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(userId: seller.userId),
              ),
            ),
          ),
        );
      }
    }

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.type == SearchAllType.farms
                ? 'No farms match "${widget.query}".'
                : 'No sellers match "${widget.query}".',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: rows,
    );
  }
}
