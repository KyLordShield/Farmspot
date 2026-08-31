import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';

class ProductDetailScreen extends StatelessWidget {
  final CropListing listing;
  const ProductDetailScreen({super.key, required this.listing});

  Future<void> _callSeller() async {
    final uri = Uri(scheme: 'tel', path: listing.contactNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _smsSeller() async {
    final uri = Uri(scheme: 'sms', path: listing.contactNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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
                    const Text(
                      'Crop name:',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          listing.cropType,
                          style: const TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('•', style: TextStyle(color: Colors.black45)),
                        ),
                        Text(
                          listing.farmName,
                          style: const TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('Posted ', style: TextStyle(color: Colors.black54)),
                        Text(
                          listing.postedLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('•', style: TextStyle(color: Colors.black45)),
                        ),
                        const Text('expires in ', style: TextStyle(color: Colors.black54)),
                        Text(
                          listing.expiresLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primaryGreen, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          listing.barangay,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 16),
                        Text(listing.sitio, style: const TextStyle(color: Colors.black54)),
                      ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.fieldBorder),
            ),
            // Swap this Icon for Image.network(...) / Image.asset(...) later.
            child: Icon(
              listing.placeholderIcon,
              size: 90,
              color: AppColors.primaryGreen,
            ),
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
