/// One live "as you type" suggestion for the Search screen: a real crop name
/// that exists in the feed, plus how many nearby listings currently carry it.
/// Built inside ListingService.fetchSuggestions() from the /listings response
/// (requested with ?suggest=1 so keystrokes never hit search_log).
class CropSuggestion {
  final String name;
  final int count;

  const CropSuggestion({required this.name, required this.count});
}