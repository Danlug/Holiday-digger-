# Сборка «Раскопки на каникулах»

## Версии

- **Godot 4.4** (движок проверен на `4.4.stable.official.4c311cbee`; `config_version=5` в `project.godot` соответствует этой ветке 4.4 — более новый 4.x, скорее всего, тоже подойдёт, но не проверялся).
- Экспорт-шаблоны той же версии (`4.4.stable`) — см. «Экспорт-шаблоны» ниже.
- Для сборки iOS: **macOS** + **Xcode** (последняя версия, поддерживающая iOS 12+) — см. раздел iOS.

## Запуск локально

```bash
godot --path .
```

Откроется редактор; `run/main_scene` уже указывает на `res://scenes/main.tscn` — F5/Play запускает игру. Портретный вьюпорт настроен в `project.godot` (`window/size/viewport_width=224`, `viewport_height=480`, `stretch/mode=canvas_items`, `stretch/aspect=expand`, `handheld/orientation=1`).

Управление мышью (для отладки на компьютере) работает так же, как тач: джойстик или удержание экрана — оба ввода эмулируются левой кнопкой мыши (см. `scripts/ui/hud.gd`).

### Тесты (headless)

Часть тестов не использует автозагрузки (`Balance`/`GameState` недоступны в режиме `--script`, см. комментарии в файлах) и гоняется как обычный `SceneTree`-скрипт:

```bash
godot --headless --path . --script res://tests/test_balance.gd
godot --headless --path . --script res://tests/test_world_gen.gd
godot --headless --path . --script res://tests/test_fall_damage_speed.gd
```

Тест игрока (`player.gd`) обращается к автозагрузкам напрямую, поэтому запускается как обычная сцена (не `--script`) — тогда движок нормально поднимает `Balance`/`GameState`:

```bash
godot --headless --path . res://tests/test_player_harness.tscn
```

Код возврата процесса — `0`, если все проверки прошли, `1`, если хоть одна упала (вывод в stdout).

Общая проверка «ничего не падает при загрузке» (главная сцена, 30 игровых кадров без реального окна):

```bash
godot --headless --path . --quit-after 30
```

## Экспорт-шаблоны

Проверялась версия шаблонов `4.4.stable`. Если их нет в `~/.local/share/godot/export_templates/4.4.stable/` (Linux) или `~/Library/Application Support/Godot/export_templates/4.4.stable/` (macOS):

1. Скачать `Godot_v4.4-stable_export_templates.tpz` с https://github.com/godotengine/godot/releases/tag/4.4-stable (файл `Godot_v4.4-stable_export_templates.tpz` в Assets).
2. Распаковать так, чтобы файлы легли в `<user_data_dir>/export_templates/4.4.stable/` (сам `.tpz` — обычный zip с папкой `templates/` внутри — её содержимое переименовать/переместить в `4.4.stable`).
3. Либо открыть редактор Godot → Editor → Manage Export Templates → Install From File и указать скачанный `.tpz` — сделает то же самое.

## Сборка веб-версии (проверено, собирается)

```bash
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
```

Результат — статический набор файлов в `build/web/` (`index.html`, `index.js`, `index.wasm`, `index.pck`, иконки). Отдать любым статическим HTTP-сервером с поддержкой байтового `Range` (нужно WASM-рантайму), например:

```bash
cd build/web && python3 -m http.server 8000
```

и открыть `http://localhost:8000/index.html`. **Не** открывать `index.html` напрямую как `file://` — браузеры блокируют `fetch()` для `.wasm`/`.pck` с локального диска.

Пресет `Web` в `export_presets.cfg`: `GL Compatibility` (см. `[rendering]` в `project.godot` — `renderer/rendering_method="gl_compatibility"`), портретная ориентация наследуется из общих настроек проекта (у веб-пресета своей ориентации нет — это настройка страницы/канваса, а не экспорта).

Готовая сборка на момент сдачи лежит в `build/web/` (каталог в `.gitignore`, при необходимости пересобрать — команда выше).

## Сборка iOS (только на macOS — собрать на Linux невозможно)

Godot умеет **сгенерировать Xcode-проект** на любой ОС, но **скомпилировать и подписать `.ipa`** — только там, где есть `xcodebuild` и Xcode.app, то есть на macOS. На Linux команда экспорта преста `iOS` в этом репозитории целенаправленно дойдёт до стадии подготовки и остановится (нет `codesign`/`xcodebuild`) — это ожидаемо, не баг пресета.

### Требования

- macOS с установленным **Xcode** (актуальная версия, поддерживающая `application/min_ios_version="12.0"` из пресета — при необходимости поднять/опустить в `export_presets.cfg`).
- Аккаунт Apple Developer (для реальной подписи и загрузки в App Store) — **App Store Team ID**.
- Godot 4.4 с установленными iOS export-шаблонами (см. выше).

### Шаги

1. Открыть проект в Godot на macOS: `godot --path .` (или через `Godot.app`).
2. `Project → Export...` → выбрать пресет **iOS**.
3. В пресете уже заполнено: портрет (наследуется из `window/handheld/orientation=1` в `project.godot` — retina/масштаб экрана обеспечивает `stretch/mode=canvas_items` + `stretch/aspect=expand`, отдельного тумблера "retina" в iOS-пресете Godot 4.4 нет — это следствие тех же настроек стретча), `application/bundle_identifier="com.danlug.holidaydigger"`, `application/targeted_device_family=1` (iPhone).
4. Заполнить **обязательно** перед экспортом (иначе Godot откажется экспортировать с ошибкой валидации):
   - `application/app_store_team_id` — сейчас стоит заглушка `"YOUR_TEAM_ID"`, заменить на реальный Team ID из Apple Developer.
   - `application/code_sign_identity_debug` / `_release` — обычно `"iPhone Developer"` / `"iPhone Distribution"` (уже так стоит), но зависит от того, как называются сертификаты в вашей связке ключей (Keychain).
   - `application/provisioning_profile_uuid_debug` / `_release` — UUID профилей из Apple Developer Portal (или используйте автоматическое управление подписью в Xcode после генерации проекта — тогда эти поля можно оставить пустыми, Xcode сам подставит).
5. Экспортировать (кнопка Export Project либо, из терминала на macOS):
   ```bash
   mkdir -p build/ios
   godot --headless --path . --export-release "iOS" build/ios/holiday_digger.ipa
   ```
   Godot сначала сгенерирует Xcode-проект во временную папку и вызовет `xcodebuild`/`xcrun` для архивации и экспорта `.ipa` — это и есть шаг, недоступный на Linux.
6. Если нужна ручная сборка (например, для отладки на подключённом iPhone): открыть сгенерированный `.xcodeproj`/`.xcodeworkspace` в Xcode, выбрать команду/устройство, Product → Run.
7. **Иконки** — в пресете сейчас не заданы (см. `НЕ ТРОГАТЬ art/**` в задании этого агента: новые PNG под `icons/*` пресета не создавались). Godot подставит свою иконку по умолчанию. Перед подачей в App Store нужно:
   - добавить реальные иконки (`icons/icon_1024x1024`, `icons/iphone_120x120`, `icons/ipad_152x152` и т.д. — полный список ключей в `export_presets.cfg` под `[preset.1.options]`, доступные имена см. `godot --help`/документацию `EditorExportPlatformIOS`);
   - указать их пути в `export_presets.cfg` (относительно `res://`).
8. **App Store**: после успешной генерации `.ipa` — загрузка через Xcode Organizer или `xcrun altool`/`notarytool`/Transporter.app, требует действующего платного Apple Developer аккаунта, заполненной карточки приложения в App Store Connect (скриншоты, описание, возрастной рейтинг и т.д. — не задача этого агента).

### Известные ограничения пресета на момент сдачи

- `app_store_team_id` — заглушка, не настоящий Team ID.
- Провижининг-профили не указаны (пусты) — либо заполнить вручную, либо доверить автоматическому управлению подписью в Xcode.
- Иконки не заданы (используется дефолтная иконка Godot).
- `min_ios_version="12.0"` — не проверялось на реальных устройствах/симуляторе (нет macOS-хоста в этой среде разработки).

## Структура проекта (для навигации)

| Путь | Назначение |
|---|---|
| `scripts/core/` | `Balance` (числа из `data/*.json`), `GameState` (автозагрузки), `SaveSystem` |
| `scripts/world/` | `WorldGen` (генератор, не трогать), `TileTypes`, `FogOfWar`, `CollapseEvents`, `MineralMap`, `TileArt`, `WorldView` (рендер окна мира) |
| `scripts/player/` | `Player` (физика/копка/полёт), `CharacterView` (спрайт-анимация) |
| `scripts/ui/` | `HUD` (весь интерфейс, джойстик, шторка инвентаря) |
| `scripts/main.gd` | Оркестратор сцены `scenes/main.tscn` |
| `data/*.json` | Баланс (не трогать) |
| `docs/GDD.md` | Дизайн-документ (не трогать) |
| `web/index.html` | JS-эталон физики/ощущений (не трогать) |
| `tests/` | Headless-тесты |

### Нарезка присланного арта

Каждый лист от владельца нарезается своим скриптом — чтобы нарезку можно было повторить, когда лист поправят:

```bash
python3 tools/import_art.py     # персонажи и предметы
python3 tools/import_tiles.py   # породы
python3 tools/import_dig.py     # анимации копки
python3 tools/import_move.py    # ходьба, падение, полёт
python3 tools/import_drill.py   # ручной бур и бурмобиль
python3 tools/import_house.py   # дом бабки после смерти деда
```

Исходники лежат в `art/_source/`, результат — в `art/`. Скрипты не трогают ничего, кроме своих выходных файлов.

**После добавления нового скрипта с `class_name`** движок не увидит класс, пока не пересканирует проект: `godot --headless --editor --quit` один раз, иначе `--path . --quit` падает с «Identifier not declared».
