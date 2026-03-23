import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    if (authState.isLoading) {
      return const _LoadingScreen();
    }

    return _LoginBody(
      hasError: authState.hasError,
      errorText: authState.hasError ? '${authState.error}' : null,
      onGoogle: () => ref.read(authStateProvider.notifier).signInWithGoogle(),
      onMicrosoft: () => ref.read(authStateProvider.notifier).signInWithMicrosoft(),
      onDevLogin: kDebugMode
          ? () => ref.read(authStateProvider.notifier).devLogin()
          : null,
    );
  }
}

// ── Loading Screen ──────────────────────────────────────────────

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2C3E50), Color(0xFF1A1D23)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, size: 60, color: Colors.white),
              const SizedBox(height: 16),
              const Text('Trip Me',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              const CircularProgressIndicator(color: Color(0xFF5DADE2)),
              const SizedBox(height: 16),
              Text('Signing in...',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Login Body ──────────────────────────────────────────────────

class _LoginBody extends StatefulWidget {
  final bool hasError;
  final String? errorText;
  final VoidCallback onGoogle;
  final VoidCallback onMicrosoft;
  final VoidCallback? onDevLogin;

  const _LoginBody({
    required this.hasError,
    this.errorText,
    required this.onGoogle,
    required this.onMicrosoft,
    this.onDevLogin,
  });

  @override
  State<_LoginBody> createState() => _LoginBodyState();
}

class _LoginBodyState extends State<_LoginBody> with TickerProviderStateMixin {
  late final AnimationController _fadeCtl;
  late final AnimationController _floatCtl;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _fadeCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _floatCtl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

    _fadeIn = CurvedAnimation(parent: _fadeCtl, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _fadeCtl, curve: Curves.easeOutCubic));

    _fadeCtl.forward();
  }

  @override
  void dispose() {
    _fadeCtl.dispose();
    _floatCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.4, 1.0],
            colors: [
              Color(0xFF2C3E50),
              Color(0xFF34495E),
              Color(0xFFF8F9FA),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: SizedBox(
              height: size.height - MediaQuery.of(context).padding.top,
              child: Column(
                children: [
                  // ── Top section: brand + floating icons ──
                  Expanded(
                    flex: 5,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Floating background icons
                        ..._buildFloatingIcons(),

                        // Brand
                        FadeTransition(
                          opacity: _fadeIn,
                          child: SlideTransition(
                            position: _slideUp,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Logo
                                Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.location_on, size: 48, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Trip Me',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Your Trip Companion',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 16,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // Feature pills
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _FeaturePill(icon: Icons.auto_awesome, label: 'AI Planning'),
                                    _FeaturePill(icon: Icons.wine_bar, label: 'Wine & Beer'),
                                    _FeaturePill(icon: Icons.route, label: 'Trip Routes'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Bottom section: sign-in buttons ──
                  Expanded(
                    flex: 4,
                    child: FadeTransition(
                      opacity: _fadeIn,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Get Started',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2C3E50),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to plan your next adventure',
                              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 24),

                            // Google button
                            _SignInButton(
                              label: 'Continue with Google',
                              icon: Icons.g_mobiledata,
                              iconColor: Colors.red,
                              onPressed: widget.onGoogle,
                            ),
                            const SizedBox(height: 12),

                            // Microsoft button (hidden for now)
                            // _SignInButton(
                            //   label: 'Continue with Microsoft',
                            //   icon: Icons.window,
                            //   iconColor: const Color(0xFF00A4EF),
                            //   onPressed: widget.onMicrosoft,
                            // ),

                            // Dev login
                            if (widget.onDevLogin != null) ...[
                              const SizedBox(height: 20),
                              TextButton.icon(
                                onPressed: widget.onDevLogin,
                                icon: Icon(Icons.developer_mode, size: 16, color: Colors.grey[500]),
                                label: Text('Dev Login', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                              ),
                            ],

                            // Error
                            if (widget.hasError && widget.errorText != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.red[200]!),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Sign-in failed. Please try again.',
                                        style: TextStyle(color: Colors.red[700], fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFloatingIcons() {
    final icons = [
      (Icons.wine_bar, 0.15, 0.15, 0.0),
      (Icons.sports_bar, 0.8, 0.1, 0.5),
      (Icons.restaurant, 0.1, 0.55, 1.0),
      (Icons.local_bar, 0.85, 0.5, 1.5),
      (Icons.map, 0.5, 0.05, 2.0),
      (Icons.star, 0.25, 0.65, 0.8),
      (Icons.favorite, 0.75, 0.65, 1.2),
    ];

    return icons.map((data) {
      final (icon, xFrac, yFrac, delay) = data;
      return Positioned(
        left: MediaQuery.of(context).size.width * xFrac - 12,
        top: 50 + (MediaQuery.of(context).size.height * 0.4 * yFrac),
        child: AnimatedBuilder(
          animation: _floatCtl,
          builder: (_, child) {
            final t = (_floatCtl.value + delay) % 1.0;
            final dy = math.sin(t * math.pi * 2) * 8;
            return Transform.translate(
              offset: Offset(0, dy),
              child: child,
            );
          },
          child: Icon(icon, size: 24, color: Colors.white.withValues(alpha: 0.12)),
        ),
      );
    }).toList();
  }
}

// ── Feature Pill ────────────────────────────────────────────────

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5DADE2)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Sign-In Button ──────────────────────────────────────────────

class _SignInButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onPressed;

  const _SignInButton({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: Colors.grey[300]!),
          backgroundColor: Colors.white,
          elevation: 1,
          shadowColor: Colors.black12,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF2C3E50))),
          ],
        ),
      ),
    );
  }
}
