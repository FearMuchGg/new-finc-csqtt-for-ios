# CSQTT for iOS — переработанный клиент

Клон iOS-клиента `vk-turn-proxy-ios` (anton48 / cacggghp), переработанный под
сервер **CSQTT 2.5**: новый визуальный слой в стиле **Liquid Glass**, тёмная и
светлая темы, анимации, тактильный отклик, онбординг и русская локализация —
при сохранении всей сетевой части (Go-мост, TURN, DTLS-SRTP, WRAP, csqtt 2.5).

> Это отдельная папка в проекте **CSQTT 2.5.0**. Оригинал лежит рядом
> (`../vk-turn-proxy-ios`) и не изменялся.

## Что переработано

| Слой | Что сделано |
|---|---|
| Дизайн-система | токены цвета/радиусов/отступов, брендовый акцент, «жидкое стекло» на `.ultraThinMaterial` + спекулярный градиент, hairline-обводка и две тени (`Design/CSQTTTheme.swift`) |
| Компоненты | орб статуса с дыханием, glass-плитки статистики, монограммы серверов, пустые состояния, скелетоны, inline-баннер ошибок (`Design/CSQTTComponents.swift`) |
| Онбординг | три экрана при первом запуске, пропуск, прогресс-точки (`Design/CSQTTOnboarding.swift`) |
| Главный экран | стеклянный статус, анимация переходов, haptics, числовые переходы, баннер ошибки вместо красной подписи |
| Настройки | раздел «Внешний вид»: тема, стекло, анимации, haptics |
| Live Activity | пульсация щита при подключении, оранжевая точка DIRECT в компактном острове, keyline в цвет маршрута |
| Локализация | String Catalog: русский и английский (`Design/Localizable.xcstrings`) |

Логика туннеля, Go-код (`pkg/`, `WireGuardBridge/`), скрипты сборки и тесты
не переписывались: переработка касается представления.

## Сборка

### GitHub Actions (без подписи)

Workflow `.github/workflows/ios-unsigned.yml` собирает на macOS:

1. Go-xcframework (`make -C WireGuardBridge xcframework`);
2. приложение без подписи (`CODE_SIGNING_ALLOWED=NO`);
3. артефакт **`VKTurnProxy-unsigned.ipa`** (zip с `Payload/VKTurnProxy.app`),
   плюс `.app.zip`, dSYM и файлы entitlements.

Запуск: push в `main` или вручную (`workflow_dispatch`). Готовый `.ipa`
скачивается из раздела **Actions → ios-unsigned → Artifacts**.

### Локально (macOS)

```bash
make -C WireGuardBridge xcframework

xcodebuild \
  -project VKTurnProxy/VKTurnProxy.xcodeproj \
  -scheme VKTurnProxy \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
```

Затем упаковать:

```bash
mkdir -p build/ipa/Payload
cp -R build/DerivedData/Build/Products/Release-iphoneos/VKTurnProxy.app build/ipa/Payload/
ditto -c -k --sequesterRsrc --keepParent build/ipa/Payload VKTurnProxy-unsigned.ipa
```

### Подпись

`.ipa` собран без подписи. Для установки на устройство его нужно подписать
(AltStore, Sideloadly, Esign, Xcode) сертификатом **платного** аккаунта
разработчика: приложение содержит Network Extension (`PacketTunnel.appex`),
а Apple требует для него профиль с capability **Network Extension** (и App
Groups, если они используются). Entitlements лежат в артефакте:

- `VKTurnProxy/VKTurnProxy/VKTurnProxy.entitlements`
- `VKTurnProxy/PacketTunnel/PacketTunnel.entitlements`

## Структура

```
CSQTTiOS/
├── VKTurnProxy/                 # Xcode-проект (app, PacketTunnel, widget)
│   └── VKTurnProxy/
│       ├── Design/              # новая косметика (единственная новая папка)
│       │   ├── CSQTTTheme.swift
│       │   ├── CSQTTComponents.swift
│       │   ├── CSQTTOnboarding.swift
│       │   └── Localizable.xcstrings
│       └── …                    # существующие экраны (точечно переработаны)
├── WireGuardBridge/             # Go-мост + xcframework
├── pkg/                         # Go: csqtt 2.5, csqtt 2.1.9, TURN, speedtest
├── tools/, third_party/, docs/  # как в оригинале
├── ci/attach_design_files.py    # подключение Design/ к проекту (однократно)
├── quick_link.py, go.mod, …
└── .github/workflows/ios-unsigned.yml
```

## Отличия от оригинала

- Оригинальный `vk-turn-proxy-ios` не изменялся; этот клон — самостоятельная
  копия.
- Новые Swift-файлы подключены в `project.pbxproj` и в target `VKTurnProxy`
  (см. `ci/attach_design_files.py` — скрипт идемпотентен и проверяет файл).
- Добавлена shared-схема `VKTurnProxy.xcscheme`, без неё `xcodebuild -scheme`
  в CI не находит цель.
- `Info.plist`: `CFBundleLocalizations = en, ru`.

## Credits и лицензия

Based on [vk-turn-proxy](https://github.com/cacggghp/vk-turn-proxy) by
[cacggghp](https://github.com/cacggghp) and
[vk-turn-proxy-ios](https://github.com/anton48/vk-turn-proxy-ios) by anton48.

[GNU General Public License v3.0](LICENSE) (GPL-3.0) — как производная
`vk-turn-proxy` (GPL-3.0). Файлы с заголовком `SPDX-License-Identifier`
дополнительно доступны под указанной там лицензией; проект в целом — GPL-3.0.
