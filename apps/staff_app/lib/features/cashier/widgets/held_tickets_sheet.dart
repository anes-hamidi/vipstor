import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../../providers/staff_providers.dart';

class HeldTicketsSheet extends ConsumerWidget {
  const HeldTicketsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(posHeldTicketsProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: AppRadius.pillAll,
              ),
            ),
            AppSpacing.gapMd,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pause_circle_outline, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'السلات المعلقة (${tickets.length})',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (tickets.isNotEmpty)
                  TextButton(
                    onPressed: () => ref.read(posHeldTicketsProvider.notifier).state = [],
                    child: const Text('حذف الكل'),
                  ),
              ],
            ),
            const Divider(),
            Expanded(
              child: tickets.isEmpty
                  ? const AppEmptyView(
                      icon: Icons.shopping_basket_outlined,
                      title: 'لا توجد سلات معلقة',
                      description: 'يمكنك تعليق أي سلة نشطة للتعامل مع زبون آخر واسترجاعها لاحقًا.',
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: tickets.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final t = tickets[idx];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text('#${idx + 1}'),
                            ),
                            title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '${t.items.length} منتجات | ${t.heldAt.hour}:${t.heldAt.minute.toString().padLeft(2, '0')}',
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DzdPriceTag(centimes: t.totalCentimes, style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: AppSpacing.md),
                                FilledButton.icon(
                                  icon: const Icon(Icons.play_arrow, size: 16),
                                  label: const Text('استرجاع'),
                                  onPressed: () {
                                    ref.read(posCartProvider.notifier).resumeTicket(t.id);
                                    Navigator.pop(context);
                                  },
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                                  onPressed: () {
                                    ref.read(posHeldTicketsProvider.notifier).update(
                                          (list) => list.where((item) => item.id != t.id).toList(),
                                        );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
