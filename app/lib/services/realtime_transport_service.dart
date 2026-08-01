import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/api_failure.dart';

abstract interface class RealtimeConnection {
  Stream<Object?> get messages;
  bool get isOpen;
  void send(Object data);
  Future<void> close();
}

typedef RealtimeConnectionFactory =
    Future<RealtimeConnection> Function(Uri uri, Map<String, dynamic> headers);

sealed class RealtimeTransportEvent {
  const RealtimeTransportEvent();
}

final class RealtimeAudioEvent extends RealtimeTransportEvent {
  const RealtimeAudioEvent(this.bytes);
  final Uint8List bytes;
}

final class RealtimeJsonEvent extends RealtimeTransportEvent {
  const RealtimeJsonEvent(this.value);
  final Map<String, dynamic> value;
}

abstract interface class RealtimeTransportService {
  Future<RealtimeConnection> connect(Uri uri, Map<String, dynamic> headers);

  RealtimeTransportEvent? decode(Object? message);
  ApiFailure describeFailure(Object error);
  Future<void> deleteTemporaryRecording(String path);
}

class IoRealtimeTransportService implements RealtimeTransportService {
  const IoRealtimeTransportService({RealtimeConnectionFactory? connect})
    : _connect = connect ?? _connectRealtime;

  final RealtimeConnectionFactory _connect;

  @override
  Future<RealtimeConnection> connect(Uri uri, Map<String, dynamic> headers) =>
      _connect(uri, headers);

  @override
  RealtimeTransportEvent? decode(Object? message) {
    if (message is List<int>) {
      return RealtimeAudioEvent(Uint8List.fromList(message));
    }
    if (message is! String) return null;
    return RealtimeJsonEvent(jsonDecode(message) as Map<String, dynamic>);
  }

  @override
  ApiFailure describeFailure(Object error) => error is ApiFailure
      ? error
      : error is HttpException
      ? ApiFailure.parse(error.message)
      : ApiFailure(raw: '$error');

  @override
  Future<void> deleteTemporaryRecording(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Session cleanup is best-effort; the recording asset owns turn audio.
    }
  }
}

class _IoRealtimeConnection implements RealtimeConnection {
  _IoRealtimeConnection(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get messages => _socket;

  @override
  bool get isOpen => _socket.readyState == WebSocket.open;

  @override
  void send(Object data) => _socket.add(data);

  @override
  Future<void> close() async => _socket.close();
}

Future<RealtimeConnection> _connectRealtime(
  Uri uri,
  Map<String, dynamic> headers,
) async => _IoRealtimeConnection(
  await WebSocket.connect(uri.toString(), headers: headers),
);
