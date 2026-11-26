# Keep Flutter engine & generated plugin registrants
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# Keep Tempo native Kotlin helpers, channels, and BroadcastReceivers
-keep class com.tempo.fitness.** { *; }

# Keep AndroidX FileProvider & media player components referenced via manifest / reflection
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# Suppress optional Play Core deferred-component & media references not bundled in offline APK
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.exoplayer2.**
-dontwarn androidx.media3.**
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement
