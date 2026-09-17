# flutter_local_notifications persists scheduled notifications with Gson,
# which relies on generic type information (TypeToken) at runtime. R8
# strips that by default, causing "Missing type parameter" crashes in
# release builds only (debug builds aren't minified, so this never shows
# up until release). See: https://github.com/MaikuB/flutter_local_notifications/issues/2265

# Keep generic signatures so Gson's TypeToken can resolve them.
-keepattributes Signature
-keepattributes *Annotation*

# Keep the plugin's own classes (notification data models, receivers).
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep Gson itself and anything it reflects into.
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-dontwarn com.google.gson.**
