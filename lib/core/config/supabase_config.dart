/// Supabase endpoint and publishable client key for Balance Desk.
///
/// The publishable/anon key is intentionally public. It grants no direct data
/// access: public tables have RLS enabled and every RPC validates a per-device
/// capability. Never add a Supabase service-role/secret key to this app.
abstract final class SupabaseConfig {
  static const String url = 'https://wljpnkcydagitqfhluog.supabase.co';
  static const String publishableKey =
      'sb_publishable_HgNJYQuAJoNE3RDihmRHJw_9F3wBim9';
}
