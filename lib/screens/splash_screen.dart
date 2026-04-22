import 'dart:io';

import 'package:flutter/material.dart';

import '../services/company_profile_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final CompanyProfileService _companyProfileService = CompanyProfileService();
  CompanyProfile _profile = const CompanyProfile(name: '', logoPath: null);

  double _fadeValue = 0;
  double _logoScale = 0.9;

  @override
  void initState() {
    super.initState();
    _startAnimation();
    _loadProfileAndContinue();
  }

  void _startAnimation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fadeValue = 1;
        _logoScale = 1;
      });
    });
  }

  Future<void> _loadProfileAndContinue() async {
    final profile = await _companyProfileService.loadProfile();
    if (!mounted) {
      return;
    }

    setState(() {
      _profile = profile;
    });

    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => widget.child));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = _profile.name.trim().isEmpty
        ? 'Balance Desk'
        : _profile.name.trim();
    final logoFile =
        _profile.logoPath == null || _profile.logoPath!.trim().isEmpty
        ? null
        : File(_profile.logoPath!);
    final hasLogo = logoFile != null && logoFile.existsSync();

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colorScheme.primary.withValues(alpha: 0.12),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOut,
            opacity: _fadeValue,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AnimatedScale(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutBack,
                  scale: _logoScale,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.18),
                          blurRadius: 36,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          foregroundColor: colorScheme.primary,
                          backgroundImage: hasLogo ? FileImage(logoFile) : null,
                          child: hasLogo
                              ? null
                              : Icon(
                                  Icons.business_outlined,
                                  size: 36,
                                  color: colorScheme.primary,
                                ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          displayName,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Accounting Workspace',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
