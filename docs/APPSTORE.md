# Подача в App Store — что готово и что делает только владелец

Из облачного контейнера (Linux) игру в App Store выложить нельзя: сборка и подпись `.ipa`
делаются Xcode на macOS, загрузка — под Apple-аккаунтом владельца. Ниже — что уже лежит
в репозитории и пошаговый путь для Mac.

## Готово в репозитории
- Пресет `iOS` в `export_presets.cfg`: bundle id `com.danlug.holidaydigger`, iPhone, портрет,
  версия 1.0, иконка App Store `art/brand/icon-1024.png` (без альфы, из `tools/gen_brand.py`),
  метод выпуска App Store (`export_method_release=0`).
- `project.godot`: `rendering/textures/vram_compression/import_etc2_astc=true` — без него Godot 4.4
  отказывает iOS-экспорту; на веб не влияет (все текстуры lossless).
- `tools/export_ios.sh` — генерирует `build/ios/Raskopki.xcodeproj` (+ `Raskopki.pck`,
  `PrivacyInfo.xcprivacy`, xcframework'и Godot). Проверено на Linux: проект генерируется.
- Политика конфиденциальности: `web/privacy.html` → https://danlug.github.io/Holiday-digger-/privacy.html
  (нужна ссылкой в карточке приложения).
- Скриншоты и тексты для карточки: `docs/store/` (`listing.md`, png) — делает зона product-polish.

## Нужно от владельца
1. Mac с **Xcode 16+** и Godot **4.4.stable** с export-шаблонами (`Editor → Manage Export Templates`).
2. **Apple Developer Program** (99 $/год) и Team ID (developer.apple.com → Membership).
3. В **App Store Connect** создать приложение: имя «Раскопки на каникулах», bundle id выше,
   SKU любой, категория Games → Simulation, возрастной рейтинг (анкета: мультяшное насилие — монстры),
   цена «бесплатно», страны, ссылка на политику, описание из `docs/store/listing.md`,
   скриншоты 6.9″ (1320×2868 или 1290×2796) и 6.5″ (1284×2778/1242×2688); экспортное
   соответствие — шифрования нет, кроме HTTPS (exempt).

## Шаги на Mac
```bash
git clone https://github.com/Danlug/Holiday-digger-.git && cd Holiday-digger-
git checkout claude/raskopki-game-dev-9oos3n     # или main после слияния PR #3
tools/export_ios.sh                               # → build/ios/Raskopki.xcodeproj
open build/ios/Raskopki.xcodeproj
```
В Xcode: target Raskopki → **Signing & Capabilities** → Automatically manage signing → выбрать Team
(тогда `app_store_team_id`/профили в пресете можно не трогать; если вписать Team ID в
`export_presets.cfg`, `tools/export_ios.sh` на Mac соберёт `.ipa` сам). Затем
**Product → Archive → Distribute App → App Store Connect → Upload**. После обработки —
**TestFlight** на своём iPhone (обязательно прогнать: первый запуск, звук, копка, покупка, уход в фон),
потом в App Store Connect: версия 1.0 → выбрать сборку → **Submit for Review**. Ревью — 1–3 дня.

## Что ревью может завернуть — решить до подачи
- **Покупки за доллары — заглушки** (`scripts/core/iap_manager.gd`: любой запрос честно
  отказывает, награды не выдаёт). Для стора это «незавершённая функция» (Guideline 2.1) или
  «покупки мимо StoreKit» (3.1.1). Варианты: (а) на iOS спрятать кнопки покупки долларов и
  подписок флагом до интеграции StoreKit; (б) подключить StoreKit через iOS-плагин Godot
  (`godot-ios-plugins` → InAppStore) — тоже только на Mac. Рекомендую (а) для первой подачи.
- **Ролики «посмотри рекламу»**: сети нет, награда выдаётся сразу (`AdManager.is_ad_ready()` ложно).
  Ревьюер увидит кнопку «реклама», которая ничего не показывает — тот же выбор: спрятать на iOS
  или подключить сеть (AdMob/Unity Ads плагином).
- **Аналитика PostHog** идёт по согласию (ГДД §16.1): в анкете App Privacy указать
  «Analytics → Product interaction, не связаны с личностью»; трекинга между приложениями нет —
  ATT не нужен.
- `min_ios_version="12.0"` — не проверялось на устройствах; если Xcode 16 ругается, поднять до 15.0.
