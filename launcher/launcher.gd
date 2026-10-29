extends Control
## Hide & Seek launcher. It asks GitHub for the latest release, downloads and
## installs it into a "game" folder next to the launcher, then starts the game.
## If GitHub can't be reached, the installed version can still be played.
##
## Command-line helpers (after `--`), used for testing:
##   --api=URL            release feed shaped like GitHub's "latest release" API
##   --install-dir=PATH   where to install the game
##   --quit-when-ready    exit once the game is installed and up to date
##   --screenshot=PATH    save a screenshot a moment after the check, then exit

const REPO := "Thyestee/Hide-Seek"
const ASSET_NAME := "Hide-Seek-windows.zip"
const VERSION_FILE := "version.txt"
const USER_AGENT := "User-Agent: Hide-Seek-Launcher"

const BG := Color(0.13, 0.2, 0.17)
const PANEL := Color(0.11, 0.12, 0.18, 0.95)
const ACCENT := Color(0.98, 0.72, 0.25)
const TEXT := Color(0.96, 0.95, 0.92)
const MUTED := Color(0.72, 0.74, 0.8)
const BAD := Color(1.0, 0.6, 0.5)

enum State { CHECKING, DOWNLOADING, INSTALLING, READY, ERROR }

var _state := State.CHECKING
var _api_url := "https://api.github.com/repos/%s/releases/latest" % REPO
var _install_dir := ""
var _installed_version := ""
var _latest_version := ""
var _asset_url := ""
var _asset_size := 0
var _game_pid := -1
var _args := {}

var _api: HTTPRequest
var _download: HTTPRequest
var _status: Label
var _version_label: Label
var _notes: RichTextLabel
var _progress: ProgressBar
var _play: Button
var _check: Button
var _close_on_play: CheckBox


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	_api_url = _args.get("api", _api_url)
	_install_dir = _args.get("install-dir", _pick_install_dir())
	_installed_version = _read_installed_version()

	_api = HTTPRequest.new()
	_api.timeout = 15.0
	_api.request_completed.connect(_on_release_info)
	add_child(_api)
	_download = HTTPRequest.new()
	_download.use_threads = true
	_download.download_chunk_size = 256 * 1024
	_download.request_completed.connect(_on_downloaded)
	add_child(_download)

	_build_ui()
	_check_for_updates()


func _process(_delta: float) -> void:
	if _state == State.DOWNLOADING:
		var total := _download.get_body_size()
		if total <= 0:
			total = _asset_size
		var done := _download.get_downloaded_bytes()
		if total > 0:
			_progress.value = 100.0 * done / total
			_status.text = "Downloading %s...  %.1f / %.1f MB" % [_latest_version, done / 1048576.0, total / 1048576.0]
	var running := _game_running()
	_play.disabled = _state != State.READY or running or _find_game_exe() == ""
	_play.text = "Running..." if running else "PLAY"
	_check.disabled = _state == State.CHECKING or _state == State.DOWNLOADING or _state == State.INSTALLING


# --- Update flow -------------------------------------------------------------

func _check_for_updates() -> void:
	_set_state(State.CHECKING, "Checking for updates...")
	if _api.request(_api_url, [USER_AGENT, "Accept: application/vnd.github+json"]) != OK:
		_offline("Couldn't start the update check.")


func _on_release_info(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_offline("Couldn't reach GitHub.")
		return
	if code == 404:
		_offline("No release has been published on GitHub yet.", "Push a version tag (see the README) to publish one.")
		return
	if code != 200:
		_offline("GitHub answered with error %d (too many checks? try again in a while)." % code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		_offline("GitHub sent an answer the launcher doesn't understand.")
		return
	_latest_version = str(data.get("tag_name", ""))
	var notes := str(data.get("body", "")).strip_edges()
	_notes.text = "%s\n\n%s" % [data.get("name", _latest_version), notes if notes != "" else "No release notes."]
	_asset_url = ""
	for asset in data.get("assets", []):
		if asset is Dictionary and asset.get("name") == ASSET_NAME:
			_asset_url = str(asset.get("browser_download_url", ""))
			_asset_size = int(asset.get("size", 0))
	if _asset_url == "":
		_offline("Release %s has no %s to download." % [_latest_version, ASSET_NAME])
	elif _latest_version == _installed_version and _find_game_exe() != "":
		_ready_to_play("Up to date.")
	elif _game_running():
		_set_state(State.READY, "Version %s is available. Close the game, then press Check for updates." % _latest_version)
	else:
		_start_download()


func _start_download() -> void:
	_set_state(State.DOWNLOADING, "Downloading %s..." % _latest_version)
	_progress.value = 0
	DirAccess.make_dir_recursive_absolute(_install_dir.get_base_dir())
	_download.download_file = _zip_path()
	if _download.request(_asset_url, [USER_AGENT]) != OK:
		_offline("Couldn't start the download.")


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(_zip_path())
		_offline("The download failed (%s)." % ("HTTP %d" % code if result == HTTPRequest.RESULT_SUCCESS else "network error %d" % result))
		return
	_set_state(State.INSTALLING, "Installing %s..." % _latest_version)
	_progress.value = 100
	await get_tree().process_frame
	var error := _install(_zip_path())
	DirAccess.remove_absolute(_zip_path())
	if error != "":
		_offline("Installing failed: %s." % error)
		return
	_installed_version = _latest_version
	_ready_to_play("Updated to %s." % _latest_version)


## Unpacks the release next to the old install, then swaps the folders so a
## failed update never leaves a half-installed game behind.
func _install(zip_path: String) -> String:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return "the download is not a valid zip file"
	var staging := _install_dir + ".new"
	_remove_tree(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	for path in reader.get_files():
		if path.begins_with("/") or ".." in path.split("/"):
			continue  # Never write outside the install folder.
		var target := staging.path_join(path)
		if path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(target)
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			return "couldn't write %s" % path
		file.store_buffer(reader.read_file(path))
		file.close()
	reader.close()
	var version_file := FileAccess.open(staging.path_join(VERSION_FILE), FileAccess.WRITE)
	version_file.store_string(_latest_version)
	version_file.close()

	if DirAccess.dir_exists_absolute(_install_dir):
		var old := _install_dir + ".old"
		_remove_tree(old)
		if DirAccess.rename_absolute(_install_dir, old) != OK:
			_remove_tree(staging)
			return "the old version is still in use (is the game running?)"
		_remove_tree(old)
	if DirAccess.rename_absolute(staging, _install_dir) != OK:
		return "couldn't move the new version into place"
	return ""


func _offline(reason: String, hint := "Check the internet connection and try again.") -> void:
	if _find_game_exe() != "":
		_ready_to_play("%s You can still play version %s." % [reason, _installed_version if _installed_version != "" else "?"], true)
	else:
		_set_state(State.ERROR, "%s The game isn't installed yet. %s" % [reason, hint])


func _ready_to_play(message: String, warning := false) -> void:
	_set_state(State.READY, message, warning)
	_progress.value = 100
	if _args.has("quit-when-ready"):
		get_tree().quit()


func _set_state(state: State, message: String, warning := false) -> void:
	_state = state
	_status.text = message
	_status.add_theme_color_override("font_color", BAD if warning or state == State.ERROR else TEXT)
	_progress.visible = state == State.DOWNLOADING or state == State.INSTALLING
	_version_label.text = "Installed: %s     Launcher: %s" % [
		_installed_version if _installed_version != "" else "none",
		ProjectSettings.get_setting("application/config/version", "dev"),
	]
	print("[launcher] ", message)
	if _args.has("screenshot") and state != State.CHECKING and state != State.DOWNLOADING and state != State.INSTALLING:
		_take_screenshot.call_deferred()


# --- Playing -----------------------------------------------------------------

func _play_game() -> void:
	var exe := _find_game_exe()
	if exe == "":
		return
	_game_pid = OS.create_process(exe, [])
	if _game_pid <= 0:
		_set_state(State.READY, "Couldn't start %s." % exe.get_file(), true)
	elif _close_on_play.button_pressed:
		get_tree().quit()


func _game_running() -> bool:
	return _game_pid > 0 and OS.is_process_running(_game_pid)


func _find_game_exe() -> String:
	var dir := DirAccess.open(_install_dir)
	if dir == null:
		return ""
	if dir.file_exists("Hide-Seek.exe"):
		return _install_dir.path_join("Hide-Seek.exe")
	for file in dir.get_files():
		if file.get_extension() in ["exe", "x86_64"]:
			return _install_dir.path_join(file)
	return ""


# --- Files -------------------------------------------------------------------

## Next to the launcher when possible, so the whole thing fits on a USB stick.
func _pick_install_dir() -> String:
	if not OS.has_feature("editor"):
		var beside := OS.get_executable_path().get_base_dir()
		if _is_writable(beside):
			return beside.path_join("game")
	return ProjectSettings.globalize_path("user://game")


func _is_writable(dir: String) -> bool:
	var probe := dir.path_join(".write_test")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	return true


func _read_installed_version() -> String:
	var file := FileAccess.open(_install_dir.path_join(VERSION_FILE), FileAccess.READ)
	return file.get_as_text().strip_edges() if file else ""


func _zip_path() -> String:
	return _install_dir + ".download.zip"


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := _label("HIDE & SEEK", 52, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	box.add_child(title)

	_status = _label("", 19)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 18)
	_progress.show_percentage = false
	box.add_child(_progress)

	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = false
	_notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes.add_theme_color_override("default_color", MUTED)
	_notes.add_theme_font_size_override("normal_font_size", 16)
	_notes.text = "Release notes will appear here."
	box.add_child(_notes)

	var info_row := HBoxContainer.new()
	box.add_child(info_row)
	_version_label = _label("", 14, MUTED)
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(_version_label)
	_close_on_play = CheckBox.new()
	_close_on_play.text = "Close launcher on play"
	_close_on_play.button_pressed = true
	info_row.add_child(_close_on_play)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_check = Button.new()
	_check.text = "Check for updates"
	_check.pressed.connect(_check_for_updates)
	row.add_child(_check)
	var folder := Button.new()
	folder.text = "Open game folder"
	folder.pressed.connect(func():
		DirAccess.make_dir_recursive_absolute(_install_dir)
		OS.shell_open(_install_dir)
	)
	row.add_child(folder)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_play = Button.new()
	_play.text = "PLAY"
	_play.custom_minimum_size = Vector2(200, 56)
	_play.add_theme_font_size_override("font_size", 26)
	_play.add_theme_stylebox_override("normal", _box(ACCENT.darkened(0.1), 12, 16))
	_play.add_theme_stylebox_override("hover", _box(ACCENT, 12, 16))
	_play.add_theme_color_override("font_color", Color(0.12, 0.1, 0.06))
	_play.add_theme_color_override("font_hover_color", Color(0.12, 0.1, 0.06))
	_play.pressed.connect(_play_game)
	row.add_child(_play)


func _label(text: String, size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 16, 24))
	t.set_stylebox("normal", "Button", _box(Color(0.24, 0.27, 0.38), 10, 14))
	t.set_stylebox("hover", "Button", _box(Color(0.32, 0.36, 0.5), 10, 14))
	t.set_stylebox("pressed", "Button", _box(ACCENT.darkened(0.2), 10, 14))
	t.set_stylebox("disabled", "Button", _box(Color(0.2, 0.21, 0.26), 10, 14))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	# CheckBox inherits Button's boxes unless it gets its own.
	for style in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(style, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", MUTED)
	t.set_color("font_hover_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", MUTED)
	t.set_color("font_hover_pressed_color", "CheckBox", TEXT)
	t.set_stylebox("background", "ProgressBar", _box(Color(0.06, 0.07, 0.1), 8, 0))
	t.set_stylebox("fill", "ProgressBar", _box(Color(0.4, 0.85, 0.45), 8, 0))
	t.set_stylebox("normal", "RichTextLabel", _box(Color(0.06, 0.07, 0.1, 0.6), 8, 12))
	return t


func _box(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin * 0.6
	box.content_margin_bottom = margin * 0.6
	return box


func _take_screenshot() -> void:
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(_args.screenshot)
	get_tree().quit()
