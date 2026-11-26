import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/quota_state.dart';
import '../common/app_sheet.dart';
import '../theme/theme.dart';

/// Semantic color for remaining quota fraction (`>30%` primary, `10-30%` warning, `<10%` danger).
Color quotaTone(BuildContext context, double remainingFraction) {
  final dsh = DshColors.of(context);
  if (remainingFraction < 0.10) return dsh.danger;
  if (remainingFraction < 0.30) return dsh.warning;
  return Theme.of(context).colorScheme.primary;
}

/// Compact Mist Glass 5-hour & weekly quota banner shown inside ModelSheet
/// for the currently active model category (`Gemini`, `Claude`, `OpenAI`, etc.).
class ModelQuotaCard extends ConsumerWidget {
  const ModelQuotaCard({
    super.key,
    required this.category,
    this.selectedModelName,
  });

  final String? category;
  final String? selectedModelName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(quotaProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);

    final matched = quota.groupsForCategory(
      category,
      selectedModelName: selectedModelName,
    );

    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: AppShape.radiusLg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  AppIcons.diagnostics,
                  size: 15,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    matched.length == 1
                        ? '${matched.first.displayName} · 剩余额度'
                        : '订阅剩余额度',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (quota.isRefreshing)
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: colors.primary,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => unawaited(
                      ref.read(quotaProvider.notifier).ensureLoaded(force: true),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        AppIcons.refresh,
                        size: 15,
                        color: dsh.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            switch (quota.status) {
              QuotaLoadStatus.idle || QuotaLoadStatus.loading => Text(
                '正在查询 5 小时与周额度…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dsh.textTertiary,
                ),
              ),
              QuotaLoadStatus.apiKeyMode => Text(
                '当前使用 API Key 按量计费，无 5 小时 / 周订阅额度限制',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dsh.textTertiary,
                ),
              ),
              QuotaLoadStatus.notSignedIn => Text(
                quota.errorMessage ?? '未登录 Google 账号，登录后可查看 5 小时与周额度',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dsh.warning,
                ),
              ),
              QuotaLoadStatus.unavailable when matched.isEmpty => Row(
                children: [
                  Expanded(
                    child: Text(
                      quota.errorMessage ?? '暂无法获取 5 小时与周额度',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: dsh.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => unawaited(
                      ref.read(quotaProvider.notifier).ensureLoaded(force: true),
                    ),
                    child: Text(
                      '重试',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              _ => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (idx, group) in matched.indexed) ...[
                    if (idx > 0) const SizedBox(height: 10),
                    if (matched.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          group.displayName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: dsh.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _QuotaGroupMeters(group: group),
                  ],
                ],
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// Full multi-group 5-hour & weekly quota section for the `/usage` Context & Usage sheet.
class QuotaOverviewSection extends ConsumerWidget {
  const QuotaOverviewSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(quotaProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SheetTitleBar.inset + 4,
            4,
            SheetTitleBar.inset,
            6,
          ),
          child: Row(
            children: [
              Text(
                '订阅额度（5 小时 / 周额度）',
                style: groupTitleStyle(context)?.copyWith(
                  color: dsh.textTertiary,
                ),
              ),
              const Spacer(),
              if (quota.isRefreshing)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: colors.primary,
                    ),
                  ),
                )
              else
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  onPressed: () => unawaited(
                    ref.read(quotaProvider.notifier).ensureLoaded(force: true),
                  ),
                  child: const Text('刷新额度'),
                ),
            ],
          ),
        ),
        SheetGroup(
          children: [
            switch (quota.status) {
              QuotaLoadStatus.idle || QuotaLoadStatus.loading => Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '正在查询 Antigravity 5 小时与周额度…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: dsh.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              QuotaLoadStatus.apiKeyMode => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '当前使用 Gemini API Key 按量计费，无 5 小时 / 周订阅额度限制。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dsh.textTertiary,
                  ),
                ),
              ),
              QuotaLoadStatus.notSignedIn => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  quota.errorMessage ?? '尚未登录 Google 账号，登录后可查看 5 小时与周额度。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dsh.warning,
                  ),
                ),
              ),
              QuotaLoadStatus.unavailable when quota.groups.isEmpty => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  quota.errorMessage ?? '暂无法获取订阅额度，请点击右上角「刷新额度」重试。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dsh.textTertiary,
                  ),
                ),
              ),
              _ => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (idx, group) in quota.groups.indexed) ...[
                      if (idx > 0) ...[
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          color: colors.onSurface.withValues(alpha: 0.08),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        group.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (group.description != null &&
                          group.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          group.description!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dsh.textTertiary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _QuotaGroupMeters(group: group),
                    ],
                  ],
                ),
              ),
            },
          ],
        ),
      ],
    );
  }
}

class _QuotaGroupMeters extends StatelessWidget {
  const _QuotaGroupMeters({required this.group});

  final QuotaGroup group;

  @override
  Widget build(BuildContext context) {
    final fiveHour = group.fiveHourBucket;
    final weekly = group.weeklyBucket;

    if (fiveHour != null && weekly != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _QuotaBucketMeter(label: '5 小时额度', bucket: fiveHour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuotaBucketMeter(label: '周额度', bucket: weekly),
          ),
        ],
      );
    }

    final ordered = <QuotaBucket>[
      ?fiveHour,
      ?weekly,
      for (final b in group.buckets)
        if (b != fiveHour && b != weekly) b,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, b) in ordered.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _QuotaBucketMeter(
            label: b.windowKind == QuotaWindowKind.other
                ? (b.name.isNotEmpty ? b.name : '剩余额度')
                : b.windowKind.shortLabel,
            bucket: b,
          ),
        ],
      ],
    );
  }
}

class _QuotaBucketMeter extends StatelessWidget {
  const _QuotaBucketMeter({
    required this.label,
    required this.bucket,
  });

  final String label;
  final QuotaBucket bucket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);
    final tone = quotaTone(context, bucket.remainingFraction);
    final pct = formatQuotaPercent(bucket.remainingFraction);
    final reset = formatQuotaResetCountdown(bucket.resetTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: dsh.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              pct,
              style: AppType.monoLabel(
                color: tone,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: bucket.remainingFraction.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: colors.onSurface.withValues(alpha: 0.08),
            color: tone,
          ),
        ),
        if (reset != null) ...[
          const SizedBox(height: 4),
          Text(
            reset,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: dsh.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
