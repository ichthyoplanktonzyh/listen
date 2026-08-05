abstract interface class MediaDownloadHandle {
  /// A null event means the download is running with no known total. Hosts
  /// that assemble a response at request time send no `Content-Length`, and
  /// there is no denominator to report.
  Stream<double?> get progress;
  Future<String?> get completed;
  void cancel();
}
