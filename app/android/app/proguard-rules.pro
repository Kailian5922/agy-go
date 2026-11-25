# Keep optional codec references inside Apache Commons Compress from failing R8
-dontwarn org.apache.commons.compress.**
-dontwarn com.github.luben.zstd.**
-dontwarn org.tukaani.xz.**
-dontwarn org.brotli.**
-dontwarn javax.naming.**

# Keep Android service / plugin classes referenced from AndroidManifest.xml
-keep class io.github.kailian5922.agy_go.** { *; }
