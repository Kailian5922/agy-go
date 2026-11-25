import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../chat/chat_screen.dart';
import '../pet/starling_pet.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';
import 'quick_panel.dart';
import 'sessions_drawer.dart';

/// 3-pane gesture shell inspired by dsh-Go:
/// - Center: ChatScreen (does not rebuild while dragging overlays)
/// - Left drag: continuous finger-tracking SessionsDrawer
/// - Right drag: continuous finger-tracking QuickPanel
/// - Wide screens (>= 840dp): docked left sidebar
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  late final AnimationController _leftCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final AnimationController _rightCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  // Active gesture target during a horizontal drag: -1 left drawer, +1 right panel, 0 none.
  int _dragTarget = 0;

  @override
  void dispose() {
    _leftCtrl.dispose();
    _rightCtrl.dispose();
    super.dispose();
  }

  void _openLeft() {
    _rightCtrl.reverse();
    _leftCtrl.forward();
  }

  void _openRight() {
    _leftCtrl.reverse();
    _rightCtrl.forward();
  }

  void _closeAll() {
    _leftCtrl.reverse();
    _rightCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 840;
    final panelWidth = math.min(width * 0.84, 340.0);
    final brightness = Theme.of(context).brightness;

    final chat = ChatScreen(
      showDrawerButton: !isWide,
      onOpenDrawer: _openLeft,
      onOpenQuickPanel: _openRight,
    );

    return AnnotatedRegion(
      value: agySystemOverlay(brightness),
      child: AgyBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (details) {
              if (_leftCtrl.value > 0) {
                _dragTarget = -1;
              } else if (_rightCtrl.value > 0) {
                _dragTarget = 1;
              } else {
                _dragTarget = 0;
              }
            },
            onHorizontalDragUpdate: (details) {
              final dx = details.delta.dx;
              if (_dragTarget == 0) {
                if (dx > 0 && !isWide) {
                  _dragTarget = -1;
                } else if (dx < 0) {
                  _dragTarget = 1;
                }
              }
              if (_dragTarget == -1 && !isWide) {
                _leftCtrl.value = (_leftCtrl.value + dx / panelWidth).clamp(0.0, 1.0);
              } else if (_dragTarget == 1) {
                _rightCtrl.value = (_rightCtrl.value - dx / panelWidth).clamp(0.0, 1.0);
              }
            },
            onHorizontalDragEnd: (details) {
              final vx = details.primaryVelocity ?? 0;
              if (_dragTarget == -1 && !isWide) {
                if (vx > 320 || (vx > -320 && _leftCtrl.value > 0.45)) {
                  _leftCtrl.forward();
                } else {
                  _leftCtrl.reverse();
                }
              } else if (_dragTarget == 1) {
                if (vx < -320 || (vx < 320 && _rightCtrl.value > 0.45)) {
                  _rightCtrl.forward();
                } else {
                  _rightCtrl.reverse();
                }
              }
              _dragTarget = 0;
            },
            child: Stack(
              children: [
                if (isWide)
                  Row(
                    children: [
                      SizedBox(
                        width: 300,
                        child: SessionsDrawer(docked: true),
                      ),
                      Expanded(child: chat),
                    ],
                  )
                else
                  chat,

                const DraggableInAppPet(),

                // Scrim + overlays rebuilt independently via AnimatedBuilder
                AnimatedBuilder(
                  animation: Listenable.merge([_leftCtrl, _rightCtrl]),
                  builder: (context, _) {
                    final scrimAlpha = math.max(_leftCtrl.value, _rightCtrl.value) * 0.34;
                    final anyOpen = _leftCtrl.value > 0 || _rightCtrl.value > 0;
                    if (!anyOpen) return const SizedBox.shrink();

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: _closeAll,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: scrimAlpha),
                            ),
                          ),
                        ),
                        if (!isWide && _leftCtrl.value > 0)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: -panelWidth * (1 - _leftCtrl.value),
                            width: panelWidth,
                            child: SessionsDrawer(onClose: _closeAll),
                          ),
                        if (_rightCtrl.value > 0)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: -panelWidth * (1 - _rightCtrl.value),
                            width: panelWidth,
                            child: QuickPanel(onClose: _closeAll),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
