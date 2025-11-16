#!/usr/bin/env bash
set -e
#!/usr/bin/env bash
set -e

# Install Flutter SDK (idempotent: reuse if already cloned)
echo "Setting up Flutter SDK..."
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
else
  echo "Flutter directory already exists, reusing cached SDK."
fi
export PATH="$PWD/flutter/bin:$PATH"

echo "Enabling Flutter web and running doctor..."
flutter config --enable-web
flutter doctor

echo "Running flutter pub get..."
flutter pub get

echo "Building Flutter web (release)..."
flutter build web --release

echo "Flutter web build completed."

# Install Flutter SDK
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PWD/flutter/bin:$PATH"

# Enable web and check setup
flutter config --enable-web
flutter doctor

# Install dependencies
flutter pub get

# Build web release
flutter build web --release