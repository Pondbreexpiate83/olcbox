# Turnbox macOS VPN - Quick Start Guide

## 🚀 Быстрый запуск

### Автоматическая настройка (рекомендуется)

Запустите этот скрипт для полной настройки:

```bash
# Сделайте скрипт исполняемым
chmod +x setup-macos-project.sh

# Запустите
./setup-macos-project.sh

# Следуйте инструкциям
open iosApp/iosApp.xcodeproj
```

### Ручная настройка

Если автоматическая настройка не сработала, следуйте инструкциям в **MACOS_IMPLEMENTATION.md**

## 🛠 Что уже сделано автоматически

✅ **Swift файлы созданы:**
- `macosApp/TurnboxApp.swift`
- `macosApp/MacosVpnManager.swift` (450+ строк)
- `macosApp/ContentView.swift` (SwiftUI интерфейс)
- `macosApp/MenuBarExtra.swift` (Menu bar)
- `PacketTunnelExtension/PacketTunnelProvider.swift` (410+ строк)

✅ **Конфигурационные файлы:**
- `macosApp/Info.plist`
- `macosApp/macosApp.entitlements`
- `PacketTunnelExtension/Info.plist`
- `PacketTunnelExtension/PacketTunnelExtension.entitlements`

✅ **Документация:**
- `MACOS_IMPLEMENTATION.md` - Полное руководство
- `QUICK_START.md` - Быстрый старт
- `setup-macos-project.sh` - Настройка проекта

✅ **Сборочные файлы:**
- `Makefile` - Автоматизация сборки

## 📦 Оставшиеся шаги (требуют Xcode)

Несмотря на автоматизацию, некоторые шаги требуют ручной работы в Xcode:

### 1. Добавить target'ы в Xcode
Запустите:
```bash
chmod +x automated-xcode-setup.rb
ruby automated-xcode-setup.rb
```

**Или** создайте вручную через File → New → Target...

### 2. Добавить SharedUI.framework
После сборки KMP:
```bash
make framework
```

Затем в Xcode:
- Перетащите `SharedUI.framework` в проект
- Добавьте к обоим target'ам (Turnbox-macOS и PacketTunnelExtension)

### 3. Добавить нативные бинарники
Положите в `macosApp/Resources/`:
- `libvkturn`
- `libhysteria`
- `tun2socks`

### 4. Настроить App Group
В Xcode в Signing & Capabilities:
- Добавьте **App Groups** capability
- Включите `group.org.turnbox.app.shared`

## 🎯 Следующие действия

1. **Запустите скрипт настройки:**
   ```bash
   ./setup-macos-project.sh
   ```

2. **Соберите KMP framework:**
   ```bash
   make framework
   ```

3. **Откройте проект:**
   ```bash
   open iosApp/iosApp.xcodeproj
   ```

4. **Следуйте инструкциям в Xcode:**
   - Добавьте framework
   - Добавьте бинарники
   - Configure signing

5. **Запустите:**
   Подключите устройство или используйте симулятор и нажмите Cmd+R

## 🐛 Troubleshooting

Если что-то не работает, проверьте:

```bash
# Проверьте Ruby
ruby --version

# Проверьте структуру
cd iosApp
xcodebuild -list

# Сборка KMP
./gradlew :sharedUI:linkReleaseFrameworkMacosArm64
```

## 🎉 Готово!

После настройки у вас будет полноценный macOS VPN клиент с:
- Современным SwiftUI интерфейсом
- Menu Bar Extra
- Packet Tunnel
- Полной интеграцией с KMP

**Приятной разработки!**

---
*Если возникнут вопросы, обратитесь к MACOS_IMPLEMENTATION.md*
