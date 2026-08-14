import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the persistent sidebar (see [AppScaffold]) is expanded. Lives in
/// a provider rather than per-screen State because AppScaffold is
/// re-instantiated on every navigation — a local bool would reset to open
/// on each screen instead of remembering the user's last choice.
final sidebarOpenProvider = StateProvider<bool>((ref) => true);
