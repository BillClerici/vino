class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic errors;

  ApiException(this.message, {this.statusCode, this.errors});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class UnauthorizedException extends ApiException {
  UnauthorizedException([String message = 'Unauthorized'])
      : super(message, statusCode: 401);
}

class SubscriptionRequiredException extends ApiException {
  SubscriptionRequiredException()
      : super('Active subscription required.', statusCode: 403);
}

class NotFoundException extends ApiException {
  NotFoundException([String message = 'Not found'])
      : super(message, statusCode: 404);
}

class ValidationException extends ApiException {
  ValidationException(dynamic errors)
      : super('Validation error', statusCode: 400, errors: errors);
}

class ServerException extends ApiException {
  ServerException([String message = 'Server error'])
      : super(message, statusCode: 500);
}
