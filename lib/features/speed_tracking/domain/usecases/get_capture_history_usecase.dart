import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/error_handler.dart';
import '../entities/capture_entity.dart';
import '../repositories/capture_repository.dart';

/// Parameters for getting capture history
class GetHistoryParams {
  final String? sessionId;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? limit;

  const GetHistoryParams({
    this.sessionId,
    this.startDate,
    this.endDate,
    this.limit,
  });

  /// Get all captures
  static const GetHistoryParams all = GetHistoryParams();
}

/// Use case for retrieving capture history
class GetCaptureHistoryUseCase with ErrorHandlerMixin {
  final CaptureRepository repository;

  GetCaptureHistoryUseCase({required this.repository});

  /// Execute the query
  Future<Result<List<CaptureEntity>>> call(GetHistoryParams params) async {
    try {
      Result<List<CaptureEntity>> result;

      if (params.sessionId != null) {
        result = await repository.getCapturesBySession(params.sessionId!);
      } else if (params.startDate != null && params.endDate != null) {
        result = await repository.getCapturesByDateRange(
          params.startDate!,
          params.endDate!,
        );
      } else {
        result = await repository.getAllCaptures();
      }

      // Apply limit if specified
      if (params.limit != null) {
        result = result.map((captures) {
          if (captures.length > params.limit!) {
            return captures.sublist(0, params.limit!);
          }
          return captures;
        });
      }

      return result;
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'GetCaptureHistoryUseCase');
      return Left(UnknownFailure(
        message: 'Failed to get capture history: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }
}

