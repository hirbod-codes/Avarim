import 'package:avarim/components/footer/app_footer.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/localization/components/locale_switcher.dart';
import 'package:avarim/localization/locale_controller.dart';
import 'package:avarim/localization/on_boarding_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Public marketing page — no auth chrome, meant to be wrapped in
/// PublicShell at the route level, not AppShell. Only ever rendered
/// while unauthenticated: go_router's redirect immediately bounces an
/// authenticated visitor away from '/' to '/app' before this ever
/// builds, so no auth-conditional logic is needed inside here at all.
class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({super.key});

  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame — showDialog needs a Navigator/
    // Overlay above it in the tree, which isn't guaranteed to exist yet
    // synchronously inside initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptLanguage());
  }

  Future<void> _maybePromptLanguage() async {
    final alreadyChosen = await hasChosenLocale();
    if (alreadyChosen || !mounted) return;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.choose_your_language),
        content: const LocaleSwitcher(),
        actions: [
          FilledButton(
            onPressed: () async {
              // Persist whatever's currently selected — even the
              // device-derived default the switcher already shows —
              // so this dialog never asks again once dismissed.
              final locale = ref.read(localeControllerProvider);
              await ref.read(localeControllerProvider.notifier).setLocale(locale);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.$continue),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: [_HeroSection(), _HowItWorksSection(), _ContentTypesSection(), _UseCasesSection(), _FinalCtaSection(), AppFooter()]);
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Text(
                l10n.landing_page_memorize_anything,
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, letterSpacing: 2, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.landing_page_hero_title,
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(l10n.landing_page_hero_secondary, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text(l10n.landing_page_get_started_free)),
                  ),
                  OutlinedButton(
                    onPressed: () => context.go('/pricing'),
                    child: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text(l10n.landing_page_see_pricing)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  static final _steps = [
    (
      icon: Icons.upload_file_outlined,
      title: (AppLocalizations l10n) => l10n.landing_page_upload_your_content,
      description: (AppLocalizations l10n) => l10n.landing_page_upload_your_content_description,
    ),
    (
      icon: Icons.account_tree_outlined,
      title: (AppLocalizations l10n) => l10n.landing_page_organize_id_your_way,
      description: (AppLocalizations l10n) => l10n.landing_page_organize_id_your_way_description,
    ),
    (
      icon: Icons.replay_outlined,
      title: (AppLocalizations l10n) => l10n.landing_page_come_back_review,
      description: (AppLocalizations l10n) => l10n.landing_page_come_back_review_description,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Text(l10n.landing_page_how_it_works, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  final children = [for (final step in _steps) _StepCard(icon: step.icon, title: step.title(l10n), description: step.description(l10n))];
                  return isWide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: _withGaps(children, 24, horizontal: true))
                      : Column(children: _withGaps(children, 24, horizontal: false));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _StepCard({required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(description, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _ContentTypesSection extends StatelessWidget {
  const _ContentTypesSection();

  static final _types = [
    (icon: Icons.text_fields, label: (AppLocalizations l10n) => l10n.text),
    (icon: Icons.article_outlined, label: (AppLocalizations l10n) => l10n.richText),
    (icon: Icons.image_outlined, label: (AppLocalizations l10n) => l10n.images),
    (icon: Icons.audiotrack_outlined, label: (AppLocalizations l10n) => l10n.audio),
    (icon: Icons.videocam_outlined, label: (AppLocalizations l10n) => l10n.video),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Text(
                l10n.landing_page_content_type,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(l10n.landing_page_content_type_description, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 32),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  for (final type in _types)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(type.icon, color: theme.colorScheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 8),
                        Text(type.label(l10n), style: theme.textTheme.bodyMedium),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UseCasesSection extends StatelessWidget {
  const _UseCasesSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: LayoutBuilder(
            builder: (context, constraints) {
              AppLocalizations l10n = AppLocalizations.of(context)!;

              final isWide = constraints.maxWidth > 700;

              final cards = [
                _UseCaseCard(icon: Icons.translate, title: l10n.landing_page_use_case_first_title, description: l10n.landing_page_use_case_first_description),
                _UseCaseCard(
                  icon: Icons.school_outlined,
                  title: l10n.landing_page_use_case_second_title,
                  description: l10n.landing_page_use_case_second_description,
                ),
              ];

              return isWide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: _withGaps(cards, 24, horizontal: true))
                  : Column(children: _withGaps(cards, 24, horizontal: false));
            },
          ),
        ),
      ),
    );
  }
}

class _UseCaseCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _UseCaseCard({required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _FinalCtaSection extends StatelessWidget {
  const _FinalCtaSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      child: Center(
        child: Column(
          children: [
            Text(l10n.landing_page_final_cta, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(l10n.landing_page_get_started_free)),
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> _withGaps(List<Widget> children, double gap, {required bool horizontal}) {
  final result = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (horizontal) {
      result.add(Expanded(child: children[i]));
    } else {
      result.add(children[i]);
    }
    if (i < children.length - 1) {
      result.add(horizontal ? SizedBox(width: gap) : SizedBox(height: gap));
    }
  }
  return result;
}
