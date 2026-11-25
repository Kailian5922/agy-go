# Third-Party Notices

AGY Go is licensed under the GNU Affero General Public License v3.0 (see [LICENSE](LICENSE)).
This file lists third-party source code, fonts, and icons adapted or bundled in this repository.

> Brand & mascot separation: No proprietary brand marks, launcher icons, whale graphics, or mascot packs from DSH Go (`ASSETS.md`) are included in AGY Go. AGY Go uses its own original geometric brand mark and Starling companion artwork.

## 1. DSH Go (AGPL-3.0)

- **Project**: DSH Go — https://github.com/ccch1mneyyy/dsh-Go
- **License**: GNU Affero General Public License v3.0
- **Usage**: Flutter UI architecture and visual system (`app/lib/ui/theme/`, `app/lib/ui/common/`, `app/lib/ui/shell/`, `app/lib/ui/chat/`, `app/lib/ui/workspace/`, `app/lib/ui/features/`, `app/lib/ui/settings/`), and Android phone storage mounting design (`app/android/.../runtime/PhoneStorage.kt`).
- **Modifications (2026-11-25)**: Adapted for Google Antigravity CLI (`agy acp`), Android native Bionic + PRoot execution, multi-workspace ACP `cwd` mounting, SSH SFTP browsing, and Flutter 3.50 `material_ui`.

## 2. PiPilot (MIT)

- **Project**: PiPilot — https://github.com/CikeSeven/pi_pilot
- **Copyright**: Copyright (c) 2026 CikeSeven
- **License**: MIT
- **Usage**: Upstream chat UI primitives, drawer gesture recognizer, sheet helpers, and theme foundations inherited via DSH Go.

## 3. Phosphor Icons (MIT)

- **Project**: Phosphor Icons 2.1.1 — https://phosphoricons.com (`@phosphor-icons/core`)
- **Copyright**: Copyright (c) 2023 Phosphor Icons
- **License**: MIT
- **Files**: `app/assets/fonts/DshIcons.ttf`, `app/lib/ui/theme/dsh_glyphs.dart`, `app/lib/ui/theme/app_icons.dart`.

## 4. JetBrains Mono (SIL OFL 1.1)

- **Project**: JetBrains Mono — https://github.com/JetBrains/JetBrainsMono
- **Copyright**: Copyright 2020 The JetBrains Mono Project Authors
- **License**: SIL Open Font License 1.1 (full text in `app/assets/fonts/OFL.txt`)
- **Files**: `app/assets/fonts/JetBrainsMono-Regular.ttf`, `JetBrainsMono-Italic.ttf`, `JetBrainsMono-Medium.ttf`, `JetBrainsMono-Bold.ttf`.
