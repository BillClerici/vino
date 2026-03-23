import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(color: colorScheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.white, size: 28),
                      SizedBox(width: 10),
                      Text('Trip Me',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('v${const String.fromEnvironment("APP_VERSION", defaultValue: "1.0.0")}+${const String.fromEnvironment("BUILD_NUMBER", defaultValue: "local")}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                ],
              ),
            ),

            // Menu items
            const SizedBox(height: 8),
            _DrawerItem(
              icon: Icons.person,
              label: 'Profile',
              onTap: (ctx) => ctx.go('/profile'),
            ),
            _DrawerItem(
              icon: Icons.map,
              label: 'Journey Map',
              subtitle: 'Places you\'ve visited',
              onTap: (ctx) => ctx.push('/profile/history'),
            ),
            _DrawerItem(
              icon: Icons.bookmark,
              label: 'My Wishlist',
              subtitle: 'Drinks to try later',
              onTap: (ctx) => ctx.push('/profile/wishlist'),
            ),
            _DrawerItem(
              icon: Icons.inventory_2,
              label: 'My Cellar',
              subtitle: 'Drinks purchased',
              onTap: (ctx) => ctx.push('/profile/cellar'),
            ),
            _DrawerItem(
              icon: Icons.insights,
              label: 'My Palate',
              subtitle: 'My taste profile',
              onTap: (ctx) => ctx.push('/profile/palate'),
            ),
            _DrawerItem(
              icon: Icons.emoji_events,
              label: 'Achievements',
              subtitle: 'Badges & milestones',
              onTap: (ctx) => ctx.push('/profile/badges'),
            ),
            const Divider(indent: 16, endIndent: 16),
            _DrawerItem(
              icon: Icons.help_outline,
              label: 'Help & Guide',
              onTap: (ctx) => ctx.push('/profile/help'),
            ),

            // Spacer pushes logout to bottom
            const Spacer(),

            // Logout
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.logout, size: 22, color: Colors.red),
              title: const Text('Log Out', style: TextStyle(fontSize: 14, color: Colors.red)),
              dense: true,
              onTap: () async {
                final notifier = ref.read(authStateProvider.notifier);
                final navContext = context;
                Navigator.of(navContext).pop(); // close drawer
                final confirmed = await showDialog<bool>(
                  context: navContext,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Log Out?'),
                    content: const Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Log Out', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await notifier.signOut();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final void Function(BuildContext) onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(fontSize: 11, color: Colors.grey[500]))
          : null,
      dense: true,
      onTap: () {
        Navigator.of(context).pop(); // close drawer
        onTap(context);
      },
    );
  }
}
