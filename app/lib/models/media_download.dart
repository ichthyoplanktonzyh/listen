abstract interface class MediaDownloadHandle {
  Stream<double> get progress;
  Future<String?> get completed;
  void cancel();
}
