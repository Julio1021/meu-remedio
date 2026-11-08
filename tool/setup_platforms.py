#!/usr/bin/env python3
"""Aplica a configuração nativa (Android/iOS) depois de `flutter create .`.

Uso (na raiz do projeto):
    flutter create --org br.com.meuremedio --platforms=android,ios .
    python3 tool/setup_platforms.py
"""
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLAT = ROOT / "platform"


def done(msg):
    print(f"  ✓ {msg}")


def android():
    app = ROOT / "android" / "app"
    if not app.exists():
        sys.exit("Pasta android/ não encontrada. Rode antes: flutter create --platforms=android,ios .")
    main = app / "src" / "main"
    shutil.copy(PLAT / "android" / "AndroidManifest.xml", main / "AndroidManifest.xml")
    done("AndroidManifest.xml (permissões e receivers de notificação)")
    dst = main / "res" / "drawable"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy(PLAT / "android" / "res" / "drawable" / "ic_stat_pill.xml", dst / "ic_stat_pill.xml")
    done("ícone da notificação (ic_stat_pill)")

    kts = app / "build.gradle.kts"
    groovy = app / "build.gradle"
    if kts.exists():
        s = kts.read_text()
        if "isCoreLibraryDesugaringEnabled" not in s:
            s = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", s, count=1)
        if "desugar_jdk_libs" not in s:
            s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = maxOf(flutter.minSdkVersion, 23)", s)
        kts.write_text(s)
        done("build.gradle.kts (desugaring + minSdk 23)")
    elif groovy.exists():
        s = groovy.read_text()
        if "coreLibraryDesugaringEnabled" not in s:
            s = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", s, count=1)
        if "desugar_jdk_libs" not in s:
            s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
        s = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion Math.max(flutter.minSdkVersion, 23)", s)
        s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = Math.max(flutter.minSdkVersion, 23)", s)
        groovy.write_text(s)
        done("build.gradle (desugaring + minSdk 23)")
    else:
        print("  ! build.gradle não encontrado — habilite coreLibraryDesugaring manualmente (veja README).")


def ios():
    runner = ROOT / "ios" / "Runner"
    if not runner.exists():
        print("  - iOS ignorado (pasta ios/ não existe)")
        return
    shutil.copy(PLAT / "ios" / "AppDelegate.swift", runner / "AppDelegate.swift")
    done("AppDelegate.swift (ações de notificação em segundo plano)")
    plist = runner / "Info.plist"
    s = plist.read_text()
    extra = {
        "NSCameraUsageDescription": "Usada para fotografar a embalagem do medicamento.",
        "NSPhotoLibraryUsageDescription": "Usada para anexar a foto de um medicamento.",
        "CFBundleDisplayName": None,
    }
    for k, v in extra.items():
        if v and k not in s:
            s = s.replace("<dict>", f"<dict>\n\t<key>{k}</key>\n\t<string>{v}</string>", 1)
    s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1Meu Remédio\2", s)
    plist.write_text(s)
    done("Info.plist (câmera/fotos, nome exibido)")


def tests():
    wt = ROOT / "test" / "widget_test.dart"
    if wt.exists() and "MyApp" in wt.read_text():
        wt.unlink()
        done("removido test/widget_test.dart gerado pelo template")


if __name__ == "__main__":
    print("Configurando plataformas…")
    android()
    ios()
    tests()
    print("Pronto. Agora rode: flutter pub get && flutter run")
