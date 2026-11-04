class_name AboutCard
extends Control
## «О игре» (product-polish): логотип, версия приложения и метка сборки, политика
## конфиденциальности. Открывается из настроек (кнопка «i»), окно поверх шторки, закрывается
## крестиком и тапом мимо. Слова здесь сознательно: версия нужна владельцу и поддержке
## («какая у вас сборка?»), ссылка на политику — требование сторов и окна согласия (§16.1).
##
##   AboutCard.open_in(parent)          # parent — Control окна настроек
##   AboutCard.version_text()           # «1.0 · сборка 30.10 17:12 · a061256»

const WIDTH := 212.0          # 224 минус поля; внутри — логотип x2 (192)
const LOGO := "res://art/ui/brand/logo.png"
const LOGO_SCALE := 2
const BTN_H := 30.0

static var _instance: AboutCard = null

var _card: PanelContainer
var _closing := false


static func open_in(parent: Control) -> AboutCard:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var a := AboutCard.new()
	a.name = "About"
	parent.add_child(a)
	a.open()
	return a


static func instance() -> AboutCard:
	return _instance if _instance != null and is_instance_valid(_instance) else null


static func is_open_any() -> bool:
	var a := instance()
	return a != null and a.visible and not a._closing


## Версия из project.godot (application/config/version) и метка сборки из data/build_info.json.
static func version_text() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	var stamp := build_stamp()
	var parts: Array[String] = []
	if not v.is_empty():
		parts.append(v)
	if not stamp.is_empty():
		parts.append(stamp)
	return " · ".join(parts)


## «сборка 30.10 17:12 · a061256» — та же метка, что в меню «•••» (hud.gd), или пусто без файла.
static func build_stamp() -> String:
	var f := FileAccess.open("res://data/build_info.json", FileAccess.READ)
	if f == null:
		return ""
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	return pretty_stamp(String(raw.get("build", "")), String(raw.get("commit", "")))


static func pretty_stamp(build: String, commit: String = "") -> String:
	if build.is_empty():
		return ""
	var pretty := build
	if build.length() >= 13:   # 20260917-0413 -> 17.09 04:13
		pretty = "%s.%s %s:%s" % [build.substr(6, 2), build.substr(4, 2), build.substr(9, 2), build.substr(11, 2)]
	return "сборка %s%s" % [pretty, (" · " + commit) if not commit.is_empty() else ""]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _ready() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func is_open() -> bool:
	return visible and not _closing


func open() -> void:
	_closing = false
	visible = true
	Sfx.play("ui_open")
	UiAnim.open(_card, UiAnim.Kind.POP, self)


func close() -> void:
	if not is_open():
		return
	_closing = true
	Sfx.play("ui_close")
	UiAnim.close(_card, UiAnim.Kind.POP, self, queue_free)


# ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.scrim(self, close, UiTheme.SCRIM_SHEET)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.custom_minimum_size = Vector2(WIDTH, 0)
	_card.add_theme_stylebox_override("panel", ProgressUiKit.popup_box(UiTheme.GOLD_DIM, UiTheme.SHEET, 8))
	center.add_child(_card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_card.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var info := TextureRect.new()
	info.texture = UiIcons.tex("info")
	info.custom_minimum_size = Vector2(20, 20)
	info.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(info, "О игре")
	head.add_child(info)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	head.add_child(UiBtn.close_button(close))

	var logo := TextureRect.new()
	logo.name = "Logo"
	if ResourceLoader.exists(LOGO):
		logo.texture = load(LOGO)
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex_size := logo.texture.get_size() if logo.texture != null else Vector2(96, 68)
	logo.custom_minimum_size = tex_size * LOGO_SCALE
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(logo)

	var ver := ProgressUiKit.make_label(version_text(), UiTheme.FS_SMALL, UiTheme.TEXT_SOFT)
	ver.name = "Version"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tip.bind(ver, "Версия", "Назови её, если пишешь о проблеме")
	ver.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(ver)

	var engine := ProgressUiKit.make_label("Godot %s" % Engine.get_version_info().get("string", ""), UiTheme.FS_TINY, UiTheme.DIM)
	engine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	engine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(engine)

	var policy := UiBtn.text_button("Политика конфиденциальности", UiBtn.Kind.NORMAL, Vector2(0, BTN_H), UiTheme.FS_SMALL)
	policy.name = "Privacy"
	var url := ConsentDialog.privacy_url()
	policy.disabled = url.is_empty()
	Tip.bind(policy, "Политика конфиденциальности", "Откроется в браузере" if not url.is_empty() else "В этой сборке адрес не задан")
	policy.pressed.connect(func() -> void:
		if Tip.swallowed() or url.is_empty():
			return
		OS.shell_open(url))
	v.add_child(policy)
