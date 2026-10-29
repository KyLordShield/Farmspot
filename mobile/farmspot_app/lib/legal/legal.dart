import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../theme.dart';

class LegalCatalog {
  final Map<String, dynamic> data;
  LegalCatalog(this.data);
  String get version => data['version'] as String;
  bool get published =>
      data['published'] == true &&
      [
        data['operator_name'],
        data['retention_policy'],
        data['refund_policy'],
      ].every((v) => v is String && v.trim().isNotEmpty) &&
      ((data['contact_text'] is String &&
              (data['contact_text'] as String).trim().isNotEmpty) ||
          RegExp(
            r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
          ).hasMatch(data['contact_email'] as String? ?? ''));
  List<Map<String, dynamic>> get documents =>
      (data['documents'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> document(String id) =>
      documents.firstWhere((doc) => doc['id'] == id);
}

class LegalService {
  static Future<LegalCatalog>? _catalog;
  static LegalCatalog? _loaded;
  static Future<LegalCatalog> catalog() {
    final loaded = _loaded;
    if (loaded != null) return Future.value(loaded);
    return _catalog ??= rootBundle
        .loadString('assets/legal/policies.json')
        .then(
          (text) =>
              _loaded = LegalCatalog(jsonDecode(text) as Map<String, dynamic>),
        );
  }

  static Future<bool> review(
    BuildContext context,
    List<String> documents, {
    LegalCatalog? policies,
    bool requireAcceptance = false,
    String? label,
  }) async {
    try {
      final catalog = policies ?? await LegalService.catalog();
      if (!context.mounted) return false;
      return await showDialog<bool>(
            context: context,
            builder: (_) => LegalReaderDialog(
              policies: catalog,
              documents: documents,
              requireAcceptance: requireAcceptance,
              label: label,
            ),
          ) ??
          false;
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load the policies. Please try again.'),
          ),
        );
      return false;
    }
  }

  static Future<void> recordAccepted(
    LegalCatalog policies,
    List<String> documents,
  ) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Please sign in again.');
    final saved = await http
        .post(
          Uri.parse('${AuthService.baseUrl}/legal/acceptances'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'legal_version': policies.version,
            'documents': documents,
            'accepted': true,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (saved.statusCode != 200) {
      final data = jsonDecode(saved.body) as Map;
      throw Exception(
        data['message'] ?? 'Could not save your agreement. Please try again.',
      );
    }
  }

  static Future<bool> ensureAccepted(
    BuildContext context,
    List<String> documents, {
    required String label,
  }) async {
    try {
      final policies = await catalog();
      // Unfinished legal content must never become an unexpected account gate.
      if (!policies.published) return true;
      final token = await AuthService.getToken();
      if (token == null) throw Exception('Please sign in again.');
      final headers = {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/legal/acceptances'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200)
        throw Exception('Could not check your agreement. Please try again.');
      final accepted =
          ((jsonDecode(response.body) as Map)['acceptances'] as List);
      if (documents.every(
        (id) => accepted.any(
          (record) =>
              record['DOCUMENT'] == id && record['VERSION'] == policies.version,
        ),
      ))
        return true;
      if (!context.mounted) return false;
      final consent = await review(
        context,
        documents,
        policies: policies,
        requireAcceptance: true,
        label: label,
      );
      if (consent != true || !context.mounted) return false;
      await recordAccepted(policies, documents);
      return true;
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      return false;
    }
  }
}

class LegalReaderDialog extends StatefulWidget {
  final LegalCatalog policies;
  final List<String> documents;
  final bool requireAcceptance;
  final String? label;
  const LegalReaderDialog({
    super.key,
    required this.policies,
    required this.documents,
    this.requireAcceptance = false,
    this.label,
  });
  @override
  State<LegalReaderDialog> createState() => _LegalReaderDialogState();
}

class _LegalReaderDialogState extends State<LegalReaderDialog> {
  final _scroll = ScrollController();
  bool _reachedEnd = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEnd());
  }

  void _checkEnd() {
    if (!mounted || _reachedEnd || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter <= 8) setState(() => _reachedEnd = true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.documents.map(widget.policies.document).toList();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.policy_outlined,
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.requireAcceptance
                              ? 'Review before continuing'
                              : (docs.length == 1
                                    ? docs.single['title'] as String
                                    : 'Privacy & Terms'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version ${widget.policies.version}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close policies',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _checkEnd(),
                  );
                  return false;
                },
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    key: const Key('legal-reader-scroll'),
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.policies.published)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              widget.policies.data['draft_notice'] as String,
                              style: const TextStyle(color: Colors.brown),
                            ),
                          ),
                        for (final doc in docs) ...[
                          Text(
                            doc['title'] as String,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkGreen,
                            ),
                          ),
                          const SizedBox(height: 16),
                          for (final section in doc['sections'] as List)
                            LegalSection(
                              section: section as Map<String, dynamic>,
                            ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          widget.policies.data['contact_text'] as String? ??
                              widget.policies.data['contact_email']
                                  as String? ??
                              '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.5,
                          ),
                        ),
                        if (widget.label != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              widget.label!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                children: [
                  if (widget.requireAcceptance && !_reachedEnd)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Scroll to the end to enable agreement.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            widget.requireAcceptance ? 'Cancel' : 'Close',
                          ),
                        ),
                      ),
                      if (widget.requireAcceptance) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            key: const Key('legal-reader-agree'),
                            onPressed: _reachedEnd && widget.policies.published
                                ? () => Navigator.pop(context, true)
                                : null,
                            child: const Text(
                              'Agree and continue',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LegalSection extends StatelessWidget {
  final Map<String, dynamic> section;
  const LegalSection({super.key, required this.section});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section['heading'] as String,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.darkGreen,
          ),
        ),
        const SizedBox(height: 8),
        if ((section['text'] as String? ?? '').isNotEmpty)
          SelectableText(
            section['text'] as String,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF3E4D43),
            ),
          ),
        for (final point in section['points'] as List? ?? [])
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '•  ',
                  style: TextStyle(color: AppColors.primaryGreen, height: 1.6),
                ),
                Expanded(
                  child: SelectableText(
                    point as String,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Color(0xFF3E4D43),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class LegalScreen extends StatelessWidget {
  final String? documentId;
  final LegalCatalog? policies;
  const LegalScreen({super.key, this.documentId, this.policies});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F8F5),
    appBar: AppBar(title: const Text('Privacy & Terms')),
    body: FutureBuilder<LegalCatalog>(
      future: policies != null
          ? Future.value(policies)
          : LegalService.catalog(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(
            child: Text(
              'Could not load the legal pages. Please reopen this screen.',
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final catalog = snapshot.data!;
        final docs = documentId == null
            ? catalog.documents
            : [catalog.document(documentId!)];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (documentId == null) ...[
              const Text(
                'Your privacy and choices',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a policy to read. You can return here anytime.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              'Version ${catalog.version}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (!catalog.published)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  catalog.data['draft_notice'] as String,
                  style: const TextStyle(color: Colors.brown),
                ),
              ),
            for (final doc in docs) ...[
              if (documentId == null)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(top: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE0E8DE)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: const Icon(
                      Icons.description_outlined,
                      color: AppColors.primaryGreen,
                    ),
                    title: Text(
                      doc['title'] as String,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(switch (doc['id']) {
                        'terms' => 'Accounts, listings and Premium payments',
                        'privacy' =>
                          'Personal data, permissions and your choices',
                        'seller' => 'Verification and responsible selling',
                        _ => 'How verification documents are used',
                      }, style: const TextStyle(fontSize: 12, height: 1.4)),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 19),
                    onTap: () => LegalService.review(context, [
                      doc['id'] as String,
                    ], policies: catalog),
                  ),
                )
              else ...[
                Text(
                  doc['title'] as String,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                for (final section in doc['sections'] as List)
                  LegalSection(section: section as Map<String, dynamic>),
              ],
            ],
            if (catalog.published)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: SelectableText(
                  '${catalog.data['operator_name']}\n${catalog.data['contact_text'] ?? catalog.data['contact_email'] ?? ''}',
                ),
              ),
          ],
        );
      },
    ),
  );
}

class LegalLinks extends StatelessWidget {
  final List<String> ids;
  const LegalLinks({super.key, this.ids = const ['terms', 'privacy']});
  static const titles = {
    'terms': 'Terms of Service',
    'privacy': 'Privacy Policy',
    'seller': 'Seller Agreement',
    'verification': 'ID & Permit Privacy Notice',
  };
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    children: [
      for (final id in ids)
        TextButton(
          onPressed: () => LegalService.review(context, [id]),
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontSize: 12),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          child: Text(titles[id]!),
        ),
    ],
  );
}

class LegalRegistrationConsent extends StatefulWidget {
  final void Function(LegalCatalog catalog, bool accepted) onChanged;
  final LegalCatalog? policies;
  final String agreementLabel;
  final List<String> documents;
  const LegalRegistrationConsent({
    super.key,
    required this.onChanged,
    this.policies,
    this.documents = const ['terms', 'privacy'],
    this.agreementLabel =
        'I agree to the Terms of Service and acknowledge the Privacy Policy.',
  });
  @override
  State<LegalRegistrationConsent> createState() =>
      _LegalRegistrationConsentState();
}

class _LegalRegistrationConsentState extends State<LegalRegistrationConsent> {
  LegalCatalog? _policies;
  bool _accepted = false;
  bool _loadError = false;
  bool _reviewing = false;
  Future<void> _choose(bool? value) async {
    if (_reviewing || _policies == null) return;
    if (value != true) {
      setState(() => _accepted = false);
      widget.onChanged(_policies!, false);
      return;
    }
    setState(() => _reviewing = true);
    final accepted = await LegalService.review(
      context,
      widget.documents,
      policies: _policies,
      requireAcceptance: true,
      label: widget.agreementLabel,
    );
    if (!mounted) return;
    setState(() {
      _reviewing = false;
      _accepted = accepted;
    });
    widget.onChanged(_policies!, _accepted);
  }

  @override
  void initState() {
    super.initState();
    (widget.policies != null
            ? Future.value(widget.policies!)
            : LegalService.catalog())
        .then((catalog) {
          if (!mounted) return;
          setState(() => _policies = catalog);
          widget.onChanged(catalog, false);
        })
        .catchError((Object error) {
          if (mounted) setState(() => _loadError = true);
        });
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_loadError)
        const Text(
          'Could not load the legal pages. Please reopen the app.',
          style: TextStyle(color: Colors.red, fontSize: 12),
        ),
      if (_policies?.published == true)
        CheckboxListTile(
          key: const Key('registration-legal-consent'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          controlAffinity: ListTileControlAffinity.leading,
          titleAlignment: ListTileTitleAlignment.top,
          horizontalTitleGap: 6,
          visualDensity: VisualDensity.compact,
          activeColor: AppColors.primaryGreen,
          tileColor: const Color(0xFFF6F8F5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFDEE7DA)),
          ),
          value: _accepted,
          onChanged: _reviewing ? null : _choose,
          title: Text(
            widget.agreementLabel,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.darkGreen,
            ),
          ),
        )
      else
        const Text(
          'Legal pages are drafts for review; no acceptance is required yet.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
    ],
  );
}
