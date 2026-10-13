import 'package:avarim/account/models/user_info.dart';
import 'package:avarim/plan/models/plan.dart';
import 'package:avarim/plan/all_plans_notifier.dart';
import 'package:avarim/subscription/subscription_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

extension PlanCapabilities on UserInfo {
  Plan? _getPlan(WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider).subscription;
    if (subscription == null) return null;

    final plans = ref.watch(allPlansProvider).plans;
    if (plans == null) return null;

    final plan = plans.firstWhere((e) => e.title == subscription.planTitle);
    return plan;
  }

  bool isStringContentAllowed(WidgetRef ref) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return plan.privileges.allowedContentTypes.string;
  }

  bool isStringContentForbidden(WidgetRef ref) => !isStringContentAllowed(ref);

  bool isRichTextContentAllowed(WidgetRef ref) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return plan.privileges.allowedContentTypes.richText;
  }

  bool isRichTextContentForbidden(WidgetRef ref) => !isRichTextContentAllowed(ref);

  bool isImageContentAllowed(WidgetRef ref) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return plan.privileges.allowedContentTypes.image;
  }

  bool isImageContentForbidden(WidgetRef ref) => !isImageContentAllowed(ref);

  bool isAudioContentAllowed(WidgetRef ref) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return plan.privileges.allowedContentTypes.audio;
  }

  bool isAudioContentForbidden(WidgetRef ref) => !isAudioContentAllowed(ref);

  bool isVideoContentAllowed(WidgetRef ref) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return plan.privileges.allowedContentTypes.video;
  }

  bool isVideoContentForbidden(WidgetRef ref) => !isVideoContentAllowed(ref);

  bool maxCardsPerCategoryReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.cardsPerCategory;
  }

  bool maxCategoriesReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.categoriesPerNestedLevel;
  }

  bool maxContentsPerCardSide(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.contentsPerCardSide;
  }

  bool maxNestedCategoriesReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.nestedLevels;
  }

  bool maxStorageBytesReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.storageBytes;
  }

  bool maxValuePerContentStringReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.valuePerContent.string;
  }

  bool maxValuePerContentRichTextReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.valuePerContent.richText;
  }

  bool maxValuePerContentImageReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.valuePerContent.image;
  }

  bool maxValuePerContentAudioReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.valuePerContent.audio;
  }

  bool maxValuePerContentVideoReached(WidgetRef ref, int currentCount) {
    final plan = _getPlan(ref);
    if (plan == null) return false;

    return currentCount >= plan.privileges.valuePerContent.video;
  }
}
