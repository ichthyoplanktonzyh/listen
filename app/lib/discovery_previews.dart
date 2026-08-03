import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'controllers/discovery_view_model.dart';
import 'data/repositories/discovery_repository.dart';
import 'screens/discovery_home_screen.dart';
import 'widgets/discovery/discovery_preview_shell.dart';

/// Full-home preview for the widget previewer. Lives at the app root rather
/// than under `screens/` so presentation stays free of repository and
/// ViewModel construction.
@Preview(name: 'Discovery home', group: 'Discovery', size: Size(1280, 800))
Widget discoveryHomePreview() {
  final viewModel = DiscoveryViewModel(FixtureDiscoveryRepository())..load();
  return discoveryPreviewShell(
    DiscoveryHome(
      viewModel: viewModel,
      onOpenMedia: _noop,
      onOpenSettings: _noop,
      onOpenClassicHome: _noop,
    ),
    width: 1280,
    height: 800,
  );
}

void _noop() {}
