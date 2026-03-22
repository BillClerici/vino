import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../providers/subscription_provider.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subState = ref.watch(subscriptionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: subState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (status) {
          final isActive = status['has_active_subscription'] as bool? ?? false;
          final isTrialing = status['is_in_trial'] as bool? ?? false;
          final daysLeft = status['trial_days_remaining'] as int? ?? 0;
          final plan = status['subscription_plan'] as String? ?? '';
          final subStatus = status['subscription_status'] as String? ?? 'none';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Current status card
              Card(
                color: isActive
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        isActive ? Icons.check_circle : Icons.warning,
                        size: 48,
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isTrialing
                            ? 'Free Trial'
                            : subStatus.toUpperCase(),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (isTrialing)
                        Text('$daysLeft days remaining'),
                      if (plan.isNotEmpty)
                        Text('Plan: ${plan.toUpperCase()}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Plan options
              if (subStatus != 'active') ...[
                Text('Choose a Plan',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _PlanCard(
                  title: 'Monthly',
                  price: '\$9.99/mo',
                  onTap: () => _checkout(context, ref, 'monthly'),
                ),
                const SizedBox(height: 8),
                _PlanCard(
                  title: 'Yearly',
                  price: '\$79.99/yr',
                  subtitle: 'Save 33%',
                  onTap: () => _checkout(context, ref, 'yearly'),
                ),
              ],
              if (status['stripe_customer_id'] != null &&
                  (status['stripe_customer_id'] as String).isNotEmpty) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _openPortal(context, ref),
                  icon: const Icon(Icons.settings),
                  label: const Text('Manage Subscription'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkout(
      BuildContext context, WidgetRef ref, String plan) async {
    final api = ref.read(apiClientProvider);
    try {
      final resp = await api.post(ApiPaths.subscriptionCheckout, data: {
        'plan': plan,
      });
      final url = (resp.data['data'] as Map<String, dynamic>)['checkout_url'] as String;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _openPortal(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiClientProvider);
    try {
      final resp = await api.post(ApiPaths.subscriptionPortal);
      final url = (resp.data['data'] as Map<String, dynamic>)['portal_url'] as String;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String? subtitle;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ),
              Text(price,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
