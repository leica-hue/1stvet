#!/usr/bin/env bash
set -e

# Install Flutter SDK (always fresh clone to avoid cache conflicts)
echo "Setting up Flutter SDK..."
rm -rf flutter
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PWD/flutter/bin:$PATH"

echo "Enabling Flutter web and running doctor..."
flutter config --enable-web
flutter doctor

echo "Running flutter pub get..."
flutter pub get

echo "Building Flutter web (release)..."
flutter build web --release

echo "Flutter web build completed."