class UserUsage {
  final String _id;
  final int storageBytes;

  const UserUsage({required String id, required this.storageBytes}) : _id = id;

  factory UserUsage.fromJson(Map<String, dynamic> json) => UserUsage(id: json['_id'] as String, storageBytes: json['storageBytes'] as int);

  Map<String, dynamic> toJson() => {'_id': _id, 'storageBytes': storageBytes};
}
