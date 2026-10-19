import 'dart:io';

final class SmokeLaunchConfiguration {
  const SmokeLaunchConfiguration({
    required this.mediaPath,
    this.primarySubtitlePath,
    this.secondarySubtitlePath,
  });

  final String mediaPath;
  final String? primarySubtitlePath;
  final String? secondarySubtitlePath;
}

abstract interface class SmokeLaunchConfigurationService {
  SmokeLaunchConfiguration? read();
}

final class EnvironmentSmokeLaunchConfigurationService
    implements SmokeLaunchConfigurationService {
  const EnvironmentSmokeLaunchConfigurationService();

  @override
  SmokeLaunchConfiguration? read() =>
      smokeLaunchConfigurationFrom(Platform.environment);
}

SmokeLaunchConfiguration? smokeLaunchConfigurationFrom(
  Map<String, String> environment,
) {
  final media = environment['LLPLAYERNEXT_SMOKE_MEDIA'];
  if (media == null || media.isEmpty) return null;
  return SmokeLaunchConfiguration(
    mediaPath: media,
    primarySubtitlePath: environment['LLPLAYERNEXT_SMOKE_SUBTITLE'],
    secondarySubtitlePath: environment['LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE'],
  );
}
