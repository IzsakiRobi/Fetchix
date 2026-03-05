using Gtk;
using Adw;
using Soup;
using Json;
using GLib;

public class AppSettings : GLib.Object {
    public string download_dir;
    public int max_threads;
    public bool auto_resize;
    public bool remember_downloads;
    public bool autostart_downloads;
    
    private string config_dir;
    public string session_path;
    private string config_path;
    
    public KeyFile progress_db;
    public string progress_path;

    public AppSettings() {
        config_dir = Environment.get_user_config_dir() + "/Fetchix";
        config_path = config_dir + "/settings.ini";
        session_path = config_dir + "/session.dat";
        progress_path = config_dir + "/progress.ini";

        try {
            var dir = GLib.File.new_for_path(config_dir);
            if (!dir.query_exists()) dir.make_directory_with_parents(null);

            var sess = GLib.File.new_for_path(session_path);
            if (!sess.query_exists()) sess.create(FileCreateFlags.NONE, null).close();
        } catch (Error e) {}

        progress_db = new KeyFile();
        try { progress_db.load_from_file(progress_path, KeyFileFlags.NONE); } catch (Error e) {}

        load();
    }

    public void load() {
        var kf = new KeyFile();
        try {
            kf.load_from_file(config_path, KeyFileFlags.NONE);
            download_dir = kf.get_string("Downloads", "Dir");
        } catch (Error e) {
            download_dir = Environment.get_user_special_dir(UserDirectory.DOWNLOAD);
            if (download_dir == null) download_dir = Environment.get_home_dir();
        }

        try { max_threads = kf.get_integer("Downloads", "Threads");
        } catch (Error e) { max_threads = 1; }
        try { auto_resize = kf.get_boolean("UI", "AutoResize");
        } catch (Error e) { auto_resize = false; }
        try { remember_downloads = kf.get_boolean("System", "RememberDownloads");
        } catch (Error e) { remember_downloads = true; }
        try { autostart_downloads = kf.get_boolean("System", "AutostartDownloads");
        } catch (Error e) { autostart_downloads = true; }
    }

    public void save() {
        var kf = new KeyFile();
        kf.set_string("Downloads", "Dir", download_dir);
        kf.set_integer("Downloads", "Threads", max_threads);
        kf.set_boolean("UI", "AutoResize", auto_resize);
        kf.set_boolean("System", "RememberDownloads", remember_downloads);
        kf.set_boolean("System", "AutostartDownloads", autostart_downloads);
        try { kf.save_to_file(config_path);
        } catch (Error e) {}
    }

    public void save_progress(HashTable<string, DownloadRow> rows) {
        var kf = new KeyFile();
        foreach (unowned string gid in rows.get_keys()) {
            var row = rows.lookup(gid);
            kf.set_int64(gid, "completed", row.current_completed);
            kf.set_int64(gid, "total", row.current_total);
        }
        try { kf.save_to_file(progress_path);
        } catch (Error e) {}
    }
}

string format_bytes(int64 bytes) {
    if (bytes < 1024) return "%lld B".printf(bytes);
    if (bytes < 1048576) return "%.1f KB".printf(bytes / 1024.0);
    if (bytes < 1073741824) return "%.2f MB".printf(bytes / 1048576.0);
    return "%.2f GB".printf(bytes / 1073741824.0);
}

string format_time(int64 seconds) {
    if (seconds <= 0) return "";
    if (seconds < 60) return "%llds".printf(seconds);
    if (seconds < 3600) return "%lldm %llds".printf(seconds / 60, seconds % 60);
    return "%lldh %lldm".printf(seconds / 3600, (seconds % 3600) / 60);
}

string get_asset_path(string filename) {
    if (GLib.FileUtils.test("/.flatpak-info", GLib.FileTest.EXISTS)) {
        return "/app/share/Fetchix/Assets/" + filename;
    } else {
        return Environment.get_home_dir() + "/.local/share/Fetchix/Assets/" + filename;
    }
}

GLib.Icon get_icon_for_url(string url) {
    if (url.has_prefix("magnet:")) return new GLib.ThemedIcon("application-x-bittorrent");
    string clean_url = url.split("?")[0];
    string basename = GLib.Path.get_basename(clean_url);
    bool uncertain;
    string ctype = ContentType.guess(basename, null, out uncertain);
    return ContentType.get_icon(ctype);
}

public class DownloadRow : Gtk.ListBoxRow {
    public string gid;
    public Gtk.Label name_label;
    public Gtk.Label status_label;
    public Gtk.ProgressBar progress;
    public Gtk.Button pause_btn;
    public Gtk.Button stop_btn;
    
    public bool is_finished = false;
    public bool is_paused = false;
    public string last_status = "";
    
    public int64 current_completed = 0;
    public int64 current_total = 0;

    public signal void on_pause_toggled(string gid, bool pause_requested);
    public signal void on_cancel(string gid);

    public DownloadRow(string gid, string title) {
        this.gid = gid;
        
        this.set_tooltip_text(title);

        var box = new Gtk.Box(Orientation.HORIZONTAL, 12);
        box.margin_top = 8; box.margin_bottom = 8;
        box.margin_start = 12; box.margin_end = 12;
        box.set_size_request(-1, 56);

        var icon = new Gtk.Image.from_gicon(get_icon_for_url(title));
        icon.pixel_size = 32;

        var text_box = new Gtk.Box(Orientation.VERTICAL, 4);
        text_box.hexpand = true;
        text_box.valign = Align.CENTER;

        name_label = new Gtk.Label(title);
        name_label.halign = Align.START;
        name_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        name_label.lines = 1;
        name_label.add_css_class("heading");

        status_label = new Gtk.Label("Loading...");
        status_label.halign = Align.START;
        status_label.ellipsize = Pango.EllipsizeMode.END;
        status_label.lines = 1; 
        status_label.add_css_class("dim-label");
        status_label.add_css_class("numeric-label");
        status_label.add_css_class("small-status"); 

        text_box.append(name_label);
        text_box.append(status_label);

        progress = new Gtk.ProgressBar();
        progress.valign = Align.CENTER;
        progress.width_request = 80;

        var btn_box = new Gtk.Box(Orientation.HORIZONTAL, 6);
        btn_box.valign = Align.CENTER;

        pause_btn = new Gtk.Button.from_icon_name("media-playback-pause-symbolic");
        pause_btn.add_css_class("circular");
        stop_btn = new Gtk.Button.from_icon_name("window-close-symbolic");
        stop_btn.add_css_class("circular");

        pause_btn.clicked.connect(() => {
            is_paused = !is_paused;
            pause_btn.set_icon_name(is_paused ? "media-playback-start-symbolic" : "media-playback-pause-symbolic");
            on_pause_toggled(this.gid, is_paused);
        });

        stop_btn.clicked.connect(() => { on_cancel(this.gid); });

        btn_box.append(pause_btn);
        btn_box.append(stop_btn);

        box.append(icon);
        box.append(text_box);
        box.append(progress);
        box.append(btn_box);

        set_child(box);
    }

    public void update_status(string status, int64 completed, int64 total, int64 speed, int64 eta) {
        if (total > 0) {
            this.current_completed = completed;
            this.current_total = total;
        }

        int64 display_comp = (total > 0) ? completed : this.current_completed;
        int64 display_tot = (total > 0) ? total : this.current_total;

        if (display_tot > 0) {
            progress.set_fraction((double)display_comp / (double)display_tot);
        } else {
            progress.set_fraction(0.0);
        }

        if (status != last_status) {
            progress.remove_css_class("success-bar");
            progress.remove_css_class("paused-bar");
            
            if (status == "complete") {
                progress.add_css_class("success-bar");
            } else if (status == "paused") {
                progress.add_css_class("paused-bar");
            }
            last_status = status;
        }

        if (status == "complete") {
            status_label.set_markup("Completed");
            is_finished = true;
            pause_btn.sensitive = false;
        } else if (status == "paused") {
            is_paused = true;
            pause_btn.set_icon_name("media-playback-start-symbolic");
            if (display_tot > 0) {
                status_label.set_markup("Paused - %s of %s".printf(format_bytes(display_comp), format_bytes(display_tot)));
            } else {
                status_label.set_markup("Paused");
            }
        } else if (status == "error") {
            status_label.set_markup("Error");
            is_finished = true;
            pause_btn.sensitive = false;
        } else {
            is_paused = false;
            pause_btn.set_icon_name("media-playback-pause-symbolic");
            string eta_str = (eta > 0) ? " - <span foreground='#3584e4' weight='bold'>" + format_time(eta) + " left</span>" : "";
            
            if (display_tot > 0) {
                status_label.set_markup("%s of %s at %s/s%s".printf(format_bytes(display_comp), format_bytes(display_tot), format_bytes(speed), eta_str));
            } else {
                status_label.set_markup("%s downloaded at %s/s".printf(format_bytes(display_comp), format_bytes(speed)));
            }
        }
    }
}

public class FetchixManager : GLib.Object {
    private Soup.Session session;
    private string rpc_url = "http://localhost:6800/jsonrpc";
    public bool is_running = false;

    public FetchixManager() {
        session = new Soup.Session();
    }

    public async void wait_ms(uint ms) {
        Timeout.add(ms, () => {
            wait_ms.callback();
            return false;
        });
        yield;
    }

    public async void ensure_started(string sess_path) {
        if (!is_running) {
            for (int i = 0; i < 30; i++) {
                var check = yield call_rpc("aria2.getVersion");
                if (check != null) {
                    yield wait_ms(500);
                } else {
                    break;
                }
            }

            try {
                string cmd = "aria2c --enable-rpc --rpc-listen-all=false --input-file='%s' --save-session='%s' --save-session-interval=30".printf(sess_path, sess_path);
                Process.spawn_command_line_async(cmd);
                
                for (int i = 0; i < 20; i++) {
                    yield wait_ms(250);
                    var verify = yield call_rpc("aria2.getVersion");
                    if (verify != null) {
                        is_running = true;
                        break;
                    }
                }
            } catch (Error e) {}
        }
    }

    public async Json.Node? call_rpc(string method, string? params_json = null) {
        var msg = new Soup.Message("POST", rpc_url);
        string json_data = "{\"jsonrpc\":\"2.0\",\"id\":\"Fetchix\",\"method\":\"%s\"%s}".printf(
            method, params_json != null ? ",\"params\":" + params_json : "");
        msg.set_request_body_from_bytes("application/json", new Bytes(json_data.data));
        try {
            var response = yield session.send_and_read_async(msg, Priority.DEFAULT, null);
            unowned uint8[] data = response.get_data();
            var parser = new Json.Parser();
            parser.load_from_data((string)data);
            return parser.get_root();
        } catch (Error e) {
            return null;
        }
    }

    public async string? add_uri(string uri, string dir, int threads) {
        string options_json = "{\"dir\":\"%s\",\"split\":\"%d\",\"max-connection-per-server\":\"%d\",\"min-split-size\":\"1M\"}".printf(
            dir.replace("\"", "\\\""), threads, threads);
        string params_json = "[[\"%s\"], %s]".printf(uri, options_json);
        var root = yield call_rpc("aria2.addUri", params_json);
        if (root != null && root.get_object().has_member("result")) {
            return root.get_object().get_string_member("result");
        }
        return null;
    }

    public async bool pause_download(string gid) {
        yield call_rpc("aria2.pause", "[\"%s\"]".printf(gid));
        return true;
    }

    public async bool resume_download(string gid) {
        yield call_rpc("aria2.unpause", "[\"%s\"]".printf(gid));
        return true;
    }

    public async bool force_remove_download(string gid) {
        yield call_rpc("aria2.forceRemove", "[\"%s\"]".printf(gid));
        return true;
    }

    public async bool remove_download_result(string gid) {
        yield call_rpc("aria2.removeDownloadResult", "[\"%s\"]".printf(gid));
        return true;
    }

    public async void force_shutdown() {
        if (!is_running) return;
        yield call_rpc("aria2.saveSession");
        yield call_rpc("aria2.forceShutdown");
    }
}

public class SettingsDialog : Adw.Window {
    public AppSettings settings;
    private FetchixApp main_app;

    public SettingsDialog(FetchixApp app, AppSettings app_settings) {
        GLib.Object(application: app);
        this.main_app = app;
        this.settings = app_settings;
        
        this.title = "Preferences";
        this.set_default_size(450, -1);
        this.resizable = false;

        var main_box = new Gtk.Box(Orientation.VERTICAL, 0);
        var header = new Adw.HeaderBar();
        header.add_css_class("flat"); 
        main_box.append(header);

        var content_box = new Gtk.Box(Orientation.VERTICAL, 24);
        content_box.margin_top = 24; content_box.margin_bottom = 24;
        content_box.margin_start = 24; content_box.margin_end = 24;

        var pref_group = new Adw.PreferencesGroup();
        pref_group.title = "Download Options";

        var folder_row = new Adw.ActionRow();
        folder_row.title = "Save Folder";
        folder_row.subtitle = settings.download_dir;
        
        var browse_btn = new Gtk.Button.with_label("Browse...");
        browse_btn.valign = Align.CENTER;
        browse_btn.clicked.connect(() => {
            var dialog = new Gtk.FileDialog();
            dialog.title = "Select Download Folder";
            dialog.select_folder.begin(this, null, (obj, res) => {
                try {
                    var file = dialog.select_folder.end(res);
                    if (file != null) folder_row.subtitle = file.get_path();
                } catch (Error e) {}
            });
        });
        folder_row.add_suffix(browse_btn);

        var thread_row = new Adw.ActionRow();
        thread_row.title = "Parallel Connections (1-9)";
        var spin = new Gtk.SpinButton.with_range(1, 9, 1);
        spin.valign = Align.CENTER;
        spin.value = settings.max_threads;
        thread_row.add_suffix(spin);

        var resize_row = new Adw.ActionRow();
        resize_row.title = "Auto-resize Window";
        resize_row.subtitle = "Adjust window height to fit the list";
        var resize_switch = new Gtk.Switch();
        resize_switch.valign = Align.CENTER;
        resize_switch.active = settings.auto_resize;
        resize_row.add_suffix(resize_switch);

        var remember_row = new Adw.ActionRow();
        remember_row.title = "Remember Downloads";
        remember_row.subtitle = "Save progress and continue later";
        var remember_switch = new Gtk.Switch();
        remember_switch.valign = Align.CENTER;
        remember_switch.active = settings.remember_downloads;
        remember_row.add_suffix(remember_switch);

        var autostart_row = new Adw.ActionRow();
        autostart_row.title = "Autostart Downloads";
        autostart_row.subtitle = "Resume active downloads on startup";
        var autostart_switch = new Gtk.Switch();
        autostart_switch.valign = Align.CENTER;
        autostart_switch.active = settings.autostart_downloads;
        autostart_row.add_suffix(autostart_switch);

        pref_group.add(folder_row);
        pref_group.add(thread_row);
        pref_group.add(resize_row);
        pref_group.add(remember_row);
        pref_group.add(autostart_row);
        content_box.append(pref_group);

        var btn_box = new Gtk.Box(Orientation.HORIZONTAL, 12);
        btn_box.halign = Align.CENTER;
        btn_box.valign = Align.END;
        btn_box.vexpand = true;

        var cancel_btn = new Gtk.Button.with_label("Cancel");
        cancel_btn.add_css_class("pill");
        cancel_btn.add_css_class("destructive-action");
        cancel_btn.width_request = 140;

        var save_btn = new Gtk.Button.with_label("Save");
        save_btn.add_css_class("pill");
        save_btn.add_css_class("suggested-action");
        save_btn.width_request = 140;

        cancel_btn.clicked.connect(() => { this.close(); });

        bool initial_resize = settings.auto_resize;

        save_btn.clicked.connect(() => {
            bool turned_on_resize = (!initial_resize && resize_switch.active);

            settings.download_dir = folder_row.subtitle;
            settings.max_threads = (int)spin.value;
            settings.auto_resize = resize_switch.active;
            settings.remember_downloads = remember_switch.active;
            settings.autostart_downloads = autostart_switch.active;
            settings.save();
            
            this.close();

            if (turned_on_resize) {
                main_app.prompt_restart();
            } else {
                main_app.apply_ui_settings(); 
            }
        });

        btn_box.append(cancel_btn);
        btn_box.append(save_btn);
        content_box.append(btn_box);

        main_box.append(content_box);
        this.set_content(main_box);
    }
}

public class FetchixApp : Adw.Application {
    private FetchixManager manager;
    private AppSettings settings;
    private Gtk.ListBox list_box;
    private Gtk.ScrolledWindow scroll;
    private HashTable<string, DownloadRow> rows;
    private Adw.ApplicationWindow window;
    private Gtk.Revealer empty_state_revealer;
    private SettingsDialog? active_settings_dialog = null;
    
    public string exec_path;

    private void debug_log(string message) {
        try {
            string log_path = Environment.get_user_config_dir() + "/Fetchix/debug.log";
            var file = GLib.File.new_for_path(log_path);
            FileOutputStream stream;
            if (!file.query_exists()) {
                stream = file.create(FileCreateFlags.NONE, null);
            } else {
                stream = file.append_to(FileCreateFlags.NONE, null);
            }
            string time_prefix = new DateTime.now_local().format("%Y-%m-%d %H:%M:%S") + " - ";
            stream.write((time_prefix + message + "\n").data, null);
            stream.close(null);
        } catch (Error e) {}
    }

    public FetchixApp() {
        GLib.Object(application_id: "io.github.IzsakiRobi.Fetchix", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
        debug_log("--- Fetchix Instantiated ---");
        manager = new FetchixManager();
        settings = new AppSettings();
        rows = new HashTable<string, DownloadRow>(str_hash, str_equal);
    }

    public void apply_ui_settings() {
        scroll.propagate_natural_height = settings.auto_resize;
        window.resizable = !settings.auto_resize;
        
        if (settings.auto_resize) {
            scroll.min_content_height = -1;
            scroll.max_content_height = 800;
            window.set_default_size(650, -1);
        } else {
            scroll.min_content_height = -1;
            scroll.max_content_height = -1;
            window.set_default_size(650, 400); 
        }
    }

    public void prompt_restart() {
        var dialog = new Adw.AlertDialog("Restart Required", "UI changes will take effect after restart. Restart now?");
        dialog.add_response("no", "Later");
        dialog.add_response("yes", "Restart");
        dialog.set_response_appearance("yes", Adw.ResponseAppearance.SUGGESTED);
        
        dialog.response.connect((response) => {
            if (response == "yes") {
                execute_quit_sequence(true);
            }
        });
        dialog.present(window);
    }

    public void execute_quit_sequence(bool restart) {
        bool has_active = false;
        foreach (var row in rows.get_values()) {
            if (!row.is_finished) has_active = true;
        }

        if (has_active && !settings.remember_downloads) {
            var dialog = new Adw.AlertDialog(
                restart ? "Restart Fetchix?" : "Quit Fetchix?", 
                "Unfinished downloads will be deleted."
            );
            dialog.add_response("stay", "Cancel");
            dialog.add_response("proceed", restart ? "Restart" : "Quit");
            dialog.set_response_appearance("proceed", Adw.ResponseAppearance.DESTRUCTIVE);

            dialog.response.connect((response) => {
                if (response == "proceed") {
                    cleanup_and_quit.begin(restart);
                }
            });
            dialog.present(window);
        } else if (has_active && settings.remember_downloads) {
            var dialog = new Adw.AlertDialog(
                restart ? "Restart Fetchix?" : "Quit Fetchix?", 
                "Downloads will be safely paused and remembered for later."
            );
            dialog.add_response("stay", "Cancel");
            dialog.add_response("proceed", restart ? "Restart" : "Quit");
            dialog.set_response_appearance("proceed", Adw.ResponseAppearance.SUGGESTED);

            dialog.response.connect((response) => {
                if (response == "proceed") {
                    settings.save_progress(rows);
                    manager.force_shutdown.begin((obj, res) => { 
                        if (restart) spawn_and_quit();
                        else window.destroy(); 
                    });
                }
            });
            dialog.present(window);
        } else {
            settings.save_progress(rows);
            manager.force_shutdown.begin((obj, res) => { 
                if (restart) spawn_and_quit();
                else window.destroy(); 
            });
        }
    }

    private void spawn_and_quit() {
        try {
            string path;
            try {
                path = GLib.FileUtils.read_link("/proc/self/exe");
            } catch (FileError e) {
                path = exec_path;
            }
            Process.spawn_command_line_async("sh -c 'sleep 1.5 && \"" + path + "\"'");
        } catch (Error e) {}
        window.destroy();
    }

    private void update_empty_state() {
        if (empty_state_revealer != null) {
            empty_state_revealer.reveal_child = (rows.size() == 0);
        }
    }

    protected override int command_line(GLib.ApplicationCommandLine cmdline) {
        debug_log("--- command_line triggered ---");
        
        string[] args = cmdline.get_arguments();
        
        for (int i = 0; i < args.length; i++) {
            debug_log("RAW ARG[" + i.to_string() + "]: " + args[i]);
        }
        
        this.activate();
        
        for (int i = 1; i < args.length; i++) {
            string arg = args[i];
            string real_url = arg;
            
            // ITT TÖRÖLTEM AZ UNESCAPE_STRING MÓDOSÍTÁST! Visszaállt az eredeti.
            if (arg.has_prefix("fetchix://")) {
                real_url = arg.substring(10);
            } else if (arg.has_prefix("fetchix:")) {
                real_url = arg.substring(8);
            }

            if (real_url.has_prefix("https//")) real_url = "https://" + real_url.substring(7);
            else if (real_url.has_prefix("http//")) real_url = "http://" + real_url.substring(6);
            else if (real_url.has_prefix("ftp//")) real_url = "ftp://" + real_url.substring(5);
            
            debug_log("Parsed URL: " + real_url);
            
            if (real_url.has_prefix("http") || real_url.has_prefix("ftp") || real_url.has_prefix("magnet:")) {
                debug_log("Valid URL format, starting download.");
                start_new_download(real_url);
            } else {
                debug_log("URL ignored (not matching http/ftp/magnet)");
            }
        }
        
        return 0;
    }

    protected override void activate() {
        debug_log("--- activate triggered ---");
        
        if (window != null) {
            debug_log("Window already exists, presenting it.");
            window.present();
            return;
        }

        debug_log("Building UI...");

        var css_provider = new Gtk.CssProvider();
        css_provider.load_from_string("""
            .no-border-drop:drop(active) { box-shadow: none; border: none; }
            .dim-overlay { background-color: rgba(0, 0, 0, 0.20); }
            .dim-text { color: #333333; font-size: 1.0em; font-weight: bold; text-shadow: none; }
            .dim-icon { color: #333333; filter: none; }
            progressbar.success-bar progress { background-color: @success_color; }
            progressbar.paused-bar progress { background-color: #f5c211; }
            .numeric-label { font-feature-settings: "tnum"; }
            .small-status { font-size: 0.85em; }
            window > contents { box-shadow: none !important; border: none !important; }
            headerbar { box-shadow: none !important; border-bottom: none !important; }
        """);
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        window = new Adw.ApplicationWindow(this);
        window.title = "Fetchix";
        window.width_request = 650;
        window.set_default_size(650, 400);

        load_existing_session.begin();

        window.close_request.connect(() => {
            if (manager.is_running) {
                execute_quit_sequence(false);
                return true;
            }
            return false;
        });

        var header = new Adw.HeaderBar();
        header.add_css_class("flat");
        
        var pref_btn = new Gtk.Button.from_icon_name("preferences-system-symbolic");
        pref_btn.clicked.connect(() => {
            window.set_focus(null);
            if (active_settings_dialog != null) {
                active_settings_dialog.present();
                return;
            }
            active_settings_dialog = new SettingsDialog(this, settings);
            active_settings_dialog.close_request.connect(() => {
                active_settings_dialog = null;
                return false;
            });
            active_settings_dialog.present();
        });
        header.pack_start(pref_btn);
        
        var title_stack = new Gtk.Stack();
        title_stack.transition_type = Gtk.StackTransitionType.NONE;

        var url_entry = new Gtk.Entry();
        url_entry.placeholder_text = "Paste URL here and hit Enter...";
        url_entry.width_request = 350; 
        url_entry.secondary_icon_name = "edit-clear-symbolic";
        url_entry.icon_press.connect((pos) => {
            if (pos == Gtk.EntryIconPosition.SECONDARY) {
                url_entry.set_text("");
            }
        });

        var fake_entry = new Gtk.Entry();
        fake_entry.placeholder_text = "Paste URL here and hit Enter...";
        fake_entry.width_request = 350;
        fake_entry.can_target = false; 
        fake_entry.focusable = false;
        fake_entry.can_focus = false;

        url_entry.changed.connect(() => {
            fake_entry.set_text(url_entry.get_text());
        });

        var fake_handle = new Gtk.WindowHandle();
        fake_handle.set_child(fake_entry);

        var title_click = new Gtk.GestureClick();
        title_click.released.connect((n, x, y) => {
            title_stack.set_visible_child_name("real");
            url_entry.grab_focus();
            url_entry.set_position(-1);
        });
        fake_handle.add_controller(title_click);

        var focus_ctrl = new Gtk.EventControllerFocus();
        focus_ctrl.leave.connect(() => {
            title_stack.set_visible_child_name("fake");
        });
        url_entry.add_controller(focus_ctrl);

        var key_ctrl = new Gtk.EventControllerKey();
        key_ctrl.key_pressed.connect((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Escape) {
                window.set_focus(null);
                return true;
            }
            return false;
        });
        url_entry.add_controller(key_ctrl);

        title_stack.add_named(fake_handle, "fake");
        title_stack.add_named(url_entry, "real");
        title_stack.set_visible_child_name("fake");

        header.set_title_widget(title_stack);

        list_box = new Gtk.ListBox();
        list_box.selection_mode = SelectionMode.NONE;
        list_box.margin_top = 0;
        list_box.margin_bottom = 0;
        list_box.margin_start = 0;
        list_box.margin_end = 0;

        url_entry.activate.connect(() => {
            string url = url_entry.get_text().strip();
            if (url != "") {
                url_entry.set_text("");
                window.set_focus(null);
                start_new_download(url);
            }
        });

        scroll = new Gtk.ScrolledWindow();
        scroll.set_child(list_box);
        scroll.has_frame = false; 
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        
        apply_ui_settings();

        var empty_state_icon = new Gtk.Image.from_file(get_asset_path("Drop.png"));
        empty_state_icon.pixel_size = 64;
        empty_state_icon.set_size_request(64, 64);

        empty_state_revealer = new Gtk.Revealer();
        empty_state_revealer.transition_type = Gtk.RevealerTransitionType.CROSSFADE;
        empty_state_revealer.transition_duration = 600;
        empty_state_revealer.halign = Align.CENTER;
        empty_state_revealer.valign = Align.CENTER;
        empty_state_revealer.set_child(empty_state_icon);

        var list_overlay = new Gtk.Overlay();
        list_overlay.set_child(scroll);
        list_overlay.add_overlay(empty_state_revealer);

        var content = new Adw.ToolbarView();
        content.add_top_bar(header);
        content.set_content(list_overlay);

        var overlay = new Gtk.Overlay();
        overlay.add_css_class("no-border-drop");
        overlay.set_child(content);

        var bg_click = new Gtk.GestureClick();
        bg_click.pressed.connect(() => {
            window.set_focus(null);
        });
        overlay.add_controller(bg_click);
        
        var list_click = new Gtk.GestureClick();
        list_click.pressed.connect(() => {
            window.set_focus(null);
        });
        list_box.add_controller(list_click);

        var dim_bg = new Gtk.Box(Orientation.VERTICAL, 0);
        dim_bg.add_css_class("dim-overlay");
        dim_bg.halign = Align.FILL;
        dim_bg.valign = Align.FILL;
        dim_bg.can_target = false;
        dim_bg.visible = false;

        overlay.add_overlay(dim_bg);

        var drop_target = new Gtk.DropTarget(typeof(string), Gdk.DragAction.COPY);
        drop_target.enter.connect((x, y) => { dim_bg.visible = true; return Gdk.DragAction.COPY; });
        drop_target.leave.connect(() => { dim_bg.visible = false; });
        drop_target.drop.connect((value, x, y) => {
            dim_bg.visible = false;
            string text = (string)value;
            string[] lines = text.split("\n");
            bool handled = false;
            foreach (string line in lines) {
                string url = line.strip();
                if (url.has_prefix("http") || url.has_prefix("ftp") || url.has_prefix("magnet:")) {
                    start_new_download(url);
                    handled = true;
                }
            }
            return handled;
        });
        overlay.add_controller(drop_target);

        window.set_content(overlay);
        window.present();
        update_empty_state();

        Timeout.add(1000, () => {
            poll_downloads.begin();
            return true;
        });
    }

    private async void load_existing_session() {
        yield manager.ensure_started(settings.session_path);
        
        var root_active = yield manager.call_rpc("aria2.tellActive");
        if (root_active != null && root_active.get_object().has_member("result")) {
            var arr = root_active.get_object().get_array_member("result");
            add_rows_from_json(arr);
            if (!settings.autostart_downloads) {
                arr.foreach_element((a, i, node) => {
                    manager.pause_download.begin(node.get_object().get_string_member("gid"));
                });
            }
        }
        
        var root_waiting = yield manager.call_rpc("aria2.tellWaiting", "[0, 1000]");
        if (root_waiting != null && root_waiting.get_object().has_member("result")) {
            var arr = root_waiting.get_object().get_array_member("result");
            add_rows_from_json(arr);
            if (!settings.autostart_downloads) {
                arr.foreach_element((a, i, node) => {
                    manager.pause_download.begin(node.get_object().get_string_member("gid"));
                });
            }
        }
    }

    private void add_rows_from_json(Json.Array list) {
        list.foreach_element((array, index, node) => {
            var obj = node.get_object();
            string gid = obj.get_string_member("gid");
            string url = "Unknown Download";
            
            if (obj.has_member("files")) {
                var files = obj.get_array_member("files");
                if (files.get_length() > 0) {
                    var file_node = files.get_object_element(0);
                    if (file_node.has_member("uris")) {
                        var uris = file_node.get_array_member("uris");
                        if (uris.get_length() > 0) {
                            url = uris.get_object_element(0).get_string_member("uri");
                        }
                    }
                    if (url == "Unknown Download" && file_node.has_member("path")) {
                        string path = file_node.get_string_member("path");
                        if (path != "") url = GLib.Path.get_basename(path);
                    }
                }
            }
            
            if (!rows.contains(gid)) {
                create_row_ui(gid, url);
            }
        });
    }

    // ÚJ: A hidegindításos probléma megoldása. Beleteszi a "várólistába" a Firefox linkjét, amíg a motor feláll.
    private async void process_queued_download(string url) {
        int attempts = 0;
        while (!manager.is_running && attempts < 50) {
            yield manager.wait_ms(200);
            attempts++;
        }
        manager.add_uri.begin(url, settings.download_dir, settings.max_threads, (obj, res) => {
            string? gid = manager.add_uri.end(res);
            if (gid != null) {
                create_row_ui(gid, url);
            }
        });
    }

    private void start_new_download(string url) {
        process_queued_download.begin(url);
    }

    private void create_row_ui(string gid, string url) {
        var row = new DownloadRow(gid, url);
        
        try {
            if (settings.progress_db.has_group(gid)) {
                int64 comp = settings.progress_db.get_int64(gid, "completed");
                int64 tot = settings.progress_db.get_int64(gid, "total");
                if (tot > 0) {
                    row.current_completed = comp;
                    row.current_total = tot;
                    row.update_status("paused", comp, tot, 0, 0); 
                }
            }
        } catch (Error e) {}
        
        row.on_pause_toggled.connect((g, is_paused) => {
            if (is_paused) manager.pause_download.begin(g);
            else manager.resume_download.begin(g);
        });

        row.on_cancel.connect((g) => {
            if (row.is_finished) {
                manager.remove_download_result.begin(g);
                list_box.remove(row);
                rows.remove(g);
                update_empty_state();
            } else {
                if (settings.remember_downloads) {
                    var dialog = new Adw.AlertDialog("Cancel?", "Keep temporary files for later?");
                    dialog.add_response("delete", "Delete All");
                    dialog.add_response("keep", "Keep Files");
                    dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);
                    
                    dialog.response.connect((response) => {
                        if (response == "delete") {
                            cancel_and_clean_download.begin(g, row);
                        } else if (response == "keep") {
                            manager.force_remove_download.begin(g);
                            manager.remove_download_result.begin(g);
                            list_box.remove(row);
                            rows.remove(g);
                            update_empty_state();
                        }
                    });
                    dialog.present(window);
                } else {
                    var dialog = new Adw.AlertDialog("Cancel?", "Temporary files will be deleted.");
                    dialog.add_response("no", "No");
                    dialog.add_response("yes", "Yes");
                    dialog.set_response_appearance("yes", Adw.ResponseAppearance.DESTRUCTIVE);
                    
                    dialog.response.connect((response) => {
                        if (response == "yes") cancel_and_clean_download.begin(g, row);
                    });
                    dialog.present(window);
                }
            }
        });

        rows.insert(gid, row);
        list_box.append(row);
        update_empty_state();
    }

    private async void cleanup_and_quit(bool restart) {
        string[] gids_to_clean = {};
        foreach (unowned string gid in rows.get_keys()) {
            if (!rows.lookup(gid).is_finished) gids_to_clean += gid;
        }

        foreach (string gid in gids_to_clean) {
            string params_json = "[\"%s\"]".printf(gid);
            var root = yield manager.call_rpc("aria2.tellStatus", params_json);
            string file_path = "";
            
            if (root != null && root.get_object().has_member("result")) {
                var obj = root.get_object().get_object_member("result");
                if (obj.has_member("files")) {
                    var files = obj.get_array_member("files");
                    if (files.get_length() > 0) {
                        var file_node = files.get_object_element(0);
                        if (file_node.has_member("path")) file_path = file_node.get_string_member("path");
                    }
                }
            }

            yield manager.force_remove_download(gid);
            yield manager.remove_download_result(gid);
            yield manager.wait_ms(200);

            if (file_path != "") {
                var file = GLib.File.new_for_path(file_path);
                try { if (file.query_exists()) file.delete(null); } catch (Error e) {}
                var aria_file = GLib.File.new_for_path(file_path + ".aria2");
                try { if (aria_file.query_exists()) aria_file.delete(null); } catch (Error e) {}
            }
        }

        yield manager.force_shutdown();
        if (restart) spawn_and_quit();
        else window.destroy();
    }

    private async void cancel_and_clean_download(string gid, DownloadRow row) {
        string params_json = "[\"%s\"]".printf(gid);
        var root = yield manager.call_rpc("aria2.tellStatus", params_json);
        string file_path = "";
        
        if (root != null && root.get_object().has_member("result")) {
            var obj = root.get_object().get_object_member("result");
            if (obj.has_member("files")) {
                var files = obj.get_array_member("files");
                if (files.get_length() > 0) {
                    var file_node = files.get_object_element(0);
                    if (file_node.has_member("path")) file_path = file_node.get_string_member("path");
                }
            }
        }

        yield manager.force_remove_download(gid);
        yield manager.remove_download_result(gid);
        yield manager.wait_ms(500);

        if (file_path != "") {
            var file = GLib.File.new_for_path(file_path);
            try { if (file.query_exists()) file.delete(null); } catch (Error e) {}
            var aria_file = GLib.File.new_for_path(file_path + ".aria2");
            try { if (aria_file.query_exists()) aria_file.delete(null); } catch (Error e) {}
        }

        list_box.remove(row);
        rows.remove(gid);
        update_empty_state();
    }

    private async void poll_downloads() {
        foreach (unowned string gid in rows.get_keys()) {
            var row = rows.lookup(gid);
            if (row.is_finished) continue;

            string params_json = "[\"%s\"]".printf(gid);
            var root = yield manager.call_rpc("aria2.tellStatus", params_json);
            
            if (root != null && root.get_object().has_member("result")) {
                var obj = root.get_object().get_object_member("result");
                
                string status = obj.get_string_member("status");
                int64 completed = int64.parse(obj.get_string_member("completedLength"));
                int64 total = int64.parse(obj.get_string_member("totalLength"));
                int64 speed = int64.parse(obj.get_string_member("downloadSpeed"));

                int64 eta = 0;
                if (speed > 0 && total > completed) {
                    eta = (total - completed) / speed;
                }

                if (status == "complete" && row.last_status != "complete") {
                    string file_path = "";
                    if (obj.has_member("files")) {
                        var files = obj.get_array_member("files");
                        if (files.get_length() > 0) {
                            var file_node = files.get_object_element(0);
                            if (file_node.has_member("path")) file_path = file_node.get_string_member("path");
                        }
                    }

                    string file_name = "Download";
                    if (file_path != "") {
                        var file = GLib.File.new_for_path(file_path);
                        file_name = file.get_basename();
                    }

                    var notif = new GLib.Notification("Download Complete");
                    notif.set_body(file_name);
                    
                    string icon_path = get_asset_path("io.github.IzsakiRobi.Fetchix.svg");
                    notif.set_icon(new GLib.FileIcon(GLib.File.new_for_path(icon_path)));
                    notif.set_priority(GLib.NotificationPriority.HIGH);
                    
                    this.send_notification("dl-complete-" + gid, notif);

                } else if (status == "error" && row.last_status != "error") {
                    string err_msg = "An error occurred during download.";
                    if (obj.has_member("errorMessage")) {
                        err_msg = obj.get_string_member("errorMessage");
                    }
                    var notif = new GLib.Notification("Download Failed");
                    notif.set_body(err_msg);
                    
                    string icon_path = get_asset_path("io.github.IzsakiRobi.Fetchix.svg");
                    notif.set_icon(new GLib.FileIcon(GLib.File.new_for_path(icon_path)));
                    notif.set_priority(GLib.NotificationPriority.HIGH);
                    
                    this.send_notification("dl-error-" + gid, notif);
                }

                row.update_status(status, completed, total, speed, eta);
            }
        }
    }
}

int main(string[] args) {
    var app = new FetchixApp();
    app.exec_path = args[0]; 
    return app.run(args);
}

