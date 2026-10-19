part of '../api_service.dart';

// Capability production attempts (Core 4.0). Attempts are the durable unit of
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

  /// Finalizes a running attempt as succeeded or failed. Succeeded carries
  /// the producer tool identity; failed carries the stable reason.
  Future<CapabilityAttempt> finalizeCapabilityAttempt({
    required String materialId,
    required String attemptId,
    required bool succeeded,
    String? failureReason,
    String? toolId,
    String? toolVersion,
  }) async {
    final body = succeeded
        ? {
            'status': 'succeeded',
            'tool_id': toolId,
            'tool_version': toolVersion,
          }
        : {'status': 'failed', 'reason': failureReason};
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
