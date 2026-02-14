import 'package:equatable/equatable.dart';

/// Capture entity - represents a captured vehicle speed record
///
/// This is the core domain entity that holds all data for a capture event.
class CaptureEntity extends Equatable {
  final int? id;
  final String? plateNumber;
  final double estimatedVehicleSpeed;
  final double userSpeed;
  final double relativeSpeed;
  final double? gpsAccuracy;
  final double? confidenceScore;
  final String imagePath;
  final DateTime timestamp;
  final String sessionId;
  final String? vehicleClass;
  final Map<String, double>? boundingBox;

  const CaptureEntity({
    this.id,
    this.plateNumber,
    required this.estimatedVehicleSpeed,
    required this.userSpeed,
    required this.relativeSpeed,
    this.gpsAccuracy,
    this.confidenceScore,
    required this.imagePath,
    required this.timestamp,
    required this.sessionId,
    this.vehicleClass,
    this.boundingBox,
  });

  /// Copy with new values
  CaptureEntity copyWith({
    int? id,
    String? plateNumber,
    double? estimatedVehicleSpeed,
    double? userSpeed,
    double? relativeSpeed,
    double? gpsAccuracy,
    double? confidenceScore,
    String? imagePath,
    DateTime? timestamp,
    String? sessionId,
    String? vehicleClass,
    Map<String, double>? boundingBox,
  }) {
    return CaptureEntity(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      estimatedVehicleSpeed: estimatedVehicleSpeed ?? this.estimatedVehicleSpeed,
      userSpeed: userSpeed ?? this.userSpeed,
      relativeSpeed: relativeSpeed ?? this.relativeSpeed,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      imagePath: imagePath ?? this.imagePath,
      timestamp: timestamp ?? this.timestamp,
      sessionId: sessionId ?? this.sessionId,
      vehicleClass: vehicleClass ?? this.vehicleClass,
      boundingBox: boundingBox ?? this.boundingBox,
    );
  }

  /// Convert to map for database
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'plate_number': plateNumber,
      'estimated_vehicle_speed': estimatedVehicleSpeed,
      'user_speed': userSpeed,
      'relative_speed': relativeSpeed,
      'gps_accuracy': gpsAccuracy,
      'confidence_score': confidenceScore,
      'image_path': imagePath,
      'timestamp': timestamp.toIso8601String(),
      'session_id': sessionId,
      'vehicle_class': vehicleClass,
      'bounding_box': boundingBox != null
          ? '${boundingBox!['left']},${boundingBox!['top']},${boundingBox!['right']},${boundingBox!['bottom']}'
          : null,
    };
  }

  /// Create from database map
  factory CaptureEntity.fromMap(Map<String, dynamic> map) {
    Map<String, double>? boundingBox;
    if (map['bounding_box'] != null) {
      final parts = (map['bounding_box'] as String).split(',');
      if (parts.length == 4) {
        boundingBox = {
          'left': double.tryParse(parts[0]) ?? 0,
          'top': double.tryParse(parts[1]) ?? 0,
          'right': double.tryParse(parts[2]) ?? 0,
          'bottom': double.tryParse(parts[3]) ?? 0,
        };
      }
    }

    return CaptureEntity(
      id: map['id'] as int?,
      plateNumber: map['plate_number'] as String?,
      estimatedVehicleSpeed: (map['estimated_vehicle_speed'] as num).toDouble(),
      userSpeed: (map['user_speed'] as num).toDouble(),
      relativeSpeed: (map['relative_speed'] as num).toDouble(),
      gpsAccuracy: (map['gps_accuracy'] as num?)?.toDouble(),
      confidenceScore: (map['confidence_score'] as num?)?.toDouble(),
      imagePath: map['image_path'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      sessionId: map['session_id'] as String,
      vehicleClass: map['vehicle_class'] as String?,
      boundingBox: boundingBox,
    );
  }

  @override
  List<Object?> get props => [
    id,
    plateNumber,
    estimatedVehicleSpeed,
    userSpeed,
    relativeSpeed,
    gpsAccuracy,
    confidenceScore,
    imagePath,
    timestamp,
    sessionId,
    vehicleClass,
    boundingBox,
  ];

  @override
  String toString() {
    return 'CaptureEntity(id:$id, speed:${estimatedVehicleSpeed.toInt()} km/h, plate:$plateNumber)';
  }
}

