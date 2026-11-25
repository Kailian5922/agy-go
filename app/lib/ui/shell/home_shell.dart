// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/sessions_state.dart';
import '../../state/settings_state.dart';
import '../chat/chat_screen.dart';
import '../engine/engine_screen.dart';
import '../features/all_features_page.dart';
import '../pet/starling_pet.dart';
import '../phone/phone_control_screen.dart';
import '../remote/ssh_hosts_screen.dart';
import '../settings/settings_screen.dart';
import '../share/share_screen.dart';
import '../system/keep_alive_screen.dart';
import '../terminal/terminal_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspace_screen.dart';
import '../workspace/workspaces_ui.dart';
import 'drawer_destination.dart';
import 'drawer_drag.dart';
import 'quick_panel.dart';
import 'sessions_drawer.dart';

/// Home shell mirroring DSH Go's HomeShell:
/// Continuous 1-finger gesture-arena left SessionsDrawer + center ChatScreen +
/// right QuickPanel with fluid parallax and SlidingGlass panels.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.chatBuilder, this.initiallyOpen = false});

  final Widget Function(VoidCallback openDrawer)? chatBuilder;
  final bool initiallyOpen;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with TickerProviderStateMixin {
  late final AnimationController _drawer = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
    value: widget.initiallyOpen ? 1 : 0,
  );

  late final AnimationController _quickPanel = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
  );

  late bool _open = widget.initiallyOpen;
  bool _quickPanelOpen = false;

  @override
  void initState() {
    super.initState();
    _drawer.addListener(() {
      final open = _drawer.value > 0;
      if (open != _open) setState(() => _open = open);
    });
    _quickPanel.addListener(() {
      final open = _quickPanel.value > 0;
      if (open != _quickPanelOpen) setState(() => _quickPanelOpen = open);
    });
  }

  @override
  void dispose() {
    _drawer.dispose();
    _quickPanel.dispose();
    super.dispose();
  }

  double _drawerWidth(BuildContext context) => math.min(
    320.0 + MediaQuery.paddingOf(context).left,
    MediaQuery.sizeOf(context).width - 56,
  );

  double _quickPanelWidth(BuildContext context) {
    final hasSession = ref.read(sessionsProvider).currentSessionId != null;
    return math.min(
      (hasSession ? QuickPanel.conversationWidth : QuickPanel.width) +
          MediaQuery.paddingOf(context).right,
      MediaQuery.sizeOf(context).width - 56,
    );
  }

  void _slideOpen(AnimationController side) {
    FocusManager.instance.primaryFocus?.unfocus();
    side.animateTo(
      1,
      curve: AppMotion.glide,
      duration: AppMotion.of(context, AppMotion.emphasized),
    );
  }

  void _slideClosed(AnimationController side) {
    FocusManager.instance.primaryFocus?.unfocus();
    side.animateBack(
      0,
      curve: AppMotion.glide,
      duration: AppMotion.of(context, AppMotion.standard),
    );
  }

  void _openDrawer() => _slideOpen(_drawer);
  void _closeDrawer() => _slideClosed(_drawer);
  void _openQuickPanel() => _slideOpen(_quickPanel);
  void _closeQuickPanel() => _slideClosed(_quickPanel);

  void _onDragStart(AnimationController side) {
    side.stop();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onDragDelta(AnimationController side, double width, double opening) {
    if (width <= 0) return;
    side.value = (side.value + opening / width).clamp(0.0, 1.0);
  }

  void _onDragEnd(AnimationController side, double width, double velocity) {
    if (velocity.abs() >= kMinFlingVelocity && width > 0) {
      final target = velocity > 0 ? 1.0 : 0.0;
      if (AppMotion.reduced(context)) {
        side.value = target;
        return;
      }
      final spring = AppMotion.settle(
        AppMotion.flingSpring,
        side.value,
        target,
        velocity / width,
        landing: false,
      );
      if (velocity > 0) {
        side.animateWith(spring);
      } else {
        side.animateBackWith(spring);
      }
      return;
    }
    if (side.value >= 0.5) {
      _slideOpen(side);
    } else {
      _slideClosed(side);
    }
  }

  void _openDestination(DrawerDestination destination) {
    final page = switch (destination) {
      DrawerDestination.engine => const EngineScreen(),
      DrawerDestination.workspaces => const WorkspacesPage(),
      DrawerDestination.files => const WorkspaceScreen(),
      DrawerDestination.remote => const SshHostsScreen(),
      DrawerDestination.terminal => const TerminalScreen(),
      DrawerDestination.phone => const PhoneControlScreen(),
      DrawerDestination.pet => const PetSettingsPage(),
      DrawerDestination.share => const ShareScreen(),
      DrawerDestination.keepAlive => const KeepAliveScreen(),
      DrawerDestination.features => const AllFeaturesPage(),
      DrawerDestination.settings => const SettingsScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    Future<void>.delayed(AppMotion.slow, () {
      if (!mounted) return;
      _drawer.value = 0;
      _quickPanel.value = 0;
    });
  }

  Map<Type, GestureRecognizerFactory> get _drawerGestures => {
    DrawerDragRecognizer:
        GestureRecognizerFactoryWithHandlers<DrawerDragRecognizer>(
          () => DrawerDragRecognizer(
            isOpen: () => _drawer.value > 0,
            onStart: () => _onDragStart(_drawer),
            onDelta: (dx) => _onDragDelta(_drawer, _drawerWidth(context), dx),
            onEnd: (velocity) =>
                _onDragEnd(_drawer, _drawerWidth(context), velocity),
            debugOwner: this,
          ),
          (_) {},
        ),
  };

  Map<Type, GestureRecognizerFactory> get _quickPanelGestures {
    final settings = MediaQuery.maybeGestureSettingsOf(context);
    return {
      QuickPanelDragRecognizer:
          GestureRecognizerFactoryWithHandlers<QuickPanelDragRecognizer>(
            () => QuickPanelDragRecognizer(
              isOpen: () => _quickPanel.value > 0,
              onStart: () => _onDragStart(_quickPanel),
              onDelta: (dx) =>
                  _onDragDelta(_quickPanel, _quickPanelWidth(context), -dx),
              onEnd: (velocity) => _onDragEnd(
                _quickPanel,
                _quickPanelWidth(context),
                -velocity,
              ),
              debugOwner: this,
            ),
            (recognizer) => recognizer.gestureSettings = settings,
          ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final width = _drawerWidth(context);
    final sessionId = ref.watch(
      sessionsProvider.select((s) => s.currentSessionId),
    );
    final quickPanelOn = ref.watch(
      settingsProvider.select((s) => s.quickPanelSwipe),
    );
    final chat =
        widget.chatBuilder?.call(_openDrawer) ??
        ChatScreen(
          onOpenDrawer: _openDrawer,
          onOpenQuickPanel: _openQuickPanel,
          onOpenDestination: _openDestination,
        );

    return PopScope(
      canPop: !_open && !_quickPanelOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_quickPanelOpen) {
          _closeQuickPanel();
        } else {
          _closeDrawer();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dshSystemOverlay(Theme.of(context).brightness),
        child: AppBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(
                  excluding: _open || _quickPanelOpen,
                  child: _SideParallax(
                    drawer: _drawer,
                    drawerWidth: width,
                    quickPanel: _quickPanel,
                    quickPanelWidth: _quickPanelWidth(context),
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.translucent,
                      gestures: {
                        ..._drawerGestures,
                        if (quickPanelOn) ..._quickPanelGestures,
                      },
                      child: chat,
                    ),
                  ),
                ),
                const StarlingPetOverlay(),
                Positioned.fill(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    gestures: _drawerGestures,
                    child: _DrawerOverlay(
                      animation: _drawer,
                      width: width,
                      drawer: SessionsDrawer(
                        onClose: _closeDrawer,
                        onOpen: _openDestination,
                        drawerMotion: _drawer,
                      ),
                      onClose: _closeDrawer,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    gestures: quickPanelOn ? _quickPanelGestures : const {},
                    child: _DrawerOverlay(
                      animation: _quickPanel,
                      width: _quickPanelWidth(context),
                      fromRight: true,
                      drawer: QuickPanel(
                        motion: _quickPanel,
                        onOpen: _openDestination,
                        sessionId: _quickPanelOpen ? sessionId : null,
                      ),
                      onClose: _closeQuickPanel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideParallax extends StatelessWidget {
  const _SideParallax({
    required this.drawer,
    required this.drawerWidth,
    required this.quickPanel,
    required this.quickPanelWidth,
    required this.child,
  });

  final Animation<double> drawer;
  final double drawerWidth;
  final Animation<double> quickPanel;
  final double quickPanelWidth;
  final Widget child;

  static const _share = 0.14;

  @override
  Widget build(BuildContext context) {
    final fluid = AppMotion.fluid(context);
    return AnimatedBuilder(
      animation: Listenable.merge([drawer, quickPanel]),
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          fluid
              ? _share *
                    (drawer.value * drawerWidth -
                        quickPanel.value * quickPanelWidth)
              : 0,
          0,
        ),
        child: child,
      ),
    );
  }
}

class _DrawerOverlay extends StatelessWidget {
  const _DrawerOverlay({
    required this.animation,
    required this.width,
    required this.drawer,
    required this.onClose,
    this.fromRight = false,
  });

  final Animation<double> animation;
  final double width;
  final Widget drawer;
  final VoidCallback onClose;
  final bool fromRight;

  @override
  Widget build(BuildContext context) {
    final scrim = DshSurfaces.of(context).scrim;
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: drawer),
      builder: (context, drawer) {
        final progress = animation.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: progress == 0,
                child: GestureDetector(
                  onTap: onClose,
                  child: ColoredBox(
                    color: scrim.withValues(alpha: scrim.a * progress),
                  ),
                ),
              ),
            ),
            Positioned(
              left: fromRight ? null : 0,
              right: fromRight ? 0 : null,
              top: 0,
              bottom: 0,
              width: width,
              child: Visibility(
                visible: progress > 0,
                maintainState: true,
                child: Transform.translate(
                  offset: Offset(
                    (progress - 1) * (width + 24) * (fromRight ? -1 : 1),
                    0,
                  ),
                  child: drawer!,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
