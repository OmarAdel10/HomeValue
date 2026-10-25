import 'package:equatable/equatable.dart';
import '../../domain/entities/house_features.dart';

class HouseFeaturesModel extends Equatable {
  final double medInc;
  final double houseAge;
  final double aveRooms;
  final double aveBedrms;
  final double population;
  final double aveOccup;
  final double latitude;
  final double longitude;
  final String oceanProximity;

  const HouseFeaturesModel({
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

  factory HouseFeaturesModel.fromEntity(HouseFeatures entity) {
    return HouseFeaturesModel(
      medInc: entity.medInc,
      houseAge: entity.houseAge,
      aveRooms: entity.aveRooms,
      aveBedrms: entity.aveBedrms,
      population: entity.population,
      aveOccup: entity.aveOccup,
      latitude: entity.latitude,
      longitude: entity.longitude,
      oceanProximity: entity.oceanProximity.value,
    );
  }

  HouseFeatures toEntity() {
    return HouseFeatures(
      medInc: medInc,
      houseAge: houseAge,
      aveRooms: aveRooms,
      aveBedrms: aveBedrms,
      population: population,
      aveOccup: aveOccup,
      latitude: latitude,
      longitude: longitude,
      oceanProximity: OceanProximity.fromString(oceanProximity),
    );
  }

  Map<String, dynamic> toJson() => {
        'MedInc': medInc,
        'HouseAge': houseAge,
        'AveRooms': aveRooms,
        'AveBedrms': aveBedrms,
        'Population': population,
        'AveOccup': aveOccup,
        'Latitude': latitude,
        'Longitude': longitude,
        'ocean_proximity': oceanProximity,
      };

  factory HouseFeaturesModel.fromJson(Map<String, dynamic> json) {
    return HouseFeaturesModel(
      medInc: (json['MedInc'] as num).toDouble(),
      houseAge: (json['HouseAge'] as num).toDouble(),
      aveRooms: (json['AveRooms'] as num).toDouble(),
      aveBedrms: (json['AveBedrms'] as num).toDouble(),
      population: (json['Population'] as num).toDouble(),
      aveOccup: (json['AveOccup'] as num).toDouble(),
      latitude: (json['Latitude'] as num).toDouble(),
      longitude: (json['Longitude'] as num).toDouble(),
      oceanProximity: json['ocean_proximity'] as String,
    );
  }

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
}
