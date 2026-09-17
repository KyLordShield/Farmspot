import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import 'farm_profile_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  final CropListing listing;
  const ProductDetailScreen({super.key, required this.listing});

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
  void _openFarmProfile(BuildContext context) {
    final farmId = listing.farmId;
    if (farmId == null || farmId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FarmProfileScreen(farmId: farmId),
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
              _buildImage(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            onTap: () => _openFarmProfile(context),
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
                      onTap: () => _openFarmProfile(context),
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

  Widget _buildImage() {
    // The authoritative gallery is the listing's `photos` array; `image` is
    // just the primary photo's URL. Legacy rows only have `image`, so it's
    // folded in as a single slide when the photos array lacks it — that keeps
    // every listing showing something while avoiding a duplicate primary slide.
    final single = listing.imageUrl;
    final photos =
        listing.photoUrls.where((u) => u.trim().isNotEmpty).toList();
    final galleryUrls = <String>[
      if (single != null && single.trim().isNotEmpty && !photos.contains(single))
        single,
      ...photos,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: 220,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.fieldBorder),
            ),
            child: galleryUrls.isEmpty
                ? Icon(
                    listing.placeholderIcon,
                    size: 90,
                    color: AppColors.primaryGreen,
                  )
                : galleryUrls.length == 1
                    ? Image.network(
                        galleryUrls.first,
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          listing.placeholderIcon,
                          size: 90,
                          color: AppColors.primaryGreen,
                        ),
                      )
                    : _PhotoGallery(urls: galleryUrls),
          ),
          Positioned(
            right: 14,
            bottom: 14,
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
    );
  }
}

/// Swipeable photo gallery used when a listing has more than one photo. Shows
/// a "n / N" counter in the top-right corner and dot indicators centered along
/// the bottom that track the current page.
class _PhotoGallery extends StatefulWidget {
  final List<String> urls;

  const _PhotoGallery({required this.urls});

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.urls.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: count,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => Image.network(
            widget.urls[i],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: Colors.grey,
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_index + 1} / $count',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        i == _index ? Colors.white : Colors.white.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
