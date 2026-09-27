import 'package:flutter/material.dart';

import '../theme.dart';

/// Activity feed: things that happened without the user asking — a new message,
/// a listing going out of stock, a seller application being approved.
///
/// The screen is the UI only for now. Nothing feeds it yet, so it renders an
/// honest empty state instead of sample rows: showing invented notifications
/// would make a real one later look like a bug. Wiring it up needs a
/// notifications table plus an authenticated endpoint like the messaging one.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: const _EmptyNotifications(),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: AppColors.searchBackground,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 38,
                color: AppColors.mutedGreen,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nothing new yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Replies from buyers and sellers, changes to your listings, and '
              'updates on your seller application will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.mutedGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
