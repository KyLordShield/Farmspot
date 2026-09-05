import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../home_screen.dart';

class FarmLiveScreen extends StatelessWidget {
  final String cropName;
  const FarmLiveScreen({super.key, required this.cropName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: const Column(
                children: [
                  Icon(Icons.celebration, color: Colors.white, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Farm is Live!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Belle Mariano · farm location',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const Text(
                    'YOUR FIRST LISTING',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.green.shade50,
                          child: const Icon(Icons.eco, color: Colors.green),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cropName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Text(
                              'Available Now',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "WHAT'S NEXT",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _bullet(
                    Icons.location_on,
                    "You're on the map. Buyers can now see your farm pin and listings.",
                  ),
                  const SizedBox(height: 10),
                  _bullet(
                    Icons.add_circle_outline,
                    'Add more crops anytime from the My Farm tab.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('GO to My Farm'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.primaryGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ),
      ],
    );
  }
}
