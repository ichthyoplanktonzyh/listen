import 'dart:io';

abstract interface class MediaFileService {
  bool exists(String path);
  String basename(String path);
}

class LocalMediaFileService implements MediaFileService {
  const LocalMediaFileService();

  @override
  bool exists(String path) => File(path).existsSync();
  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;
}
