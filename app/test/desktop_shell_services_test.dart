import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/desktop_playback_bootstrap.dart';
import 'package:llplayer_next/services/diagnostic_log_export_service.dart';
import 'package:llplayer_next/services/platform_capabilities.dart';
import 'package:llplayer_next/services/smoke_launch_configuration_service.dart';

void main() {
  test('builds the bundled desktop ffmpeg path from the executable', () {
    expect(
      bundledFfmpegPath('/Applications/listen.app/Contents/MacOS/listen'),
      '/Applications/listen.app/Contents/Frameworks/'
      'mdk.framework/Versions/A/libffmpeg.8.dylib',
    );
  });

  test('reads typed smoke launch configuration from an environment map', () {
    final configuration = smokeLaunchConfigurationFrom({
      'LLPLAYERNEXT_SMOKE_MEDIA': '/media.mp4',
      'LLPLAYERNEXT_SMOKE_SUBTITLE': '/primary.srt',
      'LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE': '/secondary.srt',
    });

    expect(configuration?.mediaPath, '/media.mp4');
    expect(configuration?.primarySubtitlePath, '/primary.srt');
    expect(configuration?.secondarySubtitlePath, '/secondary.srt');
    expect(smokeLaunchConfigurationFrom(const {}), isNull);
  });

  test('normalizes both desktop path separator styles', () {
    const helper = PlatformPathHelper();
    expect(helper.basename('/media/folder/video.mp4'), 'video.mp4');
    expect(helper.basename(r'C:\media\video.mp4'), 'video.mp4');
  });

  test('diagnostic export returns the destination and copies once', () async {
    final files = _Files(existsValue: true);
    final service = LocalDiagnosticLogExportService(
      const _Source('/logs/core.log'),
      fileService: files,
      destinationService: _Destination('/exports/core.log'),
    );

    final outcome = await service.export();

    expect(outcome, isA<DiagnosticLogExported>());
    expect((outcome as DiagnosticLogExported).path, '/exports/core.log');
    expect(files.copyArguments, ('/logs/core.log', '/exports/core.log'));
  });

  test('diagnostic export distinguishes unavailable and cancelled', () async {
    final unavailable = LocalDiagnosticLogExportService(
      const _Source('/missing.log'),
      fileService: _Files(existsValue: false),
      destinationService: _Destination('/unused.log'),
    );
    final cancelled = LocalDiagnosticLogExportService(
      const _Source('/core.log'),
      fileService: _Files(existsValue: true),
      destinationService: _Destination(null),
    );

    expect(await unavailable.export(), isA<DiagnosticLogUnavailable>());
    expect(await cancelled.export(), isA<DiagnosticLogExportCancelled>());
  });
}

final class _Files implements DiagnosticLogFileService {
  _Files({required this.existsValue});

  final bool existsValue;
  (String, String)? copyArguments;

  @override
  Future<bool> exists(String path) async => existsValue;

  @override
  Future<void> copy(String sourcePath, String destinationPath) async {
    copyArguments = (sourcePath, destinationPath);
  }
}

final class _Source implements DiagnosticLogSource {
  const _Source(this.path);

  @override
  final String? path;
}

final class _Destination implements DiagnosticLogDestinationService {
  const _Destination(this.path);

  final String? path;

  @override
  Future<String?> choosePath() async => path;
}
