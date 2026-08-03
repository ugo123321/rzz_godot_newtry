extends CanvasLayer
## 云存档管理器：Firebase 匿名登录 + 本地存档 + Firestore 云同步 + 联网门控 + 删档重启。
## 注册顺序必须在 Firebase 与 LobbyState 之后（autoload 末尾）。
## 是 CanvasLayer（layer=100）以便把「联网门控」遮罩盖在主场景之上。

# === 测试开关 ============================================================
# true  : 连 Firebase 服务器（匿名登录 + Firestore 读写），启动必须联网通过门控
# false : 纯单机（不联网、不创建账号、不弹门控；仅本地存档；引擎内反复测试用）
const ONLINE: bool = true
# =========================================================================

const LOCAL_SAVE_PATH := "user://save.json"
const PLAYERS_COLLECTION := "players"
const MAIN_SCENE := "res://scenes/main.tscn"
# 去掉易混字符 O/0/I/1/L
const CODE_CHARSET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 4
const NAME_PREFIX := "player"
const SAVE_DEBOUNCE_SEC := 2.5
const LOGIN_TIMEOUT_SEC := 10.0
const AUTH_DELETE_TIMEOUT_SEC := 8.0

var _uid: String = ""                 # Firebase 匿名 uid（doc id）；ONLINE=false 时为空
var _cloud_ready: bool = false        # 在线登录 + 首次云档处理完成
var _dirty: bool = false
var _is_first_launch: bool = false    # 本次启动是否为「设备首次」（无本地存档）→ 发 GA4 game_install
var _save_timer: Timer
var _login_timeout: Timer

# GA4 Measurement Protocol（点亮 Analytics dashboard 的 DAU / 次留）
const GA4_ENDPOINT := "https://www.google-analytics.com/mp/collect"

# 联网门控 UI
var _gate: Control
var _gate_label: Label
var _gate_retry_btn: Button

var _delete_request_done := false     # 删 auth 账号的 auth_request 回调标志


func _ready() -> void:
	layer = 100
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SEC
	_save_timer.timeout.connect(_on_save_timer)
	add_child(_save_timer)

	_login_timeout = Timer.new()
	_login_timeout.one_shot = true
	_login_timeout.wait_time = LOGIN_TIMEOUT_SEC
	_login_timeout.timeout.connect(_on_login_timeout)
	add_child(_login_timeout)

	_build_gate()
	EventBus.language_changed.connect(_on_language_changed)

	# 1) 先读本地存档：立即恢复离线进度（无论 ONLINE）
	# 在读之前先判定「设备首次启动」（用于 GA4 game_install 标记新用户）
	_is_first_launch = not FileAccess.file_exists(LOCAL_SAVE_PATH)
	var local := _local_load()
	if not local.is_empty():
		if local.has("save"):
			LobbyState.apply_save_dict(local["save"])
		else:
			LobbyState.apply_save_dict(local)
	_ensure_player_code_and_name()
	LobbyState._emit_all_state()
	EventBus.player_profile_loaded.emit()

	_connect_dirty_signals()

	if not ONLINE:
		print("[CloudManager] OFFLINE 模式：仅本地存档，不联网、不弹门控。")
		return

	# 2) 在线：必须先通过联网门控
	_begin_login_flow()


# ─── GA4 Measurement Protocol：上报 session 事件点亮 Analytics dashboard ──
# client_id 用匿名 uid（跨启动稳定）→ GA4 据此算 DAU / 次留。
# 注意：first_open / user_engagement 是 GA4 保留事件名，MP 不允许直接发（NAME_RESERVED）；
# 用自定义事件名 + engagement_time_msec 参数即可让 GA4 计为活跃。首次启动多发 game_install 标记新用户。
func _ga4_report_session(is_first: bool) -> void:
	if not ONLINE or _uid == "":
		return
	var events: Array = []
	if is_first:
		events.append({"name": "game_install", "params": {"engagement_time_msec": 1000}})
	events.append({"name": "game_session", "params": {"engagement_time_msec": 1000}})
	_ga4_send(events)


func _ga4_send(events: Array) -> void:
	if events.is_empty():
		return
	var mid := _load_env_value("measurementId")
	var secret := _load_env_value("ga4ApiSecret")
	if mid == "" or secret == "":
		return  # GA4 未配置，静默跳过
	var url := "%s?measurement_id=%s&api_secret=%s" % [GA4_ENDPOINT, mid, secret]
	var body := {
		"client_id": _uid,
		"events": events,
	}
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	var err := http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return
	await http.request_completed
	http.queue_free()


func _load_env_value(key: String) -> String:
	var env := ConfigFile.new()
	if env.load("res://addons/godot-firebase/.env") == OK:
		return str(env.get_value("firebase/environment_variables", key, ""))
	return ""


# ─── 联网门控 ──────────────────────────────────────────────────────────
func _build_gate() -> void:
	_gate = Control.new()
	_gate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gate.mouse_filter = Control.MOUSE_FILTER_STOP
	_gate.visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_gate.add_child(bg)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -200
	box.offset_right = 200
	box.offset_top = -120
	box.offset_bottom = 120
	box.add_theme_constant_override("separation", 16)
	_gate.add_child(box)

	_gate_label = Label.new()
	_gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gate_label.add_theme_font_size_override("font_size", 20)
	_gate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gate_label.text = LanguageManager.tr_ui("UI_CLOUD_GATE_CONNECTING")
	box.add_child(_gate_label)

	_gate_retry_btn = Button.new()
	_gate_retry_btn.custom_minimum_size = Vector2(180, 0)
	_gate_retry_btn.visible = false
	_gate_retry_btn.pressed.connect(_on_gate_retry)
	box.add_child(_gate_retry_btn)

	add_child(_gate)

	_apply_gate_texts()


func _apply_gate_texts() -> void:
	if _gate_label:
		_gate_label.text = LanguageManager.tr_ui("UI_CLOUD_GATE_CONNECTING")
	if _gate_retry_btn:
		_gate_retry_btn.text = LanguageManager.tr_ui("UI_CLOUD_GATE_RETRY")


func _on_language_changed(_lang: String) -> void:
	_apply_gate_texts()


func _show_gate_connecting() -> void:
	if _gate == null:
		return
	_apply_gate_texts()
	if _gate_label:
		_gate_label.text = LanguageManager.tr_ui("UI_CLOUD_GATE_CONNECTING")
	if _gate_retry_btn:
		_gate_retry_btn.visible = false
	_gate.visible = true


func _show_gate_failed() -> void:
	if _gate == null:
		return
	_apply_gate_texts()
	if _gate_label:
		_gate_label.text = LanguageManager.tr_ui("UI_CLOUD_GATE_FAILED")
	if _gate_retry_btn:
		_gate_retry_btn.visible = true
	_gate.visible = true


func _hide_gate() -> void:
	if _gate:
		_gate.visible = false


func _on_gate_retry() -> void:
	_begin_login_flow()


func _begin_login_flow() -> void:
	if Firebase == null or Firebase.Auth == null:
		push_warning("[CloudManager] Firebase autoload 不可用。")
		_show_gate_failed()
		return
	if not Firebase.Auth.login_succeeded.is_connected(_on_login_succeeded):
		Firebase.Auth.login_succeeded.connect(_on_login_succeeded)
	# login_anonymous 走 signUp 端点 → 插件 emit 的是 signup_succeeded（不是 login_succeeded），
	# 必须一并接上，否则首次匿名登录成功但无人响应 → 超时。
	if not Firebase.Auth.signup_succeeded.is_connected(_on_login_succeeded):
		Firebase.Auth.signup_succeeded.connect(_on_login_succeeded)
	if not Firebase.Auth.login_failed.is_connected(_on_login_failed):
		Firebase.Auth.login_failed.connect(_on_login_failed)

	_show_gate_connecting()
	if _login_timeout:
		_login_timeout.start(LOGIN_TIMEOUT_SEC)

	# 有 user.auth 就复用旧 uid（不堆垃圾账号），否则 login_anonymous 新建。
	# 自己先判文件存在再调 check_auth_file，避免插件在无文件时打噪声 ERROR + 发无用 auth_request。
	if FileAccess.file_exists("user://user.auth"):
		# check_auth_file → load_auth → manual_token_refresh → login_succeeded / login_failed
		Firebase.Auth.check_auth_file()
	else:
		print("[CloudManager] 无本地 auth 文件，发起匿名登录…")
		Firebase.Auth.login_anonymous()


func _on_login_timeout() -> void:
	# 登录超时仍未就绪 → 视为连不上
	if not _cloud_ready:
		print("[CloudManager] 登录超时（%ss），判为无法连接服务器。" % str(LOGIN_TIMEOUT_SEC))
		_show_gate_failed()


# ─── 登录回调 ──────────────────────────────────────────────────────────
func _on_login_succeeded(auth_result: Dictionary) -> void:
	# token 自动刷新时也会 emit login_succeeded；已就绪则只更新 auth（addon 内部），不重复拉档
	if _cloud_ready:
		return
	if _login_timeout:
		_login_timeout.stop()
	# auth_result 键名被 get_clean_keys 小写、去下划线：localid / idtoken / refreshtoken / expiresin
	var lid := str(auth_result.get("localid", auth_result.get("userid", "")))
	if lid == "":
		print("[CloudManager] 登录成功但未拿到 localid。")
		_show_gate_failed()
		return
	_uid = lid
	# 落盘 auth 文件（复用同一 uid 跨启动）
	Firebase.Auth.save_auth(auth_result)
	print("[CloudManager] 匿名登录成功 uid=%s" % _uid)
	# 上报 GA4 会话事件（点亮 DAU / 次留；client_id = uid 跨会话稳定）
	_ga4_report_session(_is_first_launch)
	# 登录即视为「已连上」→ 收起门控，放行
	_hide_gate()
	_ensure_cloud_profile_then_load()


func _on_login_failed(code, message) -> void:
	if _login_timeout:
		_login_timeout.stop()
	print("[CloudManager] 登录失败 code=%s msg=%s" % [str(code), str(message)])
	_show_gate_failed()


# 拉/建云端档案，读回存档覆盖本地
func _ensure_cloud_profile_then_load() -> void:
	if _uid == "":
		return
	var coll = Firebase.Firestore.collection(PLAYERS_COLLECTION)
	var doc = await coll.get_doc(_uid)
	var cloud_code := ""
	var cloud_save: Dictionary = {}
	if doc is FirestoreDocument and doc != null:
		var data: Dictionary = doc.get_unsafe_document()
		cloud_code = str(data.get("code", ""))
		cloud_save = data.get("save", {})
	else:
		print("[CloudManager] 云端无档案，新建 players/%s" % _uid)

	if cloud_code == "":
		# 云端无 code：若本地已有 code 就用它，否则生成
		if LobbyState.player_code == "":
			LobbyState.player_code = _generate_code()
		cloud_code = LobbyState.player_code
		LobbyState.player_name = NAME_PREFIX + cloud_code
		await _cloud_save({
			"code": cloud_code,
			"save": LobbyState.to_save_dict(),
			"created_at": int(Time.get_unix_time_from_system()),
			"updated_at": int(Time.get_unix_time_from_system()),
		})
	else:
		# 云端有档案：code 以云端为准（跨设备稳定）
		LobbyState.player_code = cloud_code
		LobbyState.player_name = NAME_PREFIX + cloud_code
		if not cloud_save.is_empty():
			LobbyState.apply_save_dict(cloud_save)

	LobbyState._emit_all_state()
	EventBus.player_profile_loaded.emit()
	_cloud_ready = true
	# 读回后若有未保存的本地改动，触发一次同步
	_mark_dirty()


# ─── 防抖保存 ──────────────────────────────────────────────────────────
func _connect_dirty_signals() -> void:
	if EventBus == null:
		return
	for sig in [
		EventBus.gold_changed,
		EventBus.energy_changed,
		EventBus.enhance_gem_changed,
		EventBus.wood_changed,
		EventBus.equipment_changed,
		EventBus.skill_stones_changed,
		EventBus.talent_changed,
		EventBus.stage_cleared,
		EventBus.scout_claimed,
	]:
		if not sig.is_connected(_mark_dirty):
			sig.connect(_mark_dirty)


func _mark_dirty(_a = null, _b = null, _c = null) -> void:
	_dirty = true
	if _save_timer:
		_save_timer.start(SAVE_DEBOUNCE_SEC)


func _on_save_timer() -> void:
	if not _dirty:
		return
	_dirty = false
	_flush_save()


func _flush_save() -> void:
	if LobbyState == null:
		return
	var save_data := LobbyState.to_save_dict()
	var local_doc := {
		"code": LobbyState.player_code,
		"save": save_data,
		"updated_at": int(Time.get_unix_time_from_system()),
	}
	_local_save(local_doc)
	if ONLINE and _cloud_ready and _uid != "":
		_cloud_save({
			"code": LobbyState.player_code,
			"save": save_data,
			"updated_at": int(Time.get_unix_time_from_system()),
		})


# 强制存盘（退出/低内存）— 防抖未到也得存
func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_CLOSE_REQUEST \
			or what == MainLoop.NOTIFICATION_OS_MEMORY_WARNING:
		if _dirty:
			_dirty = false
			_flush_save()
	# App 从后台回前台：体力随墙钟推导，立即 emit 让主菜单 UI 刷新显示（不写云）。
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
		if LobbyState != null and EventBus != null:
			EventBus.energy_changed.emit(LobbyState.get_energy_display(), LobbyState.ENERGY_MAX)


# ─── 删档重启 ──────────────────────────────────────────────────────────
# 删云端 doc + 删 Firebase 匿名账号 + 删本地存档 → 重置为新玩家 → 重新登录拿新 uid
func delete_account_and_restart() -> void:
	print("[CloudManager] 开始删档重启…")
	_cloud_ready = false
	_dirty = false
	if _save_timer:
		_save_timer.stop()
	if _login_timeout:
		_login_timeout.stop()

	# 1) 删云端 doc
	if ONLINE and _uid != "" and Firebase != null and Firebase.Firestore != null:
		var coll = Firebase.Firestore.collection(PLAYERS_COLLECTION)
		var doc = await coll.get_doc(_uid)
		if doc is FirestoreDocument and doc != null:
			await coll.delete(doc)
		# 2) 删 Firebase Auth 账号（用当前 idToken）
		await _delete_auth_account(AUTH_DELETE_TIMEOUT_SEC)

	# 3) 删本地存档 + auth 文件
	_delete_local_save()
	if Firebase != null and Firebase.Auth != null:
		Firebase.Auth.remove_auth()

	# 4) 重置状态 + 新玩家
	_uid = ""
	_is_first_launch = true  # 删档后视为新安装 → 重新发 GA4 game_install 标记新用户
	LobbyState._reset_to_new_player()
	EventBus.player_profile_loaded.emit()

	# 5) 重新登录拿新 uid（在线则过门控），同时换场景让 UI 干净复位
	if ONLINE:
		_show_gate_connecting()
	get_tree().change_scene_to_file(MAIN_SCENE)
	await get_tree().process_frame  # 等场景切换生效
	if ONLINE:
		_begin_login_flow()


# 等 delete_user_account 的 auth_request 回调或超时
func _delete_auth_account(timeout_sec: float) -> void:
	if Firebase == null or Firebase.Auth == null:
		return
	# 先等任何在飞行的请求结束
	var t := 0.0
	while Firebase.Auth.is_busy and t < 3.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	_delete_request_done = false
	var callable := Callable(self, "_on_delete_auth_request")
	Firebase.Auth.auth_request.connect(callable, CONNECT_ONE_SHOT)
	Firebase.Auth.delete_user_account()
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000)
	while not _delete_request_done and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	if not _delete_request_done:
		if Firebase.Auth.auth_request.is_connected(callable):
			Firebase.Auth.auth_request.disconnect(callable)
		print("[CloudManager] 删 auth 账号超时。")


func _on_delete_auth_request(_code, _content) -> void:
	_delete_request_done = true


# ─── 本地存档 ──────────────────────────────────────────────────────────
func _local_save(data: Dictionary) -> void:
	var f := FileAccess.open(LOCAL_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[CloudManager] 写本地存档失败: %s" % str(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data))
	f.close()


func _local_load() -> Dictionary:
	if not FileAccess.file_exists(LOCAL_SAVE_PATH):
		return {}
	var f := FileAccess.open(LOCAL_SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _delete_local_save() -> void:
	if FileAccess.file_exists(LOCAL_SAVE_PATH):
		DirAccess.remove_absolute(LOCAL_SAVE_PATH)


# ─── 云端存档 ──────────────────────────────────────────────────────────
func _cloud_save(data: Dictionary) -> void:
	await Firebase.Firestore.collection(PLAYERS_COLLECTION).set_doc(StringName(_uid), data)


# ─── 编号生成 ──────────────────────────────────────────────────────────
func _generate_code() -> String:
	var code := ""
	for i in CODE_LENGTH:
		code += CODE_CHARSET[randi() % CODE_CHARSET.length()]
	return code


func _ensure_player_code_and_name() -> void:
	if LobbyState.player_code == "":
		LobbyState.player_code = _generate_code()
	if LobbyState.player_name == "" or LobbyState.player_name == "player001":
		LobbyState.player_name = NAME_PREFIX + LobbyState.player_code
