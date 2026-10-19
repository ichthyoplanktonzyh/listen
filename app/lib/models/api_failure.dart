import 'dart:convert';

/// The backend's JSON error envelope, parsed once at the client boundary.
///
/// A failed request used to reach the UI as one interpolated exception string
/// (`'…: $error'`), which meant an internal error code, a `correlation_id`, a
/// localhost port and an internal route could all end up rendered where the
/// learner's own words belong. The charter's P4 asks for an honest
/// instrument, **not debug output**: the envelope's fields are diagnostics, so
/// they get a type of their own and a default-hidden home instead of being
/// smuggled into the content flow.
///
/// Every field is nullable on purpose. This app does not own the canonical
/// contract, so an older or newer core may answer with a body that is not this
/// envelope at all — in that case only [raw] is populated, and callers show
/// the failure's *named state*, never [raw].
class ApiFailure {
  const ApiFailure({
    required this.raw,
    this.code,
    this.message,
    this.correlationId,
    this.retryable,
  });

  /// Reads the envelope out of a response body.
  ///
  /// Anything that is not a JSON object with the expected field types degrades
  /// to an [ApiFailure] carrying only [raw]: a body the client cannot type is
  /// still a body no caller may print as content.
  factory ApiFailure.parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return ApiFailure(raw: body);
    }
    if (decoded is! Map<String, dynamic>) return ApiFailure(raw: body);
    final retryable = decoded['retryable'];
    return ApiFailure(
      raw: body,
      code: decoded['code'] as String?,
      message: decoded['message'] as String?,
      correlationId: decoded['correlation_id'] as String?,
      // Only an actual boolean counts. A missing or non-boolean field means
      // "the backend did not say", which is not the same as "no".
      retryable: retryable is bool ? retryable : null,
    );
  }

  /// The full transport text — response body, and whatever the exception's
  /// own `toString` added (URI, socket detail). Diagnostics only: it is the
  /// one field that must never be interpolated into user-facing prose.
  final String raw;

  /// The backend's machine error code (`validation_error`, …).
  final String? code;

  /// The backend's own English explanation. Descriptive, but written for an
  /// operator: it belongs behind a disclosure, not in a sentence addressed to
  /// the learner.
  final String? message;

  /// The identifier that ties this failure to a backend log line.
  final String? correlationId;

  /// Whether the backend said the same request may be retried. Null means it
  /// did not say — treated as "no" by [isRetryable] so an affordance is only
  /// offered on an explicit yes.
  final bool? retryable;

  /// True only when the backend explicitly said the request may be retried.
  bool get isRetryable => retryable == true;

  /// Whether anything beyond [raw] was recognised. False means the body did
  /// not match the envelope this client knows.
  bool get isStructured =>
      code != null || message != null || correlationId != null;
}
