-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# HDFC SmartGateway / Juspay HyperSDK
-keep class in.juspay.** { *; }
-dontwarn in.juspay.**

# Razorpay
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/

# Cashfree
-keep class com.cashfree.** { *; }
-dontwarn com.cashfree.**