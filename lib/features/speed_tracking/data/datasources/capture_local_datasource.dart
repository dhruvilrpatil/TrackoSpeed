import 'package:sqflite/sqflite.dart';

import '../../../../core/error/error_handler.dart';
import '../../domain/entities/capture_entity.dart';

/// Local data source interface for captures
abstract class CaptureLocalDataSource {
  Future<int> insertCapture(CaptureEntity capture);
  Future<List<CaptureEntity>> getAllCaptures();
  Future<List<CaptureEntity>> getCapturesBySession(String sessionId);
  Future<List<CaptureEntity>> getCapturesByDateRange(DateTime start, DateTime end);
  Future<CaptureEntity?> getCaptureById(int id);
  Future<int> deleteCapture(int id);
  Future<int> deleteAllCaptures();
  Future<int> getCaptureCount();
}

/// SQLite implementation of capture data source
class CaptureLocalDataSourceImpl implements CaptureLocalDataSource {
  final Database database;

  CaptureLocalDataSourceImpl({required this.database});

  static const String _tableName = 'captures';

  @override
  Future<int> insertCapture(CaptureEntity capture) async {
    try {
      final id = await database.insert(
        _tableName,
        capture.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      GlobalErrorHandler.logDebug('Capture inserted with id: $id');
      return id;
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Insert capture');
      rethrow;
    }
  }

  @override
  Future<List<CaptureEntity>> getAllCaptures() async {
    try {
      final maps = await database.query(
        _tableName,
        orderBy: 'timestamp DESC',
      );
      return maps.map((map) => CaptureEntity.fromMap(map)).toList();
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get all captures');
      return [];
    }
  }

  @override
  Future<List<CaptureEntity>> getCapturesBySession(String sessionId) async {
    try {
      final maps = await database.query(
        _tableName,
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp DESC',
      );
      return maps.map((map) => CaptureEntity.fromMap(map)).toList();
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get captures by session');
      return [];
    }
  }

  @override
  Future<List<CaptureEntity>> getCapturesByDateRange(DateTime start, DateTime end) async {
    try {
      final maps = await database.query(
        _tableName,
        where: 'timestamp BETWEEN ? AND ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: 'timestamp DESC',
      );
      return maps.map((map) => CaptureEntity.fromMap(map)).toList();
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get captures by date');
      return [];
    }
  }

  @override
  Future<CaptureEntity?> getCaptureById(int id) async {
    try {
      final maps = await database.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return CaptureEntity.fromMap(maps.first);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get capture by id');
      return null;
    }
  }

  @override
  Future<int> deleteCapture(int id) async {
    try {
      return await database.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Delete capture');
      return 0;
    }
  }

  @override
  Future<int> deleteAllCaptures() async {
    try {
      return await database.delete(_tableName);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Delete all captures');
      return 0;
    }
  }

  @override
  Future<int> getCaptureCount() async {
    try {
      final result = await database.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get capture count');
      return 0;
    }
  }
}

