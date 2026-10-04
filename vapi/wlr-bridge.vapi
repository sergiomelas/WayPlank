[CCode (cprefix = "wlr_toplevel_bridge_", lower_case_cprefix = "wlr_toplevel_bridge_", cheader_filename = "wlr-toplevel-bridge.h")]
namespace Plank.WlrBridge {
	[CCode (has_target = false)]
	public delegate void StateChangedCallback ();

	public static bool init (StateChangedCallback callback);
	public static void cleanup ();
	public static bool is_available ();
	public static string get_window_json ();
	public static bool queue_command (string target, string action);
	public static bool any_window_intersects (int x, int y, int width, int height);
	public static bool active_window_intersects (int x, int y, int width, int height);
	public static bool maximized_window_intersects (int x, int y, int width, int height);
}
