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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: Drawer(child: SafeArea(child: drawerChild)),
      body: SafeArea(child: content),
    );
  }
}
