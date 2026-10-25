extends Node
## AdManager — автозагрузка-каркас для rewarded-видео (баннеров/интерстишлов
## этот проект не планирует — см. docs/MONETIZATION.md: только добровольная
## реклама за награду). НЕ подключена ни к какой рекламной сети (AdMob,
## Unity Ads и т.п.) — учётной записи в сети нет.
##
## ВАЖНОЕ ПРАВИЛО ЭТОГО ФАЙЛА: show_rewarded_ad() ничего не показывает и не
## выдаёт награду. Настоящий рекламный SDK эмитит свой collбэк "зритель
## досмотрел до конца" — вот ТОЛЬКО ТОГДА полагается награда, и делает это
## вызывающий код (например scripts/shop/shop_service.gd:claim_ad — уже
## существующий, честный путь выдачи долларов/монет за ролик, см. заметку
## там же), а не эта заглушка сама по себе.
##
## В ТЕКУЩЕЙ СБОРКЕ реальная выдача награды за "ролик" уже идёт другим,
## более простым путём: ShopCatalog.ad_reward() + GameState.try_use_ad_reward()
## + ShopService.claim_ad() — без показа настоящего видео, потому что
## рекламной сети всё равно нет, а дневной лимит и сама механика награды уже
## решены владельцем (GDD раздел 15). AdManager здесь — на будущее, когда
## появится реальный SDK: тогда shop_service.claim_ad() должен звать
## AdManager.show_rewarded_ad(id) и слушать его ad_reward_earned вместо
## немедленной выдачи (см. docs/MONETIZATION.md, чек-лист интеграции). Пока
## это не сделано — обе системы существуют параллельно, не мешая друг
## другу: одна работает (без видео), другая — честный каркас под видео.
##
## Автозагрузка, а не RefCounted-статика — та же причина, что у IAPManager:
## нужны настоящие сигналы. Без отдельного class_name — по той же причине,
## что и у Balance/GameState/DayCycle/IAPManager (см. их комментарии):
## class_name с именем автозагрузки конфликтует с ней самой.

## Есть ли готовый к показу ролик для этой точки показа. Заглушка: всегда
## false — рекламной сети нет, значит и готового ролика нет и быть не может.
signal ad_availability_changed(placement_id: String, ready: bool)
signal ad_failed(placement_id: String, reason: String)
## Эмитится только настоящим SDK после честного досмотра ролика до конца.
## В этой сборке не эмитится никогда.
signal ad_reward_earned(placement_id: String)
signal ad_dismissed(placement_id: String)

const DATA_PATH := "res://data/monetization.json"

var _data: Dictionary = {}


func _ready() -> void:
	_data = _load_json(DATA_PATH)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("AdManager: файл не найден: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("AdManager: не удалось распарсить JSON: %s" % path)
		return {}
	return parsed


# ---------------------------------------------------------------------------
# Точки показа (только чтение data/monetization.json -> ad_placements)
# ---------------------------------------------------------------------------

## Все семь точек показа из ГДД раздела 15 (реализованные честной выдачей
## через ShopService.claim_ad и ещё не подключённые — см. поле "implemented").
func placements() -> Array:
	return _data.get("ad_placements", {}).get("items", [])


func placement(placement_id: String) -> Dictionary:
	for p in placements():
		if String(p.get("id", "")) == placement_id:
			return p
	return {}


# ---------------------------------------------------------------------------
# Показ ролика — ЗАГЛУШКА. Ничего не показывает, ничего не выдаёт.
# ---------------------------------------------------------------------------

## Всегда false в этой сборке: без рекламной сети готового ролика не бывает.
## Настоящая реализация должна опрашивать SDK (например, кэш загруженных
## roликов) и обновлять это сигналом ad_availability_changed по мере загрузки.
func is_ad_ready(_placement_id: String) -> bool:
	return false


## Запрашивает показ rewarded-ролика для точки placement_id. Всегда
## завершается ad_failed — честно, без подделки просмотра. Реальная
## реализация: вызвать нативный плагин рекламной сети здесь, вернуться
## немедленно, и уже из ЕГО коллбэка "досмотрено полностью" (не "закрыто
## досрочно" — это отдельный случай, см. ad_dismissed) — эмитить
## ad_reward_earned. Вызывающий код (например ShopService) выдаёт награду
## сам, слушая ad_reward_earned, а не читая возврат этой функции.
func show_rewarded_ad(placement_id: String) -> void:
	var p := placement(placement_id)
	if p.is_empty():
		push_warning("AdManager.show_rewarded_ad: неизвестная точка показа '%s'" % placement_id)
		ad_failed.emit(placement_id, "неизвестная точка показа")
		return
	print("AdManager: show_rewarded_ad('%s') — заглушка, рекламной сети нет, ролик не показан" % placement_id)
	ad_failed.emit(placement_id, "рекламная сеть не подключена в этой сборке")
