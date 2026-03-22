import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../help/help_launcher.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final statsState = ref.watch(userStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [helpButton(context, routePrefix: '/profile')],
      ),
      body: authState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Error loading profile')),
        data: (user) {
          if (user == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Avatar & name
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: user.avatarUrl.isNotEmpty
                          ? NetworkImage(user.avatarUrl)
                          : null,
                      child: user.avatarUrl.isEmpty
                          ? Text(
                              user.fullName.isNotEmpty
                                  ? user.fullName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 32),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(user.fullName,
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text(user.email,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    if (user.isInTrial)
                      Chip(
                        label: Text(
                            'Free Trial - ${user.trialDaysRemaining} days left'),
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                      )
                    else
                      Chip(
                        label: Text(
                            user.subscriptionStatus.toUpperCase()),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Stats
              statsState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
                data: (stats) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Activity',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _StatTile(Icons.place, 'Visits',
                            '${stats['visit_count'] ?? 0}'),
                        _StatTile(Icons.place, 'Places Visited',
                            '${stats['places_visited'] ?? 0}'),
                        _StatTile(Icons.map, 'Trips',
                            '${stats['trips_total'] ?? 0}'),
                        _StatTile(Icons.local_drink, 'Wines Logged',
                            '${stats['wines_logged'] ?? 0}'),
                        _StatTile(Icons.favorite, 'Favorites',
                            '${stats['favorites_count'] ?? 0}'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Social accounts
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Linked Accounts',
                          style:
                              Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...user.socialAccounts.map((sa) => ListTile(
                            leading: Icon(sa.provider.contains('google')
                                ? Icons.g_mobiledata
                                : Icons.window),
                            title: Text(sa.provider),
                            contentPadding: EdgeInsets.zero,
                          )),
                      if (user.socialAccounts.isEmpty)
                        const Text('No linked accounts'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Menu links
              ListTile(
                leading: const Icon(Icons.insights),
                title: const Text('My Palate'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/palate'),
              ),
              ListTile(
                leading: const Icon(Icons.bookmark),
                title: const Text('My Wishlist'),
                subtitle: const Text('Wines to try later', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/wishlist'),
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2),
                title: const Text('My Cellar'),
                subtitle: const Text('Wines purchased', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/cellar'),
              ),
              ListTile(
                leading: const Icon(Icons.emoji_events),
                title: const Text('Achievements'),
                subtitle: const Text('Badges & milestones', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/badges'),
              ),
              ListTile(
                leading: const Icon(Icons.credit_card),
                title: const Text('Subscription'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/subscription'),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & Guide'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/help'),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.logout,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Log Out',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                onTap: () async {
                  await ref.read(authStateProvider.notifier).signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatTile(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
