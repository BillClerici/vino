import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config/theme.dart';
import 'core/auth/auth_provider.dart';
import 'core/widgets/vino_scaffold.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/explore/screens/explore_screen.dart';
import 'features/explore/screens/place_detail_screen.dart';
import 'features/palate/screens/palate_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/subscription/screens/subscription_screen.dart';
import 'features/trips/screens/live_trip_screen.dart';
import 'features/trips/screens/trip_create_screen.dart';
import 'features/trips/screens/trip_detail_screen.dart';
import 'features/trips/screens/trip_recap_screen.dart';
import 'features/trips/screens/wishlist_screen.dart';
import 'features/trips/screens/trip_stop_detail_screen.dart';
import 'features/trips/screens/trips_screen.dart';
import 'features/help/screens/getting_started_screen.dart';
import 'features/help/screens/help_article_screen.dart';
import 'features/help/screens/help_index_screen.dart';
import 'features/visits/screens/checkin_screen.dart';
import 'features/visits/screens/visit_detail_screen.dart';
import 'features/visits/screens/visits_screen.dart';

/// Listenable that notifies GoRouter when auth state changes.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
}

final _authNotifierProvider = Provider<_AuthNotifier>((ref) {
  return _AuthNotifier(ref);
});

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.read(_authNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoading = authState.isLoading;
      final hasError = authState.hasError;
      final isLoggedIn = authState.valueOrNull != null;
      final isLoginRoute = state.matchedLocation == '/login';

      // Don't redirect while auth is loading
      if (isLoading) return null;

      // Stay on login if there's an error (so user can see it)
      if (hasError && isLoginRoute) return null;

      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return _ShellWithNav(
            location: state.matchedLocation,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/explore',
            builder: (_, __) => const ExploreScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => PlaceDetailScreen(
                    placeId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/trips',
            builder: (_, __) => const TripsScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, __) => const TripCreateScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => TripDetailScreen(
                    tripId: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'live',
                    builder: (_, state) => LiveTripScreen(
                        tripId: state.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'recap',
                    builder: (_, state) => TripRecapScreen(
                        tripId: state.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'stop/:stopIndex',
                    builder: (_, state) => TripStopDetailScreen(
                      tripId: state.pathParameters['id']!,
                      stopIndex: int.parse(state.pathParameters['stopIndex']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/visits',
            builder: (_, __) => const VisitsScreen(),
            routes: [
              GoRoute(
                path: 'checkin',
                builder: (_, state) => CheckinScreen(
                    placeId: state.uri.queryParameters['place']),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => VisitDetailScreen(
                    visitId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'palate',
                builder: (_, __) => const PalateScreen(),
              ),
              GoRoute(
                path: 'wishlist',
                builder: (_, __) => const WishlistScreen(),
              ),
              GoRoute(
                path: 'subscription',
                builder: (_, __) => const SubscriptionScreen(),
              ),
              GoRoute(
                path: 'help',
                builder: (_, __) => const HelpIndexScreen(),
                routes: [
                  GoRoute(
                    path: 'getting-started',
                    builder: (_, __) => const GettingStartedScreen(),
                  ),
                  GoRoute(
                    path: ':articleId',
                    builder: (_, state) => HelpArticleScreen(
                        articleId: state.pathParameters['articleId']!),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Shell widget that wraps tab content with a bottom NavigationBar.
class _ShellWithNav extends StatelessWidget {
  final String location;
  final Widget child;

  const _ShellWithNav({required this.location, required this.child});

  @override
  Widget build(BuildContext context) {
    final index = _tabIndex(location);
    return VinoScaffold(
      currentIndex: index,
      onTabChanged: (i) {
        const paths = [
          '/dashboard',
          '/explore',
          '/trips',
          '/visits',
          '/profile',
        ];
        GoRouter.of(context).go(paths[i]);
      },
      child: child,
    );
  }

  int _tabIndex(String loc) {
    if (loc.startsWith('/dashboard')) return 0;
    if (loc.startsWith('/explore')) return 1;
    if (loc.startsWith('/trips')) return 2;
    if (loc.startsWith('/visits')) return 3;
    if (loc.startsWith('/profile')) return 4;
    return 0;
  }
}

class VinoApp extends ConsumerWidget {
  const VinoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Trip Me',
      theme: VinoTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
