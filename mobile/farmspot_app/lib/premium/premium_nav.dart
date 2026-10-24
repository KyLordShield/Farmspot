import 'package:flutter/material.dart';
import '../screens/premium/alert_settings_screen.dart';
import '../screens/premium/buy_request_form_screen.dart';
import '../screens/premium/my_requests_screen.dart';
import '../screens/premium/premium_upgrade_screen.dart';
import '../screens/premium/saved_farms_screen.dart';
import '../screens/premium/sourcing_list_screen.dart';
import '../widgets/premium_widgets.dart';
import 'premium_state.dart';

/// Opens a Premium screen, or the Upgrade screen when the user is free.
Future<void> openPremiumOrUpgrade(BuildContext context, Widget premiumScreen) {
  if (isPremium.value) {
    return pushPremiumScreen(context, premiumScreen);
  }
  return pushPremiumScreen(context, const PremiumUpgradeScreen());
}

Future<void> openBuyRequests(BuildContext context) =>
    pushPremiumScreen(context, const MyRequestsScreen());

Future<void> openNewBuyRequest(BuildContext context) =>
    openPremiumOrUpgrade(context, const BuyRequestFormScreen());

Future<void> openSavedFarms(BuildContext context) =>
    openPremiumOrUpgrade(context, const SavedFarmsScreen());

Future<void> openSourcingList(BuildContext context) =>
    openPremiumOrUpgrade(context, const SourcingListScreen());

Future<void> openAlertSettings(BuildContext context) =>
    pushPremiumScreen(context, const AlertSettingsScreen());

Future<void> openUpgrade(BuildContext context) =>
    pushPremiumScreen(context, const PremiumUpgradeScreen());
