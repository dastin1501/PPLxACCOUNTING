import 'package:flutter/material.dart';

import '../services/sheet_sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'home_screen.dart';
import 'returns_screen.dart';
import 'sales_history_screen.dart';
import 'sell_screen.dart';

/// Top-level navigation shell: lets the cashier switch between the POS
/// checkout ("Sell"), stock management ("Inventory"), and the read-only
/// "Sales" history log.
///
/// Uses a side [NavigationRail] on wide/tablet-landscape screens and a
/// bottom [NavigationBar] on narrower/portrait screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  final _sellKey = GlobalKey<SellScreenState>();
  final _inventoryKey = GlobalKey<HomeScreenState>();
  final _salesHistoryKey = GlobalKey<SalesHistoryScreenState>();
  final _returnsKey = GlobalKey<ReturnsScreenState>();

  void _onSaleCompleted() {
    _inventoryKey.currentState?.refresh();
    _salesHistoryKey.currentState?.refresh();
    _backgroundSync();
  }

  /// Uploads anything still waiting, when a sheet is configured. Failures
  /// stay queued for the next attempt and do not interrupt a sale.
  Future<void> _backgroundSync() async {
    final result = await SheetSyncService.instance.syncIfConfigured();
    if (!mounted || result == null || !result.ok || result.importedVariants == 0) return;
    _inventoryKey.currentState?.refresh();
    _sellKey.currentState?.refresh();
  }

  void _onSaleDeleted() {
    _inventoryKey.currentState?.refresh();
    _sellKey.currentState?.refresh();
    _returnsKey.currentState?.refresh();
  }

  void _onDestinationSelected(int index) {
    setState(() => _index = index);
    // Refresh whichever tab we're switching into, since other tabs may
    // have changed stock quantities or added/edited items in the meantime.
    switch (index) {
      case 0:
        _sellKey.currentState?.refresh();
      case 1:
        _inventoryKey.currentState?.refresh();
      case 2:
        _salesHistoryKey.currentState?.refresh();
        _backgroundSync();
      case 3:
        _returnsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      SellScreen(key: _sellKey, onSaleCompleted: _onSaleCompleted),
      HomeScreen(key: _inventoryKey),
      SalesHistoryScreen(key: _salesHistoryKey, onSaleDeleted: _onSaleDeleted),
      ReturnsScreen(key: _returnsKey),
    ];

    const destinations = [
      (icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, label: 'Sell'),
      (icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'Inventory'),
      (icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: 'Sales'),
      (icon: Icons.undo_outlined, selectedIcon: Icons.undo, label: 'Returns'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final body = IndexedStack(index: _index, children: screens);

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _onDestinationSelected,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 84,
                  leading: const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 20),
                    child: _ShopMark(),
                  ),
                  trailing: const Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: _ThemeToggle(),
                      ),
                    ),
                  ),
                  destinations: destinations
                      .map(
                        (d) => NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                      )
                      .toList(),
                ),
                VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: Row(
            children: [
              Expanded(
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _onDestinationSelected,
                  destinations: destinations
                      .map(
                        (d) => NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: d.label,
                        ),
                      )
                      .toList(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: _ThemeToggle(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small wordmark at the top of the side rail.
class _ShopMark extends StatelessWidget {
  const _ShopMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.pplGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'PPL',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onRail = MediaQuery.sizeOf(context).width >= 900;
    return IconButton(
      tooltip: dark ? 'Light mode' : 'Dark mode',
      color: onRail ? const Color(0xFFF5F5F5) : Theme.of(context).colorScheme.onSurface,
      onPressed: ThemeController.instance.toggle,
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}
