import 'package:avarim/plan/models/content_type_flags.dart';
import 'package:avarim/plan/models/max_value_per_content.dart';

/// Mirrors `privilegesSchema`.
class Privileges {
  final int categoriesPerNestedLevel;
  final int nestedLevels;
  final int cardsPerCategory;
  final int contentsPerCardSide;
  final int storageBytes;
  final ContentTypeFlags allowedContentTypes;

  /// Per-content-type size caps (`maxValuePerContent`). Parsed but
  /// deliberately not surfaced as a marketing bullet on the pricing
  /// page — it's an internal limit, not something a prospective user
  /// is comparing plans on. Kept here in case a future "full spec"
  /// comparison view wants it.
  final MaxValuePerContent valuePerContent;

  const Privileges({
    required this.categoriesPerNestedLevel,
    required this.nestedLevels,
    required this.cardsPerCategory,
    required this.contentsPerCardSide,
    required this.storageBytes,
    required this.allowedContentTypes,
    required this.valuePerContent,
  });

  factory Privileges.fromJson(Map<String, dynamic> json) => Privileges(
    categoriesPerNestedLevel: json['categoriesPerNestedLevel'] as int,
    nestedLevels: json['nestedLevels'] as int,
    cardsPerCategory: json['cardsPerCategory'] as int,
    contentsPerCardSide: json['contentsPerCardSide'] as int,
    storageBytes: json['storageBytes'] as int,
    allowedContentTypes: ContentTypeFlags.fromJson(json['allowedContentTypes'] as Map<String, dynamic>),
    valuePerContent: MaxValuePerContent.fromJson(json['valuePerContent'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'categoriesPerNestedLevel': categoriesPerNestedLevel,
    'nestedLevels': nestedLevels,
    'cardsPerCategory': cardsPerCategory,
    'contentsPerCardSide': contentsPerCardSide,
    'storageBytes': storageBytes,
    'allowedContentTypes': allowedContentTypes.toJson(),
    'valuePerContent': valuePerContent.toJson(),
  };
}
