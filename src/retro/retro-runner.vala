// This file is part of GNOME Games. License: GPLv3

private class Games.RetroRunner : Object, Runner {
	public bool can_resume {
		get {
			var file = File.new_for_path (snapshot_path);

			return file.query_exists ();
		}
	}

	private string _save_path;
	private string save_path {
		get {
			if (_save_path != null)
				return _save_path;

			var dir = Application.get_saves_dir ();
			_save_path = @"$dir/$uid.save";

			return _save_path;
		}
	}

	private string _snapshot_path;
	private string snapshot_path {
		get {
			if (_snapshot_path != null)
				return _snapshot_path;

			var dir = Application.get_snapshots_dir ();
			_snapshot_path = @"$dir/$uid.snapshot";

			return _snapshot_path;
		}
	}

	private string _screenshot_path;
	private string screenshot_path {
		get {
			if (_screenshot_path != null)
				return _screenshot_path;

			var dir = Application.get_snapshots_dir ();
			_screenshot_path = @"$dir/$uid.png";

			return _screenshot_path;
		}
	}

	private Retro.Core core;
	private RetroGtk.CairoDisplay video;
	private RetroGtk.PaPlayer audio;
	private RetroGtk.VirtualGamepad gamepad;
	private RetroGtk.Keyboard keyboard;
	private RetroGtk.InputDeviceManager input;
	private Retro.Options options;
	private RetroLog log;
	private Retro.Loop loop;

	private Gtk.EventBox widget;

	private string module_path;
	private string game_path;
	private string uid;

	private bool _running;
	private bool running {
		set {
			_running = value;

			video.sensitive = running;
		}
		get { return _running; }
	}

	private bool construction_succeeded;

	public RetroRunner (string module_basename, string game_path, string uid) throws RunError {
		construction_succeeded = false;

		this.module_path = Retro.search_module (module_basename);
		this.game_path = game_path;
		this.uid = uid;

		video = new RetroGtk.CairoDisplay ();

		widget = new Gtk.EventBox ();
		widget.add (video);
		video.visible = true;

		gamepad = new RetroGtk.VirtualGamepad (widget);
		keyboard = new RetroGtk.Keyboard (widget);

		prepare_core ();
		core.shutdown.connect (on_shutdown);

		core.run (); // Needed to finish preparing some cores.

		loop = new Retro.MainLoop (core);
		running = false;

		load_screenshot ();

		construction_succeeded = true;
	}

	~RetroRunner () {
		if (!construction_succeeded)
			return;

		loop.stop ();
		running = false;

		try {
			save ();
		}
		catch (RunError e) {
			warning (e.message);
		}
	}

	public Gtk.Widget get_display () {
		return widget;
	}

	public void start () throws RunError {
		loop.stop ();

		load_ram ();
		core.reset ();

		loop.start ();
		running = true;
	}

	public void resume () throws RunError {
		loop.stop ();

		load_ram ();
		core.reset ();
		load_snapshot ();

		loop.start ();
		running = true;
	}

	private void prepare_core () throws RunError {
		var module = File.new_for_path (module_path);
		if (!module.query_exists ()) {
			var msg = @"Couldn't run game: module '$module_path' not found.";

			throw new RunError.MODULE_NOT_FOUND (msg);
		}

		core = new Retro.Core (module_path);
		audio = new RetroGtk.PaPlayer ();
		input = new RetroGtk.InputDeviceManager ();
		options = new Retro.Options ();
		log = new RetroLog ();

		input.set_controller_device (0, gamepad);
		input.set_keyboard (keyboard);

		core.variables_interface = options;
		core.log_interface = log;

		core.video_interface = video;
		core.audio_interface = audio;
		core.input_interface = input;

		core.init ();

		if (!try_load_game (core, game_path))
			throw new RunError.INVALID_GAME_FILE (@"Invalid game file: $game_path");
	}

	private bool try_load_game (Retro.Core core, string game_name) {
		try {
			var fullpath = core.system_info.need_fullpath;
			if (core.load_game (fullpath ? Retro.GameInfo (game_name) : Retro.GameInfo.with_data (game_name))) {
				if (core.disk_control_interface != null) {
					var disk = core.disk_control_interface;

					disk.set_eject_state (true);

					while (disk.get_num_images () < 1)
						disk.add_image_index ();

					var index = disk.get_num_images () - 1;

					disk.replace_image_index (index, fullpath ? Retro.GameInfo (game_name) : Retro.GameInfo.with_data (game_name));

					disk.set_eject_state (false);
				}
				return true;
			}
		}
		catch (GLib.FileError e) {
			stderr.printf ("Error: %s\n", e.message);
		}
		catch (Retro.CbError e) {
			stderr.printf ("Error: %s\n", e.message);
		}

		return false;
	}

	public void pause () {
		loop.stop ();
		running = false;


		try {
			save ();
		}
		catch (RunError e) {
			warning (e.message);
		}
	}

	private void save () throws RunError {
		save_ram ();
		save_snapshot ();
		save_screenshot ();
	}

	private void save_ram () throws RunError{
		var save = core.get_memory (Retro.MemoryType.SAVE_RAM);
		if (save.length == 0)
			return;

		var dir = Application.get_saves_dir ();
		try_make_dir (dir);

		try {
			FileUtils.set_data (save_path, save);
		}
		catch (FileError e) {
			throw new RunError.COULDNT_WRITE_SAVE (@"Couldn't write save: $(e.message)");
		}
	}

	private void load_ram () throws RunError {
		if (!FileUtils.test (save_path, FileTest.EXISTS))
			return;

		uint8[] data = null;
		try {
			FileUtils.get_data (save_path, out data);
		}
		catch (FileError e) {
			throw new RunError.COULDNT_LOAD_SAVE (@"Couldn't load save: $(e.message)");
		}

		var expected_size = core.get_memory_size (Retro.MemoryType.SAVE_RAM);
		if (data.length != expected_size)
			warning ("Unexpected RAM data size: got %lu, expected %lu\n", data.length, expected_size);

		core.set_memory (Retro.MemoryType.SAVE_RAM, data);
	}

	private void save_snapshot () throws RunError {
		var size = core.serialize_size ();
		var buffer = new uint8[size];

		if (!core.serialize (buffer))
			throw new RunError.COULDNT_WRITE_SNAPSHOT ("Couldn't write snapshot.");

		var dir = Application.get_snapshots_dir ();
		try_make_dir (dir);

		try {
			FileUtils.set_data (snapshot_path, buffer);
		}
		catch (FileError e) {
			throw new RunError.COULDNT_WRITE_SNAPSHOT (@"Couldn't write snapshot: $(e.message)");
		}
	}

	private void load_snapshot () throws RunError {
		if (!FileUtils.test (snapshot_path, FileTest.EXISTS))
			return;

		uint8[] data = null;
		try {
			FileUtils.get_data (snapshot_path, out data);
		}
		catch (FileError e) {
			throw new RunError.COULDNT_LOAD_SNAPSHOT (@"Couldn't load snapshot: $(e.message)");
		}

		var expected_size = core.serialize_size ();
		if (data.length != expected_size)
			warning ("Unexpected serialization data size: got %lu, expected %lu\n", data.length, expected_size);

		if (!core.unserialize (data))
			throw new RunError.COULDNT_LOAD_SNAPSHOT ("Couldn't load snapshot.");
	}

	private void save_screenshot () throws RunError {
		var pixbuf = video.pixbuf;
		if (pixbuf == null)
			return;

		try {
			pixbuf.save (screenshot_path, "png");
		}
		catch (Error e) {
			throw new RunError.COULDNT_WRITE_SCREENSHOT(@"Couldn't write screenshot: $(e.message)");
		}
	}

	private void load_screenshot () throws RunError {
		if (!FileUtils.test (screenshot_path, FileTest.EXISTS))
			return;

		try {
			var pixbuf = new Gdk.Pixbuf.from_file (screenshot_path);
			video.pixbuf = pixbuf;
		}
		catch (Error e) {
			throw new RunError.COULDNT_LOAD_SCREENSHOT(@"Couldn't load screenshot: $(e.message)");
		}
	}

	private bool on_shutdown () {
		pause ();
		stopped ();

		return true;
	}

	private static void try_make_dir (string path) {
		var file = File.new_for_path (path);
		try {
			if (!file.query_exists ())
				file.make_directory_with_parents ();
		}
		catch (Error e) {
			warning (@"$(e.message)\n");

			return;
		}
	}
}

