# Optional PRoot Linux Container Runtime

By default, **AGY Go** runs Google's official `android_arm64` Bionic build of Antigravity CLI (`agy`) natively on Android `arm64-v8a` devices with zero PRoot overhead.

If you want a full Ubuntu 24.04 userland (`git`, `python3`, `bash`, `apt`, `node`) inside the app — or need to run on an `x86_64` Android emulator (which only has `linux_amd64`, not `android_amd64`) — `app/android/app/build.gradle.kts` automatically picks up optional PRoot bundles placed in:

```text
runtime/out/arm64-v8a/
├── assets/runtime/rootfs.tar.xz
└── jniLibs/arm64-v8a/
    ├── libproot.so
    ├── libproot-loader.so
    ├── libtalloc.so
    └── libandroid-shmem.so
```

When `libproot.so` and `filesDir/runtime/rootfs` are present on device, `EngineScreen` automatically unlocks the **PRoot Ubuntu Linux** toggle in `AgyProcess.kt`.
