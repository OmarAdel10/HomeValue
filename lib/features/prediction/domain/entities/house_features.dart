import 'package:equatable/equatable.dart';

enum OceanProximity {
  lessThan1HourOcean('<1H OCEAN'),
  inland('INLAND'),
  nearOcean('NEAR OCEAN'),
  nearBay('NEAR BAY'),
  island('ISLAND');

  final String value;

  const OceanProximity(this.value);

  static OceanProximity fromString(String value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Invalid ocean proximity: $value'),
    );
  }

  @override
  String toString() => value;
}

class HouseFeatures extends Equatable {
  final double medInc;
  final double houseAge;
  final double aveRooms;
  final double aveBedrms;
  final double population;
  final double aveOccup;
  final double latitude;
  final double longitude;
  final OceanProximity oceanProximity;

  const HouseFeatures({
    required this.medInc,
    required this.houseAge,
    required this.aveRooms,
    required this.aveBedrms,
    required this.population,
    required this.aveOccup,
    required this.latitude,
    required this.longitude,
    required this.oceanProximity,
  });

  @override
  List<Object?> get props => [
        medInc,
        houseAge,
        aveRooms,
        aveBedrms,
        population,
        aveOccup,
        latitude,
        longitude,
        oceanProximity,
      ];

  Map<String, dynamic> toJson() => {
        'MedInc': medInc,
        'HouseAge': houseAge,
        'AveRooms': aveRooms,
        'AveBedrms': aveBedrms,
        'Population': population,
        'AveOccup': aveOccup,
        'Latitude': latitude,
        'Longitude': longitude,
        'ocean_proximity': oceanProximity.value,
      };
}