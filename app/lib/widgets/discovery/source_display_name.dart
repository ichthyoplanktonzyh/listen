import '../../controllers/discovery_view_model.dart';
import '../../localization.dart';
import '../../models/discovery.dart';

/// The user-facing name of [source], localizing the built-in imports entry
/// (its model name stays English because the controller owns it).
String sourceDisplayName(AppLocalizations l, ContentSource source) =>
    source.id == DiscoveryViewModel.customSource.id
    ? l.text('discoveryImports')
    : source.name;
