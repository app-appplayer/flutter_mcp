# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Keep Google Tink classes
-keep class com.google.crypto.tink.** { *; }
-keepclassmembers class com.google.crypto.tink.** { *; }

# Keep Google API client classes used by Tink
-dontwarn com.google.api.client.http.**
-dontwarn org.joda.time.**
-keep class com.google.api.client.http.** { *; }
-keep class org.joda.time.** { *; }

# Keep error prone annotations
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**

# Keep Flutter MCP plugin classes
-keep class com.example.flutter_mcp.** { *; }
-keepclassmembers class com.example.flutter_mcp.** { *; }

# General rules
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception