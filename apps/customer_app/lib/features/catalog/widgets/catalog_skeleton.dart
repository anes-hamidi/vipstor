import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Loading layout for the storefront.
///
/// The placeholders mirror the final proportions — slim header, search row,
/// category chips, result line, then the product grid — so the first paint
/// does not reflow when data arrives.
class CatalogSkeleton extends StatelessWidget {
  const CatalogSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ContentConstrainedBox.dashboard(
      maxWidth: 1200,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Row(
            children: [
              AppStates.skeleton(
                width: 44,
                height: 44,
                borderRadius: AppRadius.mdAll,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStates.skeleton(
                      width: 170,
                      height: 16,
                      borderRadius: AppRadius.smAll,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStates.skeleton(
                      width: 104,
                      height: 10,
                      borderRadius: AppRadius.smAll,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AppStates.skeleton(
                width: 44,
                height: 44,
                borderRadius: AppRadius.pillAll,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppStates.skeleton(
                  height: 48,
                  borderRadius: AppRadius.mdAll,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppStates.skeleton(
                width: 48,
                height: 48,
                borderRadius: AppRadius.mdAll,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: [
                _chip(width: 68),
                const SizedBox(width: AppSpacing.sm),
                _chip(width: 92),
                const SizedBox(width: AppSpacing.sm),
                _chip(width: 80),
                const SizedBox(width: AppSpacing.sm),
                _chip(width: 104),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppStates.skeleton(
            width: 120,
            height: 11,
            borderRadius: AppRadius.smAll,
          ),
          const SizedBox(height: AppSpacing.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisExtent: 200,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: 6,
            itemBuilder: (_, __) => AppStates.skeleton(
              height: 200,
              borderRadius: AppRadius.xlAll,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({required double width}) {
    return AppStates.skeleton(
      width: width,
      height: 40,
      borderRadius: AppRadius.pillAll,
    );
  }
}
