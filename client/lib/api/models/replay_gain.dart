import 'package:avarim/api/models/helpers.dart';

class ReplayGain {
  const ReplayGain({this.trackGainDb, this.trackPeak, this.albumGainDb});

  final double? trackGainDb;
  final double? trackPeak;
  final double? albumGainDb;

  factory ReplayGain.fromJson(Map<String, dynamic> json) =>
      ReplayGain(trackGainDb: asDouble(json['trackGainDb']), trackPeak: asDouble(json['trackPeak']), albumGainDb: asDouble(json['albumGainDb']));
}
