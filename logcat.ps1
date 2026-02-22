$env:PATH = "C:\Users\53\android-sdk\platform-tools;$env:PATH"
adb -s 8a5ab27c logcat -c
adb -s 8a5ab27c logcat flutter:V StealthVPNService:V AmneziaWGService:V ByeDPIService:V FallbackController:V "*:E"
