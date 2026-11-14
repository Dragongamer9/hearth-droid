#!/system/bin/sh
# Hearth Droid after start-up (hearth.rc). Each step checks first and only does what's needed.
say() { /system/bin/log -t HearthDroid "$*"; }

# 1. The web engine: Hearth draws its screen with it. On a first start Android sometimes hasn't picked one yet.
if /system/bin/dumpsys webviewupdate 2>/dev/null | grep -q "Current WebView package is null"; then
    if /system/bin/cmd webviewupdate set-webview-implementation com.android.webview >/dev/null 2>&1; then
        say "picked the web engine (com.android.webview)"
        /system/bin/am force-stop dev.hearthos.android
    else
        say "couldn't pick the web engine"
    fi
fi

# 2. Hearth as the home screen, on the first start only. After that the choice is the person's own: this never
#    changes it again.
if [ "$(getprop persist.hearth.home_set)" != 1 ]; then
    if /system/bin/cmd role add-role-holder --user 0 android.app.role.HOME dev.hearthos.android 0 >/dev/null 2>&1; then
        setprop persist.hearth.home_set 1
        say "Hearth set as the home screen (first start)"
    else
        say "couldn't set Hearth as the home screen; will try again next start"
    fi
fi
