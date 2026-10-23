# Avarim

To manage your favorite audio files

## To develop

### Run after change in video_player_provider.dart file run

```cmd
dart run build_runner build
```

or:

```cmd
dart run build_runner watch --delete-conflicting-outputs
```

### To use another mirror(CMD)

```cmd
setx PUB_HOSTED_URL "https://pub.flutter-io.cn"
setx FLUTTER_STORAGE_BASE_URL "https://storage.flutter-io.cn"
```

to rollback:

```cmd
reg delete "HKCU\Environment" /F /V PUB_HOSTED_URL
reg delete "HKCU\Environment" /F /V FLUTTER_STORAGE_BASE_URL
```

### To build

```cmd
flutter run -d windows --dart-define=API_URL=https://api.example.com --dart-define=ENV=prod
flutter run -d windows --dart-define=API_URL=https://localhost:8081 --dart-define=ENV=dev
flutter run -d web-server --web-port=5000 --dart-define=API_URL=http://localhost:8081 --dart-define=ENV=dev
```

### Use nginx to redirect requests to backend(because of browsers CORS)

#### On windows

1. backend must first run mkcert.exe to generate `localhost+2.pem` and `localhost+2-key.pem`
2. nginx serves backend and https

download nginx and run:

```cmd
C:\nginx\nginx.exe -p C:\nginx\ -c <absolute\path\to\nginx.dev.conf>
```

for instance:

```cmd
C:\nginx\nginx.exe -p C:\nginx\ -c C:\projects\Avarim\client\nginx.dev.conf
```

To list or kill nginx processes

```cmd
tasklist | findstr nginx

taskkill /F /PID <pid>
```

### Localization

any update to localization .arb files needs a running this command: `flutter gen-l10n`

### for icons

run `dart run flutter_launcher_icons`
