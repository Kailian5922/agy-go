import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/pet_state.dart';
import '../shell/page_frame.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// 100% original animated companion ("星灵 Starling") rendered via CustomPainter.
class StarlingAvatar extends StatefulWidget {
  const StarlingAvatar({
    super.key,
    required this.mood,
    this.size = 56,
  });

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
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _StarlingPainter(
            mood: widget.mood,
            progress: _ctrl.value,
          ),
        );
      },
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
      PetMood.thinking => const Color(0xFF638CFF),
      PetMood.working => const Color(0xFF10B981),
      PetMood.waitingApproval => const Color(0xFFF59E0B),
      PetMood.happy => const Color(0xFF8B5CF6),
      PetMood.sleeping => const Color(0xFF64748B),
      PetMood.idle => const Color(0xFF3E63DD),
    };

    // Ambient halo
    canvas.drawCircle(
      Offset(cx, cy),
      r * (1.28 + 0.06 * math.sin(angle * 2)),
      Paint()..color = accent.withValues(alpha: 0.24),
    );

    // Core orb with specular gradient
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

    // Crisp glass rim
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    // Expressive eyes
    final eyePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final ex = r * 0.32;
    final ey = cy - r * 0.05;
    if (mood == PetMood.sleeping) {
      canvas.drawLine(Offset(cx - ex - 3.5, ey), Offset(cx - ex + 3.5, ey), eyePaint);
      canvas.drawLine(Offset(cx + ex - 3.5, ey), Offset(cx + ex + 3.5, ey), eyePaint);
    } else if (mood == PetMood.happy) {
      final leftArc = Rect.fromCenter(center: Offset(cx - ex, ey + 1), width: 7, height: 6);
      final rightArc = Rect.fromCenter(center: Offset(cx + ex, ey + 1), width: 7, height: 6);
      canvas.drawArc(leftArc, math.pi, math.pi, false, eyePaint);
      canvas.drawArc(rightArc, math.pi, math.pi, false, eyePaint);
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

    // Orbiting spark satellite during active / approval states
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
class DraggableInAppPet extends ConsumerStatefulWidget {
  const DraggableInAppPet({super.key});

  @override
  ConsumerState<DraggableInAppPet> createState() => _DraggableInAppPetState();
}

class _DraggableInAppPetState extends ConsumerState<DraggableInAppPet> {
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
          MaterialPageRoute<void>(builder: (_) => const PetSettingsScreen()),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_showLabel)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    '星灵 · ${mood.label}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
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

class PetSettingsScreen extends ConsumerStatefulWidget {
  const PetSettingsScreen({super.key});

  @override
  ConsumerState<PetSettingsScreen> createState() => _PetSettingsScreenState();
}

class _PetSettingsScreenState extends ConsumerState<PetSettingsScreen> {
  PetMood _previewMood = PetMood.idle;

  @override
  Widget build(BuildContext context) {
    final pet = ref.watch(petSettingsProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return AgyPage(
      title: '桌宠与伙伴（星灵）',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          HairlineCard(
            child: Column(
              children: [
                StarlingAvatar(mood: _previewMood, size: 96),
                const SizedBox(height: 8),
                Text(
                  '星灵 Starling · ${_previewMood.label}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'AGY Go 原创极简伴侣：实时反映思考、工具执行、待确认审批与完成状态。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaces.subtleText,
                  ),
                ),
                const SizedBox(height: 12),
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
          const SizedBox(height: 14),
          HairlineCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('在 App 内显示悬浮伙伴'),
                  subtitle: const Text('可自由拖拽，单击查看状态，长按进入本设置页'),
                  value: pet.showInApp,
                  onChanged: (v) =>
                      ref.read(petSettingsProvider.notifier).setShowInApp(v),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('App 外桌面悬浮球'),
                  subtitle: Text(
                    pet.canDrawOverlays
                        ? '已获得悬浮窗权限，切到其他应用时自动靠边吸附显示'
                        : '需要开启「显示在其他应用上层」权限',
                  ),
                  value: pet.showSystemOverlay,
                  onChanged: (v) async {
                    final ok = await ref
                        .read(petSettingsProvider.notifier)
                        .setShowSystemOverlay(v);
                    if (v && !ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('请在系统设置中允许 AGY Go 显示悬浮窗后返回开启。'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
