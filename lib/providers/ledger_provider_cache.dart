import '../models/customer.dart';
import 'ledger_provider.dart';

/// Caches [LedgerProvider] instances by customer ID so that reopening a
/// customer's ledger reuses the existing provider instead of re-querying
/// the database on every navigation.
class LedgerProviderCache {
  LedgerProviderCache._();

  static final LedgerProviderCache instance = LedgerProviderCache._();

  final Map<int, LedgerProvider> _providers = <int, LedgerProvider>{};

  LedgerProvider providerFor({
    required Customer customer,
    bool forceRefresh = false,
  }) {
    final id = customer.id!;

    final provider = _providers.putIfAbsent(
      id,
      () => LedgerProvider(customer: customer)..loadEntries(),
    );

    if (forceRefresh) {
      provider.loadEntries();
    }

    return provider;
  }

  /// Disposes and removes the cached provider for [customerId].
  void disposeFor(int customerId) {
    final provider = _providers.remove(customerId);
    provider?.dispose();
  }

  /// Disposes all cached providers.
  void disposeAll() {
    for (final provider in _providers.values) {
      provider.dispose();
    }
    _providers.clear();
  }
}
