import "package:avarim/auth/auth_controller.dart";
import "package:avarim/auth/auth_state.dart";
import "package:avarim/components/checkout/checkout_dialog.dart";
import "package:avarim/l10n/app_localizations.dart";
import "package:avarim/lib/talker.dart";
import "package:avarim/plan/all_plans_notifier.dart";
import "package:avarim/plan/models/currency_label.dart";
import "package:avarim/subscription/models/subscription.dart";
import "package:avarim/subscription/subscription_notifier.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "package:avarim/plan/models/plan.dart";
import "currency_formatter.dart";

/// Public pricing page. No auth required — this is meant to be
/// reachable by anyone, logged in or not, which is why it goes through
/// plansProvider"s plain dioProvider rather than anything auth-related.
///
/// [onSelectPlan] fires when someone taps a plan"s CTA button. Wire it
/// to whatever your app"s actual next step is — e.g. navigate to
/// /login?plan=<id> so signup can pre-select that plan, or straight to
/// checkout if the user"s already authenticated. Left as a callback
/// since that routing decision depends on your app"s flow, not
/// something this page should assume.
class PricingPage extends ConsumerStatefulWidget {
  final ValueChanged<Plan>? onSelectPlan;

  const PricingPage({super.key, this.onSelectPlan});

  @override
  ConsumerState<PricingPage> createState() => _PricingPageState();
}

class _PricingPageState extends ConsumerState<PricingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(allPlansProvider.notifier).refresh();
      final status = ref.read(authControllerProvider).status;
      await ref.read(subscriptionProvider.notifier).refresh(silentError: AuthStatus.unauthenticated == status);
    });
  }

  @override
  Widget build(BuildContext context) {
    final plansState = ref.watch(allPlansProvider);
    final subscriptionState = ref.watch(subscriptionProvider);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    if (plansState.isLoading || subscriptionState.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(48.0),
        child: const Center(child: CircularProgressIndicator()),
      );
    } else if (plansState.error != null || subscriptionState.error != null) {
      talker.error("allPlansProvider threw an error", plansState.error);
      return Padding(
        padding: const EdgeInsets.all(48.0),
        child: _RetryState(message: l10n.pricing_page_could_not_load, onRetry: () => ref.read(allPlansProvider.notifier).refresh()),
      );
    } else {
      final plans = plansState.plans;

      if (plans == null || plans.isEmpty) return _RetryState(message: l10n.pricing_page_no_plan_available);

      List<Plan> sortedPlans = List.empty(growable: true);
      try {
        for (var j = 0; j < plans.length; j++) {
          double max = 10000000;
          int? maxIndex;
          for (var i = 0; i < plans.length; i++) {
            final p = plans[i];
            if (p.price.usd < max && p.price.usd > (sortedPlans.lastOrNull?.price.usd ?? -1)) {
              max = p.price.usd;
              maxIndex = i;
            }

            if (i == plans.length - 1) {
              sortedPlans.add(plans[maxIndex!]);
            }
          }
        }
      } catch (e) {
        talker.error("sorting plans failed", e);
        sortedPlans = plans;
      }

      return Padding(
        padding: const EdgeInsets.all(48.0),
        child: _PricingContent(plans: sortedPlans, subscription: subscriptionState.subscription, onSelectPlan: widget.onSelectPlan),
      );
    }
  }
}

class _PricingContent extends StatefulWidget {
  final Subscription? subscription;
  final List<Plan> plans;
  final ValueChanged<Plan>? onSelectPlan;

  const _PricingContent({required this.plans, this.onSelectPlan, this.subscription});

  @override
  State<_PricingContent> createState() => _PricingContentState();
}

class _PricingContentState extends State<_PricingContent> {
  Currency _currency = Currency.usd;

  @override
  Widget build(BuildContext context) {
    AppLocalizations l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(l10n.pricing_page_choose_plan, style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.pricing_page_choose_plan_description, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Center(
            child: SegmentedButton<Currency>(
              segments: Currency.values.map((c) => ButtonSegment(value: c, label: Text(c.label))).toList(),
              selected: {_currency},
              onSelectionChanged: (selection) => setState(() => _currency = selection.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              if (isWide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final plan in widget.plans) ...[
                        Expanded(
                          child: _PlanCard(plan: plan, currency: _currency, subscription: widget.subscription, onSelect: widget.onSelectPlan),
                        ),
                        if (plan != widget.plans.last) const SizedBox(width: 16),
                      ],
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (final plan in widget.plans) ...[
                    _PlanCard(plan: plan, currency: _currency, subscription: widget.subscription, onSelect: widget.onSelectPlan),
                    if (plan != widget.plans.last) const SizedBox(height: 16),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Subscription? subscription;
  final Plan plan;
  final Currency currency;
  final ValueChanged<Plan>? onSelect;

  const _PlanCard({required this.plan, required this.currency, this.onSelect, this.subscription});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = plan.price;
    final privileges = plan.privileges;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    final nowTS = DateTime.now().millisecondsSinceEpoch;
    if (subscription != null && subscription!.currentPeriodEnd > nowTS) {}

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plan.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              price.isFree ? "Free" : CurrencyFormatter.format(price.forCurrency(currency), currency),
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
            _Feature(icon: Icons.folder_outlined, text: "${formatCount(privileges.categoriesPerNestedLevel)} ${l10n.categories}"),
            _Feature(icon: Icons.account_tree_outlined, text: "${formatCount(privileges.nestedLevels)} ${l10n.pricing_page_levels_of_nesting}"),
            _Feature(icon: Icons.style_outlined, text: "${formatCount(privileges.cardsPerCategory)} ${l10n.pricing_page_cards_per_category}"),
            _Feature(icon: Icons.view_agenda_outlined, text: "${formatCount(privileges.contentsPerCardSide)} ${l10n.pricing_page_contents_per_card_side}"),
            _Feature(icon: Icons.storage_outlined, text: "${formatBytes(privileges.storageBytes)} ${l10n.storage}"),
            const SizedBox(height: 12),
            Text(l10n.contentTypes, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _ContentTypeChip(label: l10n.text, enabled: privileges.allowedContentTypes.string, icon: Icons.text_fields),
                _ContentTypeChip(label: l10n.richText, enabled: privileges.allowedContentTypes.richText, icon: Icons.article_outlined),
                _ContentTypeChip(label: l10n.image, enabled: privileges.allowedContentTypes.image, icon: Icons.image_outlined),
                _ContentTypeChip(label: l10n.audio, enabled: privileges.allowedContentTypes.audio, icon: Icons.audiotrack_outlined),
                _ContentTypeChip(label: l10n.video, enabled: privileges.allowedContentTypes.video, icon: Icons.videocam_outlined),
              ],
            ),
            const SizedBox(height: 24),
            if (!price.isFree)
              FilledButton(
                onPressed: () async {
                  onSelect?.call(plan);
                  await showCheckoutDialog(context, plan: plan, subscription: subscription);
                },
                child: Text(subscription == null ? l10n.pricing_page_get_started : (subscription!.planTitle == plan.title ? l10n.renewal : l10n.upgrade)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Feature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ContentTypeChip extends StatelessWidget {
  final String label;
  final bool enabled;
  final IconData icon;

  const _ContentTypeChip({required this.label, required this.enabled, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled ? theme.colorScheme.primary : theme.disabledColor;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Chip(
        avatar: Icon(enabled ? Icons.check_circle : Icons.cancel_outlined, size: 16, color: color),
        label: Text(label, style: TextStyle(color: color)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _RetryState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _RetryState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (onRetry != null) ...[const SizedBox(height: 16), OutlinedButton(onPressed: onRetry, child: Text(l10n.tryAgain))],
          ],
        ),
      ),
    );
  }
}
