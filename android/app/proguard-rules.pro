# Real crash confirmed (2026-09-22, release build only): R8's optimizer
# was miscompiling a class inside the Tap payment SDK, producing
# java.lang.VerifyError on company.tap.gosellapi.internal.data_managers.
# PaymentDataManager$PaymentProcessListener the moment KNET checkout
# starts (SDKSession.start() -> PaymentDataManager.getInstance() ->
# PaymentDataManager.<init>). Debug builds don't run R8 at all, which is
# exactly why this never showed up there. Keeping the SDK's own classes
# (and the go_sell_sdk_flutter plugin wrapper around them) untouched by
# R8's optimizer/shrinker/obfuscator is the standard fix for this class of
# bug in a third-party precompiled library — R8 can still process the
# rest of the app normally.
-keep class company.tap.gosellapi.** { *; }
-keep interface company.tap.gosellapi.** { *; }
-keep class tap.company.go_sell_sdk_flutter.** { *; }
-dontwarn company.tap.gosellapi.**
