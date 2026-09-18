import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import 'farm_profile_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final CropListing listing;
  const ProductDetailScreen({super.key, required this.listing});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  CropListing get listing => widget.listing;

  /// Every viewable photo URL: the listing's `photos` array, with the legacy
  /// `image` (the primary thumbnail) folded in first when it's not already in
  /// that array — so every listing still has a header photo.
  List<String> get _photoUrls {
    final single = listing.imageUrl;
    final photos =
        listing.photoUrls.where((u) => u.trim().isNotEmpty).toList();
    return <String>[
      if (single != null && single.trim().isNotEmpty && !photos.contains(single))
        single,
      ...photos,
    ];
  }

  /// Single cover photo shown big at the top (the primary/thumbnail image).
  String? get _headerUrl => _photoUrls.isEmpty ? null : _photoUrls.first;

  Future<void> _callSeller() async {
    // Fire-and-forget analytics: never awaited, so the dialer opens the moment
    // this handler runs regardless of logging success/network speed.
    ListingService.logContact(
      listingId: listing.listingId ?? '',
      method: 'CALL',
    );
    final uri = Uri(scheme: 'tel', path: listing.contactNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _smsSeller() async {
    ListingService.logContact(
      listingId: listing.listingId ?? '',
      method: 'SMS',
    );
    final uri = Uri(scheme: 'sms', path: listing.contactNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Opens the farm's public profile. No-op when the listing carries no farm id
  /// (legacy rows) rather than navigating somewhere meaningless.
  void _openFarmProfile() {
    final farmId = listing.farmId;
    if (farmId == null || farmId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FarmProfileScreen(farmId: farmId),
      ),
    );
  }

  /// Opens the full-screen photo viewer starting at [index].
  void _openViewer(int index) {
    final urls = _photoUrls;
    if (urls.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullScreenPhotoViewer(
          urls: urls,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBackButton(context),
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhotoStrip(),
                    Text(
                      listing.cropName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            listing.cropType,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primaryGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('•', style: TextStyle(color: Colors.black45)),
                        ),
                        Flexible(
                          child: GestureDetector(
                            onTap: _openFarmProfile,
                            child: Text(
                              listing.farmName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('Posted ', style: TextStyle(color: Colors.black54)),
                        Flexible(
                          child: Text(
                            listing.postedLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('•', style: TextStyle(color: Colors.black45)),
                        ),
                        const Text('expires in ', style: TextStyle(color: Colors.black54)),
                        Flexible(
                          child: Text(
                            listing.expiresLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (listing.description != null &&
                        listing.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        listing.description!,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _openFarmProfile,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: AppColors.primaryGreen, size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              listing.barangay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Flexible(
                            child: Text(
                              listing.sitio,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Text(
                        listing.distance,
                        style: const TextStyle(color: Colors.black45, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, color: AppColors.primaryGreen, size: 20),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Fresh Harvest, Ready for pickup at farm',
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _callSeller,
                        icon: const Icon(Icons.call, size: 18),
                        label: Text('Call Seller  ${listing.contactNumber}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _smsSeller,
                        icon: const Icon(Icons.sms_outlined, size: 18),
                        label: const Text('Send SMS to Seller'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          side: const BorderSide(color: AppColors.primaryGreen),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: const Row(
          children: [
            Icon(Icons.arrow_back, color: AppColors.primaryGreen),
            SizedBox(width: 4),
            Text(
              'Back',
              style: TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Big single header/cover photo (the primary/thumbnail image). Tapping it
  /// opens the full-screen viewer.
  Widget _buildHeader() {
    final url = _headerUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        key: const Key('detail_hero_photo'),
        onTap: url == null ? null : () => _openViewer(0),
        child: Container(
          width: double.infinity,
          height: 240,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.fieldBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.fieldBorder),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url == null)
                Icon(
                  listing.placeholderIcon,
                  size: 90,
                  color: AppColors.primaryGreen,
                )
              else ...[
                _BoxedNetworkImage(
                  url: url,
                  fit: BoxFit.cover,
                  errorIcon: listing.placeholderIcon,
                ),
                // Soft gradient at the bottom so the status chip + hint stay
                // readable over any photo.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black38, Colors.transparent],
                      stops: [0.0, 0.55],
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 12,
                  left: 12,
                  child: _TapToViewHint(),
                ),
              ],
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    listing.status == 'P_status' ? 'Product Status' : listing.status,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal, swipeable strip of every photo thumbnail that sits between the
  /// header and the details. Hidden for single-photo listings (the header
  /// already shows the one photo). Tapping a thumbnail opens the full-screen
  /// viewer on that photo.
  Widget _buildPhotoStrip() {
    final urls = _photoUrls;
    if (urls.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'PHOTOS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Colors.black54,
                  ),
                ),
              ),
              Text(
                '${urls.length} photos • tap to view',
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 78,
            child: ListView.separated(
              key: const Key('detail_photo_strip'),
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                return _StripThumb(
                  key: ValueKey('detail_photo_thumb_$i'),
                  url: urls[i],
                  isCover: i == 0,
                  onTap: () => _openViewer(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill shown on the header photo hinting that it can be tapped to view
/// every photo full-screen.
class _TapToViewHint extends StatelessWidget {
  const _TapToViewHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fullscreen, size: 14, color: Colors.white),
          SizedBox(width: 5),
          Text(
            'Tap to view photos',
            style: TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Rounded thumbnail in the middle photo strip. The cover photo (the one shown
/// big at the top) gets a green ring so buyers know which thumbnail it matches.
class _StripThumb extends StatelessWidget {
  final String url;
  final bool isCover;
  final VoidCallback onTap;

  const _StripThumb({
    super.key,
    required this.url,
    required this.isCover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          border: Border.all(
            color: isCover ? AppColors.primaryGreen : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: _BoxedNetworkImage(
            url: url,
            fit: BoxFit.cover,
            brokenIconSize: 22,
          ),
        ),
      ),
    );
  }
}

/// Image.network wrapper that always shows a friendly loading spinner and a
/// broken-image fallback instead of crashing on a bad URL.
class _BoxedNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final IconData? errorIcon;
  final double brokenIconSize;

  const _BoxedNetworkImage({
    required this.url,
    required this.fit,
    this.errorIcon,
    this.brokenIconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: Icon(
          errorIcon ?? Icons.broken_image_outlined,
          size: brokenIconSize,
          color: errorIcon == null ? Colors.grey : AppColors.primaryGreen,
        ),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryGreen,
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen photo viewer: black background, swipeable PageView with a
/// "n / N" counter, and a close button. Opens on the photo the user tapped.
class FullScreenPhotoViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const FullScreenPhotoViewer({
    super.key,
    required this.urls,
    required this.initialIndex,
  });

  @override
  State<FullScreenPhotoViewer> createState() => _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<FullScreenPhotoViewer> {
  late final int _count = widget.urls.length;
  late int _index =
      widget.initialIndex.clamp(0, _count - 1).toInt();
  late final PageController _controller =
      PageController(initialPage: _index);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _count,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Center(
              child: _BoxedNetworkImage(
                url: widget.urls[i],
                fit: BoxFit.contain,
                brokenIconSize: 64,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_index + 1} / $_count',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    key: const Key('viewer_close'),
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_count > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: Text(
                  'Swipe to view more photos',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}