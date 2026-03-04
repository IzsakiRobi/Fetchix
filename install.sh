#!/bin/bash

APP_ID="io.github.IzsakiRobi.Fetchix"
BASE_DIR="$HOME/.local/share/Fetchix"
ASSETS_DIR="$BASE_DIR/Assets"
APP_DIR="$HOME/.local/share/applications"

echo "📦 Telepítés indítása (Portable mód)..."

mkdir -p "$BASE_DIR"
mkdir -p "$ASSETS_DIR"
mkdir -p "$APP_DIR"

if [ -f "fetchix" ]; then
    cp fetchix "$BASE_DIR/fetchix"
    chmod +x "$BASE_DIR/fetchix"
    echo "✅ Futtatható fájl másolva: $BASE_DIR/fetchix"
else
    echo "❌ Hiba: Nem találom a 'fetchix' binárist! Fordítsd le előbb."
    exit 1
fi

if [ -f "Assets/io.github.IzsakiRobi.Fetchix.svg" ]; then
    cp "Assets/io.github.IzsakiRobi.Fetchix.svg" "$ASSETS_DIR/$APP_ID.svg"
    echo "✅ Ikon másolva: $ASSETS_DIR/$APP_ID.svg"
elif [ -f "io.github.IzsakiRobi.Fetchix.svg" ]; then
    cp "io.github.IzsakiRobi.Fetchix.svg" "$ASSETS_DIR/$APP_ID.svg"
    echo "✅ Ikon másolva: $ASSETS_DIR/$APP_ID.svg"
else
    echo "❌ Hiba: Nem találom az 'io.github.IzsakiRobi.Fetchix.svg' ikont!"
    exit 1
fi

if [ -f "Assets/Drop.png" ]; then
    cp "Assets/Drop.png" "$ASSETS_DIR/Drop.png"
    echo "✅ Drop ikon másolva: $ASSETS_DIR/Drop.png"
fi

cat <<EOF > "$APP_DIR/$APP_ID.desktop"
[Desktop Entry]
Name=Fetchix
Comment=Simple, multi-thread download manager
Exec=$BASE_DIR/fetchix %U
Icon=$ASSETS_DIR/$APP_ID.svg
Terminal=false
Type=Application
Categories=Network;FileTransfer;
MimeType=x-scheme-handler/fetchix;
StartupNotify=false
EOF

echo "✅ .desktop fájl létrehozva: $APP_DIR/$APP_ID.desktop"

update-desktop-database "$APP_DIR"
echo "✅ Rendszer alkalmazás-adatbázisa frissítve."
echo "🚀 TELEPÍTÉS KÉSZ!"

