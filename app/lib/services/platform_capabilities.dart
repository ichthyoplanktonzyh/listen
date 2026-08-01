import 'dart:io';

abstract interface class PlatformCapabilities {
  bool get isMacOS;
}

final class LocalPlatformCapabilities implements PlatformCapabilities {
  const LocalPlatformCapabilities();

  @override
  bool get isMacOS => Platform.isMacOS;
}

final class PlatformPathHelper {
  const PlatformPathHelper();

  String basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    return separator < 0 ? normalized : normalized.substring(separator + 1);
  }
}
