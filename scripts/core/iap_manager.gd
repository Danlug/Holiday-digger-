extends Node
## IAPManager — автозагрузка-каркас для внутриигровых покупок (App Store
## Connect / Google Play Billing). НЕ подключена ни к какому платёжному SDK:
## учётных данных разработчика на этой машине нет и быть не может (см.
## docs/MONETIZATION.md, раздел «Что дальше — только у владельца»).
##
## ВАЖНОЕ ПРАВИЛО ЭТОГО ФАЙЛА: ни один метод здесь не выдаёт награду и не
## подтверждает покупку. request_purchase() и restore_purchases() —
## заглушки, которые логируют вызов и завершаются сигналом отказа. Настоящая
## реализация подставит сюда вызов платформенного плагина (например,
## godot-google-play-billing / встроенный in-app-purchase модуль iOS) и
## будет эмитить purchase_completed ТОЛЬКО из подтверждённого коллбэка
## стора — никогда сразу после вызова request_purchase(). Подделывать
## успешную покупку здесь — то же самое, что дать бесплатный донат, а
## заявленная цель (см. задание владельца) — честная монетизация, не обман
## тестировщика и не дыра для будущего бага.
##
## Список товаров и цен — дизайн-предложение, а не решение владельца, и
## живёт в data/monetization.json (не здесь) — тот же приём, что у
## ShopCatalog со своим data/shop.json: числа не дублируются в коде.
##
## Зарегистрирован автозагрузкой (project.godot -> [autoload]), а не
## RefCounted-статикой вроде Settings/ShopCatalog, потому что этому классу
## нужны настоящие сигналы (purchase_completed и т.п.), а GDScript не умеет
## эмитить сигнал у класса без единственного живого экземпляра — тот же
## повод, по которому сигналы держит GameState, а не Settings. Как и у
## Balance/GameState/DayCycle, здесь нет отдельного class_name: имя
## автозагрузки (IAPManager) само становится глобальным идентификатором —
## объявленный поверх него class_name с тем же именем конфликтует с
## автозагрузкой ("Class hides an autoload singleton") и роняет весь скрипт.

signal purchase_started(product_id: String)
## reason содержит человекочитаемую причину отказа — в этой сборке всегда
## "нет платёжного SDK", но сигнатура уже такая, какая понадобится боевой
## реализации (отменил в сторе, сеть, уже куплено и т.п.).
signal purchase_failed(product_id: String, reason: String)
## Эмитится ТОЛЬКО настоящей интеграцией после подтверждения стора. В этой
## сборке не эмитится никогда — раз в коде появился слушатель этого
## сигнала, он безопасно ждёт покупку, которая по-честному никогда не
## придёт, пока не встанет реальный SDK.
signal purchase_completed(product_id: String)
## restore_purchases(): список product_id, которые сторе считает уже
## купленными этим аккаунтом. В заглушке всегда пустой массив.
signal purchases_restored(product_ids: Array)

const DATA_PATH := "res://data/monetization.json"

var _data: Dictionary = {}


func _ready() -> void:
	_data = _load_json(DATA_PATH)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("IAPManager: файл не найден: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("IAPManager: не удалось распарсить JSON: %s" % path)
		return {}
	return parsed


# ---------------------------------------------------------------------------
# Каталог (только чтение data/monetization.json — см. его для цен и грантов)
# ---------------------------------------------------------------------------

## Разовые/подписочные товары (антиреклама, чёрный ящик+1, подписки).
func iap_products() -> Array:
	return _data.get("iap_products", {}).get("items", [])


## Пачки долларов за реальные деньги (пока не продаются — см. dollar_packs
## в data/monetization.json, поле grants_dollars).
func dollar_packs() -> Array:
	return _data.get("dollar_packs", {}).get("items", [])


## Ищет товар по product_id среди iap_products() и dollar_packs() сразу —
## вызывающему коду (UI) не нужно знать, из какого он списка.
func product(product_id: String) -> Dictionary:
	for p in iap_products():
		if String(p.get("id", "")) == product_id:
			return p
	for p in dollar_packs():
		if String(p.get("product_id", "")) == product_id:
			return p
	return {}


## Уже ли активна подписка/владение product_id. Заглушка: реальных покупок
## не существует, поэтому всегда false. Настоящая реализация должна читать
## это из сохранённого и провалидированного стором состояния, не просто из
## локального флага (иначе сохранение можно подделать редактированием файла
## сейва — ровно то жульничество, которого этот файл избегает на уровне API).
func is_owned(_product_id: String) -> bool:
	return false


# ---------------------------------------------------------------------------
# Покупки — ЗАГЛУШКИ. Ничего не покупают, ничего не выдают.
# ---------------------------------------------------------------------------

## Инициирует покупку через платформенный SDK. В этой сборке SDK нет —
## сразу и честно отвечает отказом через purchase_failed, а не тишиной и не
## поддельным успехом. Реальная реализация: вызвать нативный плагин здесь,
## вернуться немедленно (сама покупка асинхронна), и уже из ЕГО коллбэка —
## только после проверки чека/квитанции стора — эмитить purchase_completed
## и уже тогда выдавать награду через GameState (add_dollars/grant_gear/…).
func request_purchase(product_id: String) -> void:
	purchase_started.emit(product_id)
	var p := product(product_id)
	if p.is_empty():
		push_warning("IAPManager.request_purchase: неизвестный product_id '%s'" % product_id)
		purchase_failed.emit(product_id, "неизвестный товар")
		return
	print("IAPManager: request_purchase('%s') — заглушка, платёжного SDK нет, покупка не выполняется" % product_id)
	purchase_failed.emit(product_id, "платежи не подключены в этой сборке")


## Восстановление покупок (обязательная кнопка на iOS — Apple отклоняет
## сборки без неё, если в игре есть неконсьюмерики/подписки). Заглушка:
## всегда возвращает пустой список, честно — восстанавливать нечего, пока
## нет SDK, который бы знал о прошлых покупках аккаунта.
func restore_purchases() -> void:
	print("IAPManager: restore_purchases() — заглушка, платёжного SDK нет")
	purchases_restored.emit([])
