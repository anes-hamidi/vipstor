import 'package:flutter/material.dart';

/// Stable failure codes accepted by `rpc_record_delivery_failure`.
///
/// The labels are used by the driver UI; the code is what is persisted so the
/// manager dashboard and audit trail can rely on a stable value.
enum DeliveryFailureReason {
  customerUnavailable(
    'customer_unavailable',
    'الزبون غير متاح',
    'لم يرد الزبون أو تعذر الوصول إليه',
    Icons.phone_missed_rounded,
  ),
  wrongAddress(
    'wrong_address',
    'عنوان غير صحيح',
    'العنوان غير دقيق أو لا يوجد أحد في الموقع',
    Icons.wrong_location_outlined,
  ),
  customerRefused(
    'customer_refused',
    'رفض الزبون الطلب',
    'رفض الزبون استلام البضاعة',
    Icons.person_off_outlined,
  ),
  paymentIssue(
    'payment_issue',
    'مشكلة في الدفع',
    'تعذر تحصيل المبلغ أو رفضه الزبون',
    Icons.payments_outlined,
  ),
  damagedOrder(
    'damaged_order',
    'الطلب تالف',
    'تلف أو نقص في البضاعة أثناء النقل',
    Icons.broken_image_outlined,
  ),
  other(
    'other',
    'سبب آخر',
    'سيتم توضيح السبب في الملاحظات',
    Icons.more_horiz_rounded,
  );

  const DeliveryFailureReason(
    this.code,
    this.label,
    this.description,
    this.icon,
  );

  final String code;
  final String label;
  final String description;
  final IconData icon;

  static DeliveryFailureReason? fromCode(String? code) {
    if (code == null) return null;
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }

  static String labelForCode(String? code) =>
      fromCode(code)?.label ??
      (code?.trim().isNotEmpty == true ? code! : 'سبب غير محدد');
}
