# MealAttend R8 rules — applied when isMinifyEnabled=true (release builds).
# Flutter's own default rules (flutter_proguard_rules.pro) are added by the
# Flutter Gradle plugin automatically; Firebase/MLKit ship consumer rules in
# their AARs. The keeps below cover the plugins known to use reflection.

# flutter_local_notifications — scheduled notifications serialize via Gson.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Gson generic types (TypeToken) survive shrinking.
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# flutter_secure_storage — Android Keystore-backed prefs.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Play Core is referenced by Flutter's deferred-components support but is NOT
# bundled (we don't use deferred components) — silence the missing-class errors.
-dontwarn com.google.android.play.core.**

# Keep the generated Flutter embedding entry points.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
