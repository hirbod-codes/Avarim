import 'package:avarim/api/models/helpers.dart';

class Loudness {
  const Loudness({this.integratedLufs, this.truePeakDbtp, this.loudnessRangeLu});

  final double? integratedLufs;
  final double? truePeakDbtp;
  final double? loudnessRangeLu;

  factory Loudness.fromJson(Map<String, dynamic> json) => Loudness(
    integratedLufs: asDouble(json['integratedLufs']),
    truePeakDbtp: asDouble(json['truePeakDbtp']),
    loudnessRangeLu: asDouble(json['loudnessRangeLu']),
  );
}
