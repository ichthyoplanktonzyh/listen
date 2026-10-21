part of '../api_service.dart';

// Capability production attempts (Core 5.0). Attempts are the durable unit of
// `generating` / `failed_attempt` evidence; retries create new attempts and
// never rewrite old facts.

extension CapabilityAttemptsApi on LocalApi {
  /// Starts a production attempt for one capability. Retry creates a new
  /// attempt and never rewrites the previous attempt's facts.
  Future<CapabilityAttempt> startCapabilityAttempt(
    String materialId,
    String capability,
  ) async => decodeCapabilityAttempt(
    (await _request(
          'POST',
          '/v1/materials/${Uri.encodeComponent(materialId)}/capability-attempts',
          {'capability': capability},
        ))
        as Map<String, dynamic>,
  );

  /// Finalizes a running attempt with its explicit terminal state.
  /// Succeeded carries the producer tool identity; failed carries its stable
  /// reason; cancelled carries neither.
  Future<CapabilityAttempt> finalizeCapabilityAttempt({
    required String materialId,
    required String attemptId,
    required CapabilityAttemptFinalStatus status,
    String? failureReason,
    String? toolId,
    String? toolVersion,
  }) async {
    final body = switch (status) {
      CapabilityAttemptFinalStatus.succeeded => {
        'status': status.name,
        'tool_id': toolId,
        'tool_version': toolVersion,
      },
      CapabilityAttemptFinalStatus.failed => {
        'status': status.name,
        'reason': failureReason,
      },
      CapabilityAttemptFinalStatus.cancelled => {'status': status.name},
    };
    return decodeCapabilityAttempt(
      (await _request(
            'PUT',
            '/v1/materials/${Uri.encodeComponent(materialId)}/capability-attempts/'
                '${Uri.encodeComponent(attemptId)}',
            body,
          ))
          as Map<String, dynamic>,
    );
  }
}
