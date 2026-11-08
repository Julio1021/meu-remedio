#!/usr/bin/env bash
# Instala o APK de diagnóstico num emulador e coleta evidências das notificações.
set -x
PKG=br.com.meuremedio.meu_remedio
OUT=emulador
mkdir -p $OUT
adb wait-for-device
adb shell settings put global window_animation_scale 0
adb install -r app-autotest.apk
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb shell appops get $PKG SCHEDULE_EXACT_ALARM || true
adb logcat -c
adb shell am start -W -n $PKG/.MainActivity
sleep 25
adb exec-out screencap -p > $OUT/1-app.png
adb shell dumpsys notification --noredact > $OUT/notif-1.txt
adb shell dumpsys alarm > $OUT/alarm-1.txt
adb logcat -d > $OUT/logcat-1.txt
echo "===== AUTOTEST ====="; grep -E "AUTOTEST|Falha" $OUT/logcat-1.txt | head -60
echo "===== ERROS ====="; grep -iE "FATAL|AndroidRuntime|Exception|dexterous" $OUT/logcat-1.txt | head -60
echo "===== NOTIFICACOES ATIVAS ====="; grep -E "pkg=$PKG|android.title=" $OUT/notif-1.txt | head -30
echo "===== ALARMES ====="; grep -B2 -A6 "$PKG" $OUT/alarm-1.txt | head -60
# Fecha o app (vai para segundo plano) e espera o teste agendado (1 min) e a dose (2 min)
adb shell input keyevent KEYCODE_HOME
sleep 170
adb shell dumpsys notification --noredact > $OUT/notif-2.txt
adb logcat -d > $OUT/logcat-2.txt
echo "===== NOTIFICACOES APOS 3 MIN ====="; grep -E "pkg=$PKG|android.title=" $OUT/notif-2.txt | head -40
echo "===== ERROS APOS 3 MIN ====="; grep -iE "FATAL|AndroidRuntime|Exception|dexterous|ScheduledNotification" $OUT/logcat-2.txt | tail -60
adb shell cmd statusbar expand-notifications
sleep 3
adb exec-out screencap -p > $OUT/2-notificacoes.png
# Toca no primeiro botão de ação (TOMADO) se existir, para testar a ação em segundo plano
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb pull /sdcard/ui.xml $OUT/ui.xml >/dev/null 2>&1
grep -o 'text="[^"]*"' $OUT/ui.xml | head -40
exit 0
