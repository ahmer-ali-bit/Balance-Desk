import 'dart:io';

import 'package:flutter/material.dart';

import '../services/company_profile_service.dart';
import '../utils/platform_helper.dart';

/// Brand-first splash.
///
/// Always rendered on the deep-emerald identity panel (the brand is the one
/// moment that never changes with theme mode). Split layout on desktop —
/// emerald brand rail left, quiet paper welcome panel right — and a centered
/// ceremony layout on mobile.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final CompanyProfileService _companyProfileService = CompanyProfileService();
  CompanyProfile _profile = const CompanyProfile(name: '', logoPath: null);
  File? _logoFile;
  bool _hasLogo = false;

  late AnimationController _mainController;
  late Animation<double> _opacityAnimation;
  late Animation<double> _liftAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadProfileAndContinue();
  }

  void _setupAnimations() {
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _liftAnimation = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.05, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _mainController.forward();
  }

  Future<void> _loadProfileAndContinue() async {
    final profile = await _companyProfileService.loadProfile();
    if (!mounted) return;

    final logoPath = profile.logoPath?.trim();
    final logoFile =
        logoPath == null || logoPath.isEmpty ? null : File(logoPath);
    final hasLogo = logoFile != null && logoFile.existsSync();

    setState(() {
      _profile = profile;
      _logoFile = logoFile;
      _hasLogo = hasLogo;
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
    final displayName = _profile.name.trim().isEmpty
        ? 'Balance Desk'
        : _profile.name.trim();
    final width = MediaQuery.sizeOf(context).width;
    final useDesktopLayout =
        PlatformHelper.isDesktop && width >= 980;

    if (useDesktopLayout) {
      return _buildDesktopSplash(context, displayName: displayName);
    }
    return _buildMobileSplash(context, displayName: displayName);
  }

  /// Emblem shown at the ceremony size — the company's own logo when one is
  /// configured, otherwise the bundled brand mark.
  Widget _emblem({required double size, required double padding}) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xB308150F),
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.4),
          radius: 1.2,
          colors: [Color(0x408CE0B0), Color(0x0008150F)],
        ),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0x59A9F0CB), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x3D5BE0A4),
            blurRadius: 70,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: _hasLogo
            ? Image.file(_logoFile!, fit: BoxFit.contain)
            : Image.asset('assets/logo.png', fit: BoxFit.contain),
      ),
    );
  }

  Widget _entrance({required Widget child}) {
    return AnimatedBuilder(
      animation: _mainController,
      builder: (BuildContext context, Widget? _) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.translate(
            offset: Offset(0, _liftAnimation.value),
            child: child,
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Desktop — split brand rail + welcome panel
  // ─────────────────────────────────────────────────────────────
  Widget _buildDesktopSplash(
    BuildContext context, {
    required String displayName,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final panelBackground =
        isLight ? const Color(0xFFF4F5F0) : const Color(0xFF121A15);
    final inkPrimary = isLight ? const Color(0xFF182420) : const Color(0xFFE9EFEA);
    final inkMuted = isLight ? const Color(0xFF55645A) : const Color(0xFFA5B6AB);
    const brass = Color(0xFFC8A44E);
    const emerald = Color(0xFF0E5F3D);
    const mint = Color(0xFF5BE0A4);

    return Scaffold(
      backgroundColor: panelBackground,
      body: Row(
        children: <Widget>[
          // ── Brand rail ──
          Expanded(
            flex: 46,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF12402E), Color(0xFF0B241B)],
                ),
              ),
              child: CustomPaint(
                painter: const _SplashGridPainter(),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Row(
                          children: <Widget>[
                            Icon(Icons.menu_book_rounded,
                                size: 15, color: Color(0xFF7CF2B4)),
                            SizedBox(width: 8),
                            Text(
                              'BALANCE DESK',
                              style: TextStyle(
                                fontFamily: 'Lato',
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
                                color: Color(0xFFEFF6EF),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        _entrance(
                          child: _emblem(size: 148, padding: 16),
                        ),
                        const SizedBox(height: 30),
                        const Text(
                          'Every rupee,\naccounted for.',
                          style: TextStyle(
                            fontFamily: 'Lato',
                            fontSize: 37,
                            height: 1.14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.9,
                            color: Color(0xFFEFF6EF),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Customer udhaar, ledger years, daily snapshots and\nPDF statements — in one calm, professional register.',
                          style: TextStyle(
                            fontFamily: 'Lato',
                            fontSize: 13.5,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9DB8A8),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'DEVELOPED BY AHMER ABID  ·  DESIGNED FOR PRECISION',
                          style: TextStyle(
                            fontFamily: 'Lato',
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                            color: Color(0x66EFF6EF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── Welcome panel ──
          Expanded(
            flex: 54,
            child: CustomPaint(
              painter: _PaperGridPainter(isLight: isLight),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: _entrance(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'WELCOME BACK',
                              style: TextStyle(
                                fontFamily: 'Lato',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.6,
                                color: brass,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Lato',
                                fontSize: 34,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.7,
                                color: inkPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Your ledger is opening…',
                              style: TextStyle(
                                fontFamily: 'Lato',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: inkMuted,
                              ),
                            ),
                            const SizedBox(height: 26),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: SizedBox(
                                width: 240,
                                height: 3,
                                child: LinearProgressIndicator(
                                  minHeight: 3,
                                  backgroundColor: isLight
                                      ? const Color(0xFFE3E6DD)
                                      : const Color(0xFF223128),
                                  color: isLight ? emerald : mint,
                                ),
                              ),
                            ),
                            const SizedBox(height: 36),
                            Row(
                              children: <Widget>[
                                _WelcomeFeature(
                                  icon: Icons.people_alt_outlined,
                                  label: 'Customers',
                                  ink: inkMuted,
                                  isLight: isLight,
                                ),
                                const SizedBox(width: 10),
                                _WelcomeFeature(
                                  icon: Icons.menu_book_outlined,
                                  label: 'Ledger',
                                  ink: inkMuted,
                                  isLight: isLight,
                                ),
                                const SizedBox(width: 10),
                                _WelcomeFeature(
                                  icon: Icons.history_rounded,
                                  label: 'Daily logs',
                                  ink: inkMuted,
                                  isLight: isLight,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Mobile — full-viewport ceremony on the brand panel
  // ─────────────────────────────────────────────────────────────
  Widget _buildMobileSplash(
    BuildContext context, {
    required String displayName,
  }) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12402E), Color(0xFF081F16)],
          ),
        ),
        child: CustomPaint(
          painter: const _SplashGridPainter(),
          child: SafeArea(
            child: _entrance(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'BALANCE DESK',
                        style: TextStyle(
                          fontFamily: 'Lato',
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.4,
                          color: Color(0xFFEFF6EF),
                        ),
                      ),
                    ),
                    const Spacer(flex: 3),
                    _emblem(size: 118, padding: 12),
                    const SizedBox(height: 26),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 25,
                        height: 1.16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: Color(0xFFEFF6EF),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'PROFESSIONAL LEDGER & ACCOUNTING',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.6,
                        color: Color(0xFF7CF2B4),
                      ),
                    ),
                    const Spacer(flex: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        width: 168,
                        height: 2.5,
                        child: LinearProgressIndicator(
                          minHeight: 2.5,
                          backgroundColor: const Color(0x2EFFFFFF),
                          color: const Color(0xFF7CF2B4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'PREPARING YOUR WORKSPACE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.1,
                        color: Color(0x99EFF6EF),
                      ),
                    ),
                    const Spacer(flex: 2),
                    const Text(
                      'DEVELOPED BY AHMER ABID',
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: Color(0x8CEFF6EF),
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'DESIGNED FOR PRECISION',
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 7.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.4,
                        color: Color(0x40EFF6EF),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeFeature extends StatelessWidget {
  const _WelcomeFeature({
    required this.icon,
    required this.label,
    required this.ink,
    required this.isLight,
  });

  final IconData icon;
  final String label;
  final Color ink;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF18231C),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLight ? const Color(0xFFE3E6DD) : const Color(0xFF26362C),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: ink),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Diagonal ledger dot-grid for the brand panel.
class _SplashGridPainter extends CustomPainter {
  const _SplashGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7CF2B4).withValues(alpha: 0.05);
    const spacing = 24.0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SplashGridPainter oldDelegate) => false;
}

/// Whisper-quiet grid for the paper welcome panel.
class _PaperGridPainter extends CustomPainter {
  const _PaperGridPainter({required this.isLight});

  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isLight ? const Color(0xFF182420) : const Color(0xFF7CF2B4))
          .withValues(alpha: isLight ? 0.05 : 0.045);
    const spacing = 24.0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.05, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGridPainter oldDelegate) =>
      oldDelegate.isLight != isLight;
}
