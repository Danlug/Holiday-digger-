class_name UiFmt
## Единый формат чисел в интерфейсе.
##   short(): 9999 -> «9999», 15300 -> «15.3к», 250000 -> «250к», 1250000 -> «1.2М»
##   full():  1234567 -> «1 234 567» — точное число для подсказок Tip.


static func short(n: int) -> String:
	var a := absi(n)
	var sign := "-" if n < 0 else ""
	if a < 10000:
		return sign + str(a)
	var unit := 1000
	var suf := "к"
	if a >= 1000000:
		unit = 1000000
		suf = "М"
	# целочисленно и с отбросом: не «1000к» и не больше, чем есть
	var tenths := a / (unit / 10)
	if tenths >= 1000 or tenths % 10 == 0:
		return sign + str(a / unit) + suf
	return sign + "%d.%d" % [tenths / 10, tenths % 10] + suf


static func full(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out    # обычный пробел: узкого U+202F в шрифте темы нет
	return ("-" if n < 0 else "") + out
