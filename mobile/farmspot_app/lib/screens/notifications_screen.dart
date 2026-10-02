import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/listing_service.dart';
import '../services/notification_service.dart';
import '../services/session_state.dart';
import '../theme.dart';
import '../utils/notification_icons.dart';
import 'product_detail_screen.dart';
import 'profile_screen.dart';
import 'seller/my_farm_screen.dart';

/// The notification inbox: things that happened without the user asking — a
/// listing about to expire, a report answered, a seller application resolved.
///
/// Deliberately contains no chat. A message has its own endpoint, its own inbox
/// and its own unread badge on Home; folding it in here would make the bell
/// unreadable ("is that a message or a listing?").
///
/// Rows page in as the user scrolls (the server caps a page at 20), and a tap
/// marks the row read and deep-links to whatever the notification is about.
class NotificationsScreen extends StatefulWidget {
  /// Injectable for tests; the real HTTP-backed service is used when omitted.
  final NotificationsGateway? gateway;

  const NotificationsScreen({super.key, this.gateway});

  /// Key for the unread dot, used by widget tests.
  static const Key unreadDotKey = Key('notification-unread-dot');

  /// Key for the "Mark all read" action, used by widget tests.
  static const Key markAllReadKey = Key('notifications-mark-all-read');

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ScrollController _scroll = ScrollController();
  final List<AppNotification> _items = [];

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  int _page = 1;
  int _lastPage = 1;
  int _unreadCount = 0;

  NotificationsGateway get _api =>
      widget.gateway ?? NotificationService.instance;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Fetches the next page before the user reaches the bottom, so a long
  /// history never shows a hard stop. The 200px lead-in is deliberately short:
  /// the page size is 20 rows, so there is plenty of time to fetch while the
  /// last screenful is still being read.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 200) _loadMore();
  }

  /// First page, and the retry/pull-to-refresh path. Only the unread total and
  /// page window are taken from it — older pages already on screen are
  /// replaced wholesale, because a refresh is asking the server for the truth.
  Future<void> _load() async {
    try {
      final first = await _api.fetchPage(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(first.items);
        _page = 1;
        _lastPage = first.lastPage;
        _unreadCount = first.unreadCount;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _page >= _lastPage) return;

    setState(() => _loadingMore = true);
    try {
      final next = await _api.fetchPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(next.items);
        _page = next.currentPage;
        _lastPage = next.lastPage;
        // The server reports the total unread on every page, so the header
        // action cannot drift while paging.
        _unreadCount = next.unreadCount;
      });
    } catch (_) {
      // Leave the page boundary where it is. The scroll listener will try again
      // on the next flick, and pull-to-refresh always works.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Marks one row read the instant it is tapped.
  ///
  /// The local copy flips first and the request follows in the background: a
  /// tap that waits for a round trip before the row dims reads as broken on a
  /// weak connection, and the next refresh re-reads the truth either way.
  void _markRead(AppNotification notification) {
    setState(() {
      final index = _items.indexWhere((n) => n.id == notification.id);
      if (index != -1) _items[index] = _items[index].asRead();
      if (_unreadCount > 0) _unreadCount--;
    });
    unawaited(_confirmRead(notification.id));
  }

  Future<void> _confirmRead(String id) async {
    try {
      await _api.markAsRead(id);
    } catch (_) {
      // The row stays marked here until the next refresh; the server is the
      // source of truth and a retry through pull-to-refresh settles it.
    }
  }

  /// One UPDATE on the server rather than a write per visible row, so clearing
  /// a large backlog does not turn into a burst of requests on a slow phone.
  Future<void> _markAllRead() async {
    if (_unreadCount == 0) return;

    final previous = List<AppNotification>.from(_items);
    final previousUnread = _unreadCount;
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        _items[i] = _items[i].asRead();
      }
      _unreadCount = 0;
    });

    try {
      await _api.markAllAsRead();
    } catch (_) {
      if (!mounted) return;
      // Put the rows back the way they were, then tell the user — silently
      // showing everything as read when the server still disagrees would make
      // the bell wrong until the next launch.
      setState(() {
        _items
          ..clear()
          ..addAll(previous);
        _unreadCount = previousUnread;
      });
      _toast('Could not mark notifications as read.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.errorTerracotta,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Opens whatever the notification is about, then returns.
  ///
  /// The row is marked read whether or not there is anywhere to go: opening
  /// the inbox row is itself the read receipt, and refusing to clear a badge
  /// because the destination is missing would strand it forever.
  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) _markRead(notification);

    final style = notificationStyleFor(notification.type);
    if (style.target == NotificationTarget.none || !notification.hasTarget) {
      return;
    }

    switch (style.target) {
      case NotificationTarget.listing:
        await _openListing(notification.refId!);
      case NotificationTarget.profile:
        if (!mounted) return;
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      case NotificationTarget.myFarm:
        if (!mounted) return;
        // Only a seller has a My Farm to land on. A buyer who somehow receives
        // this is sent to their profile instead of a screen that would try to
        // load farms they do not have.
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionState.instance.isSeller
                ? const MyFarmScreen()
                : const ProfileScreen(),
          ),
        );
      case NotificationTarget.none:
        break;
    }
  }

  /// Resolves the LST_ID behind the notification into a listing the detail
  /// screen can render. A removed or deleted listing can legitimately fail to
  /// load, so the tap reports that instead of throwing out of the gesture.
  Future<void> _openListing(String listingId) async {
    try {
      final listing = await ListingService.fetchListing(listingId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(listing: listing.toCropListing()),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _toast('That listing is no longer available.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          // Only offered when there is something to clear: a permanently
          // visible "Mark all read" on an empty inbox is noise.
          if (_unreadCount > 0)
            TextButton(
              key: NotificationsScreen.markAllReadKey,
              onPressed: _markAllRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: AppColors.primaryGreen,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }
    if (_error != null) {
      return _Notice(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load notifications",
        subtitle: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return const _Notice(
        icon: Icons.notifications_none_rounded,
        title: 'Nothing new yet',
        subtitle:
            'Changes to your listings, harvest reminders, and updates on your '
            'seller application will show up here.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        // One extra row for the page-2 spinner, so it is never glued to the
        // bottom edge of a full page.
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          thickness: 1,
          indent: 72,
          color: Color(0xFFEEF1EC),
        ),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            );
          }
          final notification = _items[i];
          return _NotificationRow(
            notification: notification,
            onTap: () => _open(notification),
          );
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationRow({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = notificationStyleFor(notification.type);
    final unread = !notification.isRead;

    return InkWell(
      onTap: onTap,
      // A soft tint on the unread rows, so the eye can find what is new in a
      // long list without reading every line.
      child: Container(
        color: unread ? AppColors.infoSoft : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, size: 21, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _when(notification.createdAt),
                    style: const TextStyle(color: Colors.black38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (unread) ...[
              const SizedBox(width: 8),
              Container(
                key: NotificationsScreen.unreadDotKey,
                margin: const EdgeInsets.only(top: 5),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "now" / "5m" / "3h" / "Mon" / "12 Mar" — the same scale the message inbox
  /// uses, where a full timestamp is only worth the space for older rows.
  static String _when(DateTime? at) {
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return _days[at.weekday - 1];
    return '${at.day} ${_months[at.month - 1]}';
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

/// Full-screen empty / error state, matching the message inbox's treatment.
class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Notice({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

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
              child: Icon(icon, size: 38, color: AppColors.mutedGreen),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Colors.black54,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(color: AppColors.primaryGreen),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
