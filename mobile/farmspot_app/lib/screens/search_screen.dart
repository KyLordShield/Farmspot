import 'dart:async';

import 'package:flutter/material.dart';

import '../models/crop_suggestion.dart';
import '../services/listing_service.dart';
import '../services/recent_searches.dart';
import '../theme.dart';
import 'image_search_screen.dart';
import 'search_results_screen.dart';

/// Screen 1 of the search flow: a full-screen search entry experience, now
/// wired to live data.
///
/// - Suggestions: as the buyer types, a 450ms debounce fires
///   ListingService.fetchSuggestions(), which queries the SAME /listings search
///   endpoint with ?suggest=1. The backend treats each request as a pure
///   suggestion probe and SKIPS the search_log insert — keystroke noise never
///   reaches the Top Searched analytics.
/// - Recents: the last few REAL submitted terms, stored on-device only via
///   shared_preferences (capped, deduped, most recent first). Purely local —
///   never touches search_log.
/// - Submit: navigating to SearchResultsScreen passes the RAW term; that screen
///   reuses the existing /listings search (no ?suggest=1), so the real search
///   is logged exactly as it always was.
///
/// The loader/storage callbacks are injectable for tests (MapScreen pattern).
class SearchScreen extends StatefulWidget {
  final Future<List<CropSuggestion>> Function(String term) loadSuggestions;
  final Future<List<String>> Function() loadRecents;
  final Future<void> Function(String term) saveRecent;

  const SearchScreen({
    super.key,
    this.loadSuggestions = ListingService.fetchSuggestions,
    this.loadRecents = RecentSearches.load,
    this.saveRecent = RecentSearches.add,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  bool _showSuggestions = false;
  List<String> _recents = const [];
  List<CropSuggestion> _suggestions = const [];
  bool _suggestionsLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final recents = await widget.loadRecents();
    if (!mounted) return;
    setState(() => _recents = recents);
  }

  void _onChanged(String text) {
    final term = text.trim();
    _debounce?.cancel();

    if (term.isEmpty) {
      setState(() {
        _showSuggestions = false;
        _suggestions = const [];
        _suggestionsLoading = false;
      });
      return;
    }

    setState(() => _showSuggestions = true);
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _fetchSuggestions(term),
    );
  }

  Future<void> _fetchSuggestions(String term) async {
    setState(() => _suggestionsLoading = true);
    List<CropSuggestion> results;
    try {
      results = await widget.loadSuggestions(term);
    } catch (_) {
      // Suggestions are best-effort; a failure just yields an empty list
      // (the buyer can still submit and get real results).
      results = const [];
    }
    if (!mounted) return;
    if (_controller.text.trim().toLowerCase() != term.toLowerCase()) {
      return; // stale response for a term the buyer already changed.
    }
    setState(() {
      _suggestions = results;
      _suggestionsLoading = false;
    });
  }

  /// Submits a real search: saves the term to local recents, then opens the
  /// real results screen (whose /listings call logs the search as before).
  void _submitSearch(String term) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;

    _debounce?.cancel();
    // Local device storage only — never touches search_log/analytics.
    widget.saveRecent(trimmed);
    if (mounted) {
      setState(() => _recents = _prependRecent(_recents, trimmed));
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(query: trimmed),
      ),
    );
  }

  List<String> _prependRecent(List<String> current, String term) {
    final updated = List<String>.of(current)
      ..removeWhere((e) => e.toLowerCase() == term.toLowerCase())
      ..insert(0, term);
    if (updated.length > RecentSearches.maxEntries) {
      updated.removeRange(RecentSearches.maxEntries, updated.length);
    }
    return updated;
  }

  void _openImageSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ImageSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: _showSuggestions
                    ? _buildSuggestions()
                    : _buildRecent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            color: Colors.black87,
            tooltip: 'Back',
          ),
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.fieldBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.black45),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onChanged,
                      onSubmitted: _submitSearch,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search crops or farms',
                        hintStyle:
                            TextStyle(color: Colors.black45, fontSize: 14),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _openImageSearch,
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('RECENT SEARCHES'),
        const SizedBox(height: 8),
        if (_recents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Your recent searches will appear here.',
              style: TextStyle(color: Colors.black45, fontSize: 14),
            ),
          )
        else
          ..._recents.map(
            (term) => _RecentRow(
              term: term,
              onTap: () => _submitSearch(term),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('SUGGESTIONS'),
        const SizedBox(height: 8),
        if (_suggestionsLoading)
          const _StatusRow(
            icon: Icons.search,
            text: 'Searching crops\u2026',
            loading: true,
          )
        else if (_suggestions.isEmpty)
          const _StatusRow(
            icon: Icons.search_off,
            text: 'No matching crops yet.',
          )
        else
          ..._suggestions.map(
            (s) => _SuggestionRow(
              head: _capitalize(s.name),
              subtitle: '${s.count} '
                  '${s.count == 1 ? 'farm' : 'farms'} selling nearby',
              onTap: () => _submitSearch(s.name),
            ),
          ),
      ],
    );
  }

  String _capitalize(String value) => value.isEmpty
      ? value
      : value[0].toUpperCase() + value.substring(1);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.black45,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// A muted single-line row used for transient suggestion states (searching,
/// no matches).
class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool loading;

  const _StatusRow({
    required this.icon,
    required this.text,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 18, color: AppColors.mutedGreen),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(color: Colors.black45, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// A tappable "recent search" row: small clock icon, term, chevron.
class _RecentRow extends StatelessWidget {
  final String term;
  final VoidCallback onTap;

  const _RecentRow({required this.term, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.history, size: 18, color: Colors.black38),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  term,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A live suggestion row: bold leading crop name, muted "N farms selling
/// nearby" line beneath, then a chevron.
class _SuggestionRow extends StatelessWidget {
  final String head;
  final String? subtitle;
  final VoidCallback onTap;

  const _SuggestionRow({
    required this.head,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18, color: AppColors.mutedGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      head,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.mutedGreen,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}