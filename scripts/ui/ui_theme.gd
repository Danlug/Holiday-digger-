class_name UiTheme
extends RefCounted
## Один источник вида интерфейса: палитра, кегли, затемнение за окнами.
## Цвета мира, плиток и сгенерированной графики сюда не входят (art/PALETTE.md).
## Старые имена в китах (ProgressUiKit.GOLD, MetaUiKit.CARD, UiBtn.BORDER…) —
## ссылки сюда: поменять цвет = поменять одну строку ниже.

# --- Фоны (от тёмного к светлому) ---
const BG := Color(0.071, 0.055, 0.043, 0.97)       # полупрозрачная подложка экрана
const BG_SOLID := Color(0.071, 0.055, 0.043, 1.0)  # непрозрачная: сквозь неё не светится HUD
const INSET := Color(0.06, 0.05, 0.04)             # «утопленное»: канавки, дорожки полос
const PANEL_DARK := Color8(0x12, 0x0D, 0x0A)
const PANEL := Color(0.11, 0.09, 0.07, 1.0)
const SHEET := Color8(0x1A, 0x14, 0x0F)            # шторка и окно
const FLOAT_BG := Color8(0x1A, 0x14, 0x0F, 0xF5)   # тост и подсказка поверх мира
const CARD := Color8(0x1D, 0x17, 0x12)             # карточка/плитка внутри окна
const ROW := Color8(0x23, 0x1B, 0x14)              # строка списка, плитка отчёта
const BTN := Color8(0x26, 0x1E, 0x16)
const BTN_HOVER := Color8(0x34, 0x28, 0x1B)
const BTN_PRESS := Color8(0x1B, 0x15, 0x10)
const GOLD_BG := Color8(0x3A, 0x2C, 0x14)          # «готово, забирай»: карточка, день
const AD_BG := Color8(0x3C, 0x3A, 0x1A)            # кнопка «×2 за ролик»
const OK_BTN := Color8(0x2F, 0x6B, 0x3B)           # зелёная кнопка-призыв
const SHADOW := Color(0, 0, 0, 0.5)

# --- Рамки ---
const BORDER := Color8(0x3E, 0x31, 0x25)
const EDGE := Color8(0x52, 0x40, 0x2D)             # рамка приподнятого: кнопки, шторки, окна

# --- Текст (от яркого к тусклому) ---
const CREAM := Color8(0xF2, 0xE6, 0xC8)
const TEXT_HI := Color8(0xF2, 0xD9, 0x9B)          # заголовок, главное число
const TEXT := Color8(0xD8, 0xCF, 0xC0)
const TEXT_SOFT := Color8(0xB4, 0xA3, 0x88)
const MUTED := Color8(0x9D, 0x8B, 0x73)
const DIM := Color8(0x86, 0x76, 0x60)
const DISABLED := Color8(0x5A, 0x50, 0x44)
const INK := Color8(0x1A, 0x10, 0x0C)              # тёмное на золотом, обводка значков

# --- Акценты ---
const GOLD := Color8(0xE0, 0xA9, 0x3B)             # монеты, выбранное, главный акцент
const GOLD_DIM := Color8(0x9C, 0x76, 0x2C)
const GOLD_LIGHT := Color8(0xFF, 0xE0, 0x66)
const GOLD_BRIGHT := Color8(0xFF, 0xD8, 0x5A)
const GOLD_INK := Color8(0x6A, 0x3E, 0x0A)         # обводка надписей на золотых кнопках
const OK := Color8(0x7F, 0xB8, 0x6B)
const OK_LIGHT := Color8(0x7D, 0xE0, 0x8A)
const MONEY := Color8(0x4D, 0xE0, 0x94)            # доллары
const RED := Color8(0xB8, 0x5A, 0x52)              # «не хватает», приглушённый
const DANGER := Color8(0xD9, 0x4F, 0x4A)           # здоровье, бейдж-счётчик, «плохо»
const CRIMSON := Color8(0xC2, 0x1E, 0x3A)
const BAD_TEXT := Color8(0xE8, 0x8C, 0x80)         # «−5» в тостах
const BAD_LIGHT := Color8(0xFF, 0x6B, 0x6B)
const WARN := Color8(0xFF, 0x9A, 0x2E)
const BLUE := Color8(0x6E, 0x93, 0xA8)
const TEAL := Color8(0x6F, 0xE0, 0xD8)
const OLIVE := Color8(0x8F, 0xA3, 0x5C)
const HUNGER := Color8(0xE8, 0x7E, 0x6E)
const STAMINA := Color8(0xE8, 0xC5, 0x47)

# --- Ночная (фиолетовая) гамма магазина и склада ---
const NIGHT_DEEP := Color8(0x14, 0x0F, 0x1B)
const NIGHT_TOP := Color8(0x26, 0x1E, 0x30)
const NIGHT_SLOT := Color8(0x24, 0x1E, 0x2C)
const NIGHT_HI := Color8(0x2C, 0x24, 0x34)
const NIGHT_LINE := Color8(0x4A, 0x3F, 0x5C)
const NIGHT_RIM := Color8(0x6A, 0x62, 0x78)

# --- Затемнение за окнами: модальное окно глушит мир, шторка — слабее ---
const SCRIM_MODAL := 0.72
const SCRIM_SHEET := 0.6

# --- Кегли. Шрифт ещё выбирается: смена кеглей — правка здесь ---
const FS_MICRO := 6
const FS_TINY := 8
const FS_SMALL := 9
const FS_BODY := 10
const FS_LABEL := 11
const FS_TITLE := 12
const FS_TITLE_L := 13
const FS_HEAD := 14
const FS_HEAD_L := 15
const FS_HERO := 16
const FS_HERO_L := 18
const FS_BIG := 20
const FS_HUGE := 24
