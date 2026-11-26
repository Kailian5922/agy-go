import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';

/// Top-level pages reachable from SessionsDrawer, QuickPanel, and AllFeaturesPage.
enum DrawerDestination {
  engine,
  workspaces,
  files,
  remote,
  terminal,
  phone,
  pet,
  share,
  keepAlive,
  features,
  settings,
  settingsSearch;

  IconData get icon => switch (this) {
    DrawerDestination.engine => AppIcons.engine,
    DrawerDestination.workspaces => AppIcons.workspace,
    DrawerDestination.files => AppIcons.files,
    DrawerDestination.remote => AppIcons.remoteHosts,
    DrawerDestination.terminal => AppIcons.terminal,
    DrawerDestination.phone => AppIcons.phoneControl,
    DrawerDestination.pet => AppIcons.pet,
    DrawerDestination.share => AppIcons.share,
    DrawerDestination.keepAlive => AppIcons.keepAlive,
    DrawerDestination.features => AppIcons.allFeatures,
    DrawerDestination.settings => AppIcons.settings,
    DrawerDestination.settingsSearch => AppIcons.search,
  };

  String get label => switch (this) {
    DrawerDestination.engine => '本机引擎',
    DrawerDestination.workspaces => '工作区',
    DrawerDestination.files => '文件浏览',
    DrawerDestination.remote => 'SSH 远程主机',
    DrawerDestination.terminal => '远程终端',
    DrawerDestination.phone => '手机操控',
    DrawerDestination.pet => '星灵桌宠',
    DrawerDestination.share => '分享与回放',
    DrawerDestination.keepAlive => '保活与更新',
    DrawerDestination.features => '全部功能',
    DrawerDestination.settings => '设置',
    DrawerDestination.settingsSearch => '搜索设置',
  };
}
