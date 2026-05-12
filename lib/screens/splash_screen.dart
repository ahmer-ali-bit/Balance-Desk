import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/company_profile_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  final CompanyProfileService _companyProfileService = CompanyProfileService();
  CompanyProfile _profile = const CompanyProfile(name: '', logoPath: null);

  late AnimationController _mainController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadProfileAndContinue();
  }

  void _setupAnimations() {
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.1).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_mainController);

    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)),
    );

    _mainController.forward();
  }

  Future<void> _loadProfileAndContinue() async {
    final profile = await _companyProfileService.loadProfile();
    if (!mounted) return;

    setState(() {
      _profile = profile;
    });

    await Future.delayed(const Duration(milliseconds: 3200));
    if (!mounted) return;

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => widget.child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = _profile.name.trim().isEmpty ? 'Balance Desk' : _profile.name.trim();
    final logoFile = _profile.logoPath == null || _profile.logoPath!.trim().isEmpty ? null : File(_profile.logoPath!);
    final hasLogo = logoFile != null && logoFile.existsSync();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // Elegant Animated Gradient Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.08),
                    colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
          
          // Floating Abstract Shapes
          ...List.generate(3, (index) {
            return _PositionedMovingShape(
              color: colorScheme.primary.withValues(alpha: 0.03),
              index: index,
            );
          }),

          // Center Content
          Center(
            child: AnimatedBuilder(
              animation: _mainController,
              builder: (context, child) {
                return Opacity(
                  opacity: _opacityAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated Pulse Logo
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Pulse Effect
                            ...List.generate(2, (i) {
                              final delay = i * 0.5;
                              final progress = (_mainController.value - delay).clamp(0.0, 1.0);
                              return Opacity(
                                opacity: (1.0 - progress) * 0.3,
                                child: Container(
                                  width: 140 + (progress * 100),
                                  height: 140 + (progress * 100),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colorScheme.primary, width: 2),
                                  ),
                                ),
                              );
                            }),
                            
                            // Logo Card
                            Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.primary.withValues(alpha: 0.2),
                                  width: 4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withValues(alpha: 0.15),
                                    blurRadius: 30,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: hasLogo
                                    ? Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Image.file(logoFile, fit: BoxFit.contain),
                                      )
                                    : Icon(Icons.account_balance_rounded, size: 50, color: colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),

                        // Title with Spacing and Alignment
                        Text(
                          displayName.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Premium Subtitle Tag
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'PREMIUM ACCOUNTING',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3.0,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 64),
                        
                        // Centered Progress Indicator
                        Column(
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'SYNCHRONIZING...',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Clean Developer Branding
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 45),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DEVELOPED BY AHMER ABID',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0D1B2A), // Dark Navy Blue
                      fontSize: 10,
                      shadows: [
                        Shadow(
                          color: colorScheme.primary.withValues(alpha: 0.15),
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'DESIGNED FOR PRECISION',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 3.0,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionedMovingShape extends StatefulWidget {
  const _PositionedMovingShape({required this.color, required this.index});
  final Color color;
  final int index;

  @override
  State<_PositionedMovingShape> createState() => _PositionedMovingShapeState();
}

class _PositionedMovingShapeState extends State<_PositionedMovingShape> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 10 + (widget.index * 2)),
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = (_controller.value * 2 * math.pi) + (widget.index * 1.5);
        return Positioned(
          left: (math.cos(angle) * 100) + (MediaQuery.of(context).size.width / 2) - 100,
          top: (math.sin(angle) * 100) + (MediaQuery.of(context).size.height / 2) - 100,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}
