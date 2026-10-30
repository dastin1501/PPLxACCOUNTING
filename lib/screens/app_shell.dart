import 'package:flutter/material.dart';

import '../services/sheet_sync_service.dart';
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
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.storefront,
                            size: 26,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'POS',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                        ),
                      ],
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
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
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
        );
      },
    );
  }
}
