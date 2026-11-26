import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/pet_state.dart';
import '../common/brief_notice.dart';
import '../common/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';

/// 100% original animated companion ("星灵 Starling") rendered via CustomPainter.
/// Zero proprietary assets from DSH Go.
class StarlingAvatar extends StatefulWidget {
  const StarlingAvatar({super.key, required this.mood, this.size = 56});

  final PetMood mood;
  final double size;

  @override
  State<StarlingAvatar> createState() => _StarlingAvatarState();
}

class _StarlingAvatarState extends State<StarlingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _StarlingPainter(mood: widget.mood, progress: _ctrl.value),
      ),
    );
  }
}

class _StarlingPainter extends CustomPainter {
  _StarlingPainter({required this.mood, required this.progress});

  final PetMood mood;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final angle = progress * math.pi * 2;
    final bob = math.sin(angle) * (mood == PetMood.happy ? 3.5 : 2.0);
    final cx = size.width / 2;
    final cy = size.height / 2 + bob;
    final r = size.shortestSide * 0.34;

    final accent = switch (mood) {
      PetMood.thinking => const Color(0xFF4B67B4),
      PetMood.working => const Color(0xFF34766F),
      PetMood.waitingApproval => const Color(0xFFD97706),
      PetMood.happy => const Color(0xFF726291),
      PetMood.sleeping => const Color(0xFF64748B),
      PetMood.idle => const Color(0xFF4B67B4),
    };

    canvas.drawCircle(
      Offset(cx, cy),
      r * (1.28 + 0.06 * math.sin(angle * 2)),
      Paint()..color = accent.withValues(alpha: 0.22),
    );

    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 1.0,
        colors: [
          Color.lerp(accent, Colors.white, 0.38)!,
          accent,
          Color.lerp(accent, Colors.black, 0.22)!,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, bodyPaint);

    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    final eyePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final ex = r * 0.32;
    final ey = cy - r * 0.05;
    if (mood == PetMood.sleeping) {
      canvas.drawLine(
        Offset(cx - ex - 3.5, ey),
        Offset(cx - ex + 3.5, ey),
        eyePaint,
      );
      canvas.drawLine(
        Offset(cx + ex - 3.5, ey),
        Offset(cx + ex + 3.5, ey),
        eyePaint,
      );
    } else if (mood == PetMood.happy) {
      canvas.drawArc(
        Rect.fromCenter(center: Offset(cx - ex, ey + 1), width: 7, height: 6),
        math.pi,
        math.pi,
        false,
        eyePaint,
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(cx + ex, ey + 1), width: 7, height: 6),
        math.pi,
        math.pi,
        false,
        eyePaint,
      );
    } else {
      final blink = progress > 0.94 ? 0.25 : 1.0;
      final fill = Paint()..color = Colors.white;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - ex, ey),
          width: r * 0.28,
          height: r * 0.28 * blink,
        ),
        fill,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + ex, ey),
          width: r * 0.28,
          height: r * 0.28 * blink,
        ),
        fill,
      );
    }

    if (mood == PetMood.thinking ||
        mood == PetMood.working ||
        mood == PetMood.waitingApproval) {
      final orbitR = r * 1.22;
      final sx = cx + math.cos(angle * 2) * orbitR;
      final sy = cy + math.sin(angle * 2) * orbitR;
      canvas.drawCircle(
        Offset(sx, sy),
        r * 0.17,
        Paint()
          ..color = mood == PetMood.waitingApproval
              ? const Color(0xFFFEF08A)
              : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarlingPainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.progress != progress;
}

/// Draggable in-app floating companion resting over HomeShell.
class StarlingPetOverlay extends ConsumerStatefulWidget {
  const StarlingPetOverlay({super.key});

  @override
  ConsumerState<StarlingPetOverlay> createState() => _StarlingPetOverlayState();
}

/// Legacy alias kept for compatibility.
typedef DraggableInAppPet = StarlingPetOverlay;

class _StarlingPetOverlayState extends ConsumerState<StarlingPetOverlay> {
  double _right = 14;
  double _bottom = 96;
  bool _showLabel = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(petSettingsProvider);
    if (!settings.showInApp) return const SizedBox.shrink();
    final mood = ref.watch(petMoodProvider);
    final size = MediaQuery.sizeOf(context);

    return Positioned(
      right: _right.clamp(8.0, math.max(8.0, size.width - 72)),
      bottom: _bottom.clamp(76.0, math.max(76.0, size.height - 150)),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _right -= details.delta.dx;
            _bottom -= details.delta.dy;
          });
        },
        onTap: () => setState(() => _showLabel = !_showLabel),
        onLongPress: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PetSettingsPage()),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_showLabel)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GlassSurface(
                  tier: GlassTier.chrome,
                  stadium: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      '星灵 · ${mood.label}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            StarlingAvatar(mood: mood, size: 54),
          ],
        ),
      ),
    );
  }
}

/// Companion & desktop overlay settings page in DSH Go style.
class PetSettingsPage extends ConsumerStatefulWidget {
  const PetSettingsPage({super.key});

  @override
  ConsumerState<PetSettingsPage> createState() => _PetSettingsPageState();
}

typedef PetSettingsScreen = PetSettingsPage;

class _PetSettingsPageState extends ConsumerState<PetSettingsPage> {
  PetMood _previewMood = PetMood.idle;

  @override
  Widget build(BuildContext context) {
    final pet = ref.watch(petSettingsProvider);
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);

    return AppPage.list(
      title: '星灵桌宠',
      subtitle: const Text('AGY Go 原创状态联动伴侣与桌面悬浮球'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: GlassSurface(
            tier: GlassTier.card,
            borderRadius: AppShape.radiusLg,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  StarlingAvatar(mood: _previewMood, size: 96),
                  const SizedBox(height: 8),
                  Text(
                    '星灵 Starling · ${_previewMood.label}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '实时反映思考、工具执行、等待确认与任务完成状态。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: dsh.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final m in PetMood.values)
                        ChoiceChip(
                          label: Text(m.label),
                          selected: _previewMood == m,
                          onSelected: (_) => setState(() => _previewMood = m),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SettingsSection(
          title: '应用外悬浮输入（DSH Go 同款方案）',
          footer: const Text(
            '切出 AGY Go 到任意其他应用时，单击悬浮球即可直接弹出输入框「问一句」并切换当前对话/新对话；长按打开快捷菜单；待确认的手机操控也会以悬浮气泡弹出。',
          ),
          children: [
            SettingsSwitchTile(
              icon: AppIcons.overlayBall,
              tint: 1,
              title: '应用外桌面悬浮球与悬浮输入',
              subtitle: pet.canDrawOverlays
                  ? '已获悬浮窗权限，单击悬浮球可在应用外直接输入提问'
                  : pet.canUseAccessibilityOverlay
                  ? '已通过无障碍悬浮就绪（免额外悬浮窗权限）'
                  : '需要「显示在其他应用上层」权限或开启手机操控无障碍服务',
              value: pet.showSystemOverlay,
              onChanged: (v) async {
                final ok = await ref
                    .read(petSettingsProvider.notifier)
                    .setShowSystemOverlay(v);
                if (v && !ok && context.mounted) {
                  showBriefNotice(context, '请在系统设置中允许悬浮窗后返回开启');
                }
              },
            ),
            SettingsSwitchTile(
              icon: AppIcons.openExternal,
              tint: 0,
              title: '仅在切出 AGY Go 后显示',
              subtitle: '回到本应用时自动隐藏桌面球，切到其他应用时自动滑出',
              value: pet.onlyOutsideApp,
              onChanged: (v) =>
                  ref.read(petSettingsProvider.notifier).setOnlyOutsideApp(v),
            ),
            if (pet.hasAnyOverlayPermission)
              SettingsTile(
                icon: AppIcons.askAi,
                tint: 4,
                title: '立即弹出悬浮输入条体验',
                subtitle: '在当前界面直接拉起悬浮「问一句」输入条',
                onTap: () async {
                  if (!pet.showSystemOverlay) {
                    await ref
                        .read(petSettingsProvider.notifier)
                        .setOnlyOutsideApp(false);
                    await ref
                        .read(petSettingsProvider.notifier)
                        .setShowSystemOverlay(true);
                  } else if (pet.onlyOutsideApp) {
                    await ref
                        .read(petSettingsProvider.notifier)
                        .setOnlyOutsideApp(false);
                  }
                  final opened = await ref
                      .read(petSettingsProvider.notifier)
                      .openFloatingAskBar();
                  if (!opened && context.mounted) {
                    showBriefNotice(context, '请先授予悬浮窗或无障碍权限');
                  }
                },
              ),
            if (!pet.hasAnyOverlayPermission)
              SettingsTile(
                icon: AppIcons.securityWarning,
                tint: 3,
                title: '打开应用信息（解除受限设置）',
                subtitle: '若系统禁止开启悬浮窗，先在应用信息右上角 ⋮ 允许受限设置',
                onTap: () =>
                    ref.read(petSettingsProvider.notifier).openAppDetails(),
              ),
          ],
        ),
        SettingsSection(
          title: '应用内伙伴',
          children: [
            SettingsSwitchTile(
              icon: AppIcons.pet,
              tint: 2,
              title: '在 App 内显示悬浮伙伴',
              subtitle: '可自由拖拽，单击查看状态，长按进入本页',
              value: pet.showInApp,
              onChanged: (v) =>
                  ref.read(petSettingsProvider.notifier).setShowInApp(v),
            ),
          ],
        ),
      ],
    );
  }
}
