-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# HDFC SmartGateway / Juspay HyperSDK
-keep class in.juspay.** { *; }
-dontwarn in.juspay.**