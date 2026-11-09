import '../../legal/legal.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/premium_checkout.dart';
import '../../services/premium_checkout_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/lottie_loader.dart';
import '../../theme.dart';

class PremiumCheckoutScreen extends StatefulWidget {
  final PremiumCheckoutGateway? gateway;
  final Future<bool> Function(Uri)? openCheckout;
  final Future<bool> Function()? refreshAccount;
  final Future<void> Function()? savePaymentAgreement;
  const PremiumCheckoutScreen({
    super.key,
    this.gateway,
    this.openCheckout,
    this.refreshAccount,
    this.savePaymentAgreement,
  });
  @override
  State<PremiumCheckoutScreen> createState() => _PremiumCheckoutScreenState();
}

class _PremiumCheckoutScreenState extends State<PremiumCheckoutScreen>
    with WidgetsBindingObserver {
  PremiumCheckout? _checkout;
  LegalCatalog? _legalCatalog;
  bool _paymentTermsAccepted = false;
  bool _busy = true, _opened = false, _activated = false;
  String? _error, _notice;
  PremiumCheckoutGateway get _gateway =>
      widget.gateway ?? PremiumCheckoutService.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _opened &&
        !_busy &&
        !_activated) {
      _verify();
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await _gateway.create();
      if (mounted) setState(() => _checkout = order);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    if (_busy || _checkout == null) return;
    late LegalCatalog policies;
    try {
      policies = _legalCatalog ?? await LegalService.catalog();
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not load the payment terms. Reopen the app and try again.',
        );
      return;
    }
    if (!mounted) return;
    if (policies.published && !_paymentTermsAccepted) {
      setState(
        () => _error =
            'Please review and accept the payment terms before continuing.',
      );
      return;
    }
    final uri = Uri.tryParse(_checkout!.url);
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'paymongo.com' || uri.host.endsWith('.paymongo.com'))) {
      setState(
        () => _error = 'The checkout link is invalid. Please try again later.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (policies.published) {
        if (widget.savePaymentAgreement != null)
          await widget.savePaymentAgreement!();
        else
          await LegalService.recordAccepted(policies, ['terms', 'privacy']);
      }
      final opened =
          await (widget.openCheckout?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!mounted) return;
      setState(() {
        _opened = opened;
        if (!opened) {
          _error = 'Could not open checkout. Please try again.';
        } else {
          _notice =
              'After completing payment, return here and tap Check payment.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open checkout. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || _checkout == null || _activated) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await withFarmLottieLoading(context, () async {
        final order = await _gateway.verify(_checkout!.id);
        if (!mounted) return;
        setState(() => _checkout = order);
        if (order.paid) {
          final refreshed =
              await (widget.refreshAccount?.call() ?? _refreshAccount());
          if (!refreshed) {
            throw Exception(
              'Payment confirmed. Tap Check payment again to refresh your Premium access.',
            );
          }
          if (mounted) setState(() => _activated = true);
        } else {
          setState(
            () => _notice = order.expired
                ? 'This checkout has expired. Start a new checkout below.'
                : 'Payment is not confirmed yet. Complete checkout or check again shortly.',
          );
        }
      }, message: 'Checking your payment...');
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _refreshAccount() async {
    final user = await AuthService.fetchUser();
    return user != null && user['USR_IS_PREMIUM'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final order = _checkout;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Premium checkout')),
      body: _busy && order == null
          ? const Center(
              child: FarmLottieLoading(message: 'Preparing your checkout...'),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  _activated ? Icons.check_circle : Icons.workspace_premium,
                  size: 64,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(height: 16),
                Text(
                  _activated ? 'Premium is active' : 'FarmSpot Business',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your Premium membership starts here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(height: 24),
                if (order != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            '${order.price} / one month',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'One month of access. No automatic renewal.',
                            textAlign: TextAlign.center,
                          ),
                          if (_activated && order.premiumUntil != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Access until ${order.premiumUntil!.split('T').first}',
                            ),
                            if (order.paymentReference != null) ...[
                              const SizedBox(height: 8),
                              SelectableText(
                                'Reference: ${order.paymentReference}',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_notice != null) ...[
                  Text(_notice!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                ],
                if (!_activated)
                  LegalRegistrationConsent(
                    agreementLabel:
                        'I agree to the Premium payment terms and acknowledge the Privacy Policy.',
                    onChanged: (catalog, accepted) {
                      setState(() {
                        _legalCatalog = catalog;
                        _paymentTermsAccepted = accepted;
                      });
                    },
                  ),
                if (_activated)
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Done'),
                  )
                else if (order == null || order.expired)
                  FilledButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Retry checkout'),
                  )
                else ...[
                  FilledButton(
                    onPressed: _busy || order.paid ? null : _open,
                    child: Text(
                      _opened ? 'Return to PayMongo' : 'Continue to PayMongo',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _verify,
                    child: const Text('Check payment'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Complete your payment securely with PayMongo. Premium activates once your payment is confirmed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                ],
              ],
            ),
    );
  }
}
