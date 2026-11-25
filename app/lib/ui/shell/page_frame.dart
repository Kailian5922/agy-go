import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Unified secondary page layout with edge-to-edge backdrop and floating glass header.
class AgyPage extends StatelessWidget {
  const AgyPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AnnotatedRegion(
      value: agySystemOverlay(brightness),
      child: AgyBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: floatingActionButton,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: GlassSurface(
                    borderRadius: BorderRadius.circular(18),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 21),
                          onPressed: () => Navigator.of(context).maybePop(),
                          tooltip: '返回',
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ...actions,
                      ],
                    ),
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
