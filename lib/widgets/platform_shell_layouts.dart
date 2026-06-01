import 'package:flutter/material.dart';

class DesktopLayout extends StatelessWidget {
  const DesktopLayout({
    super.key,
    required this.sidebar,
    required this.content,
  });

  final Widget sidebar;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: <Widget>[
            sidebar,
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class DesktopDrawerLayout extends StatelessWidget {
  const DesktopDrawerLayout({
    super.key,
    required this.title,
    required this.drawerChild,
    required this.content,
  });

  final String title;
  final Widget drawerChild;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      drawerScrimColor: Colors.black.withValues(alpha: 0.56),
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 0,
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: colorScheme.outline),
        ),
      ),
      drawer: Drawer(width: 304, child: SafeArea(child: drawerChild)),
      body: SafeArea(top: false, child: content),
    );
  }
}

class MobileLayout extends StatelessWidget {
  const MobileLayout({
    super.key,
    required this.title,
    required this.drawerChild,
    required this.content,
  });

  final String title;
  final Widget drawerChild;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      resizeToAvoidBottomInset: true,
      drawerScrimColor: colorScheme.primary.withValues(alpha: 0.3),
      drawer: Drawer(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
        child: SafeArea(top: false, child: drawerChild),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu_rounded, color: colorScheme.onSurface),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: SafeArea(top: false, child: content),
    );
  }
}
