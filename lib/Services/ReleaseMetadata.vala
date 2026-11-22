//
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of WayPlank.
//
//  WayPlank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  WayPlank is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

namespace Plank
{
	/**
	 * A formatted credit section loaded from the embedded root VERSION file.
	 */
	public class CreditGroup : Object
	{
		public string heading { get; private set; }
		public string[] lines { get; private set; }

		public CreditGroup (string heading, string[] lines)
		{
			this.heading = heading;
			this.lines = lines;
		}
	}

	/**
	 * Single-source-of-truth reader for release metadata and WayPlank credits
	 * compiled into the monolithic GResource from the repository root VERSION file.
	 */
	public class ReleaseMetadata : Object
	{
		static ReleaseMetadata? instance = null;

		public string version { get; private set; default = ""; }
		public string decoration { get; private set; default = ""; }
		public string year { get; private set; default = ""; }
		public string program_name { get; private set; default = "WayPlank"; }
		public string copyright_holder { get; private set; default = ""; }
		public string copyright_email { get; private set; default = ""; }
		public string homepage { get; private set; default = ""; }
		public string issues_url { get; private set; default = ""; }
		public string supported_os { get; private set; default = ""; }
		public string fully_supported_compositors { get; private set; default = ""; }
		public string partially_supported_compositors { get; private set; default = ""; }
		public string credits_tab_title { get; private set; default = ""; }

		string[] wayplank_authors = {};
		string[] wayplank_documenters = {};
		string[] wayplank_artists = {};
		Gee.ArrayList<CreditGroup> credit_groups = new Gee.ArrayList<CreditGroup> ();
		string hall_of_fame_body = "";

		public static ReleaseMetadata get_default ()
		{
			if (instance == null)
				instance = new ReleaseMetadata ();
			return instance;
		}

		ReleaseMetadata ()
		{
			load_from_resource ();
		}

		static bool has_key_safe (KeyFile kf, string group, string key)
		{
			try {
				return kf.has_key (group, key);
			} catch (Error e) {
				return false;
			}
		}

		static string read_key (KeyFile kf, string group, string key, string fallback = "")
		{
			try {
				if (kf.has_key (group, key))
					return kf.get_string (group, key).strip ();
			} catch (Error e) {
			}
			return fallback;
		}

		static void collect_numbered (KeyFile kf, string group, string prefix, Gee.ArrayList<string> dest)
		{
			for (int i = 1; ; i++) {
				string key = "%s%d".printf (prefix, i);
				if (!has_key_safe (kf, group, key))
					break;
				string val = read_key (kf, group, key);
				if (val.length > 0)
					dest.add (val);
			}
		}

		static void append_entry_markup (string entry, string layout, Gee.ArrayList<string> lines)
		{
			string[] raw_parts = entry.split ("|");
			string name = raw_parts.length > 0 ? raw_parts[0].strip () : "";
			string desc = raw_parts.length > 1 ? raw_parts[1].strip () : "";
			string url = raw_parts.length > 2 ? raw_parts[2].strip () : "";
			string email = raw_parts.length > 3 ? raw_parts[3].strip () : "";

			if (name.length == 0)
				return;

			string esc_name = GLib.Markup.escape_text (name);
			string name_markup = (url.length > 0)
				? "<a href=\"%s\">%s</a>".printf (GLib.Markup.escape_text (url), esc_name)
				: esc_name;

			if (layout == "stacked") {
				if (email.length > 0) {
					string esc_email = GLib.Markup.escape_text (email);
					lines.add ("%s &lt;<a href=\"mailto:%s\">%s</a>&gt;".printf (name_markup, esc_email, esc_email));
				} else {
					lines.add (name_markup);
				}
				if (desc.length > 0)
					lines.add (GLib.Markup.escape_text (desc));
			} else {
				if (desc.length > 0)
					lines.add ("%s — %s".printf (name_markup, GLib.Markup.escape_text (desc)));
				else
					lines.add (name_markup);
			}
		}

		void load_from_resource ()
		{
			var kf = new KeyFile ();
			try {
				var bytes = GLib.resources_lookup_data (
					"%s/meta/VERSION".printf (G_RESOURCE_PATH),
					GLib.ResourceLookupFlags.NONE
				);
				if (bytes == null)
					return;
				unowned uint8[] raw = bytes.get_data ();
				var buf = new uint8[raw.length + 1];
				Memory.copy (buf, raw, raw.length);
				buf[raw.length] = 0;
				kf.load_from_data ((string) buf, raw.length, KeyFileFlags.NONE);
			} catch (Error e) {
				warning ("ReleaseMetadata: unable to load embedded VERSION metadata: %s", e.message);
				return;
			}

			version = read_key (kf, "Release", "Version", Build.VERSION);
			decoration = read_key (kf, "Release", "Decoration", Build.PACKAGE_VERSION_DECO);
			year = read_key (kf, "Release", "Year", Build.PACKAGE_YEAR);
			program_name = read_key (kf, "Release", "ProgramName", Build.RELEASE_NAME);
			copyright_holder = read_key (kf, "Release", "CopyrightHolder");
			copyright_email = read_key (kf, "Release", "CopyrightEmail");
			homepage = read_key (kf, "Release", "Homepage", Build.PACKAGE_URL);
			issues_url = read_key (kf, "Release", "IssuesUrl", Build.PACKAGE_BUGREPORT);
			supported_os = read_key (kf, "Release", "SupportedOS");
			fully_supported_compositors = read_key (kf, "Release", "FullySupportedCompositors");
			partially_supported_compositors = read_key (kf, "Release", "PartiallySupportedCompositors");
			credits_tab_title = read_key (kf, "Credits", "TabTitle", "🚀 %s (%s)".printf (program_name, year));

			var authors_list = new Gee.ArrayList<string> ();
			var docs_list = new Gee.ArrayList<string> ();
			var artists_list = new Gee.ArrayList<string> ();
			var hof_list = new Gee.ArrayList<string> ();

			string groups_raw = read_key (kf, "Credits", "Groups");
			foreach (string raw_id in groups_raw.split (";")) {
				string gid = raw_id.strip ();
				if (gid.length == 0)
					continue;
				string sec = "Credits:%s".printf (gid);
				if (!kf.has_group (sec))
					continue;

				collect_numbered (kf, sec, "Author", authors_list);
				collect_numbered (kf, sec, "Documenter", docs_list);
				collect_numbered (kf, sec, "Artist", artists_list);
				collect_numbered (kf, sec, "HallOfFame", hof_list);

				string heading = read_key (kf, sec, "Heading");
				string layout = read_key (kf, sec, "Layout", "inline");
				var lines = new Gee.ArrayList<string> ();
				for (int i = 1; ; i++) {
					string key = "Entry%d".printf (i);
					if (!has_key_safe (kf, sec, key))
						break;
					append_entry_markup (read_key (kf, sec, key), layout, lines);
				}

				if (heading.length > 0 && lines.size > 0)
					credit_groups.add (new CreditGroup (heading, lines.to_array ()));
			}

			wayplank_authors = authors_list.to_array ();
			wayplank_documenters = docs_list.to_array ();
			wayplank_artists = artists_list.to_array ();

			var sb = new StringBuilder ();
			for (int i = 0; i < hof_list.size; i++) {
				if (i > 0)
					sb.append ("   •   ");
				sb.append (hof_list[i]);
			}
			hall_of_fame_body = sb.str;
		}

		public string[] get_authors_with_historic (string[] historic)
		{
			return concat_arrays (wayplank_authors, historic);
		}

		public string[] get_documenters_with_historic (string[] historic)
		{
			return concat_arrays (wayplank_documenters, historic);
		}

		public string[] get_artists_with_historic (string[] historic)
		{
			return concat_arrays (wayplank_artists, historic);
		}

		public Gee.List<CreditGroup> get_credit_groups ()
		{
			return credit_groups;
		}

		public string get_hall_of_fame (string historic_tribute)
		{
			if (hall_of_fame_body.length > 0)
				return "🌟 WAYPLANK HALL OF FAME   •   %s   •   %s     •     ".printf (hall_of_fame_body, historic_tribute);
			return "🌟 WAYPLANK HALL OF FAME   •   %s     •     ".printf (historic_tribute);
		}

		static string[] concat_arrays (string[] head, string[] tail)
		{
			var merged = new string[head.length + tail.length];
			for (int i = 0; i < head.length; i++)
				merged[i] = head[i];
			for (int i = 0; i < tail.length; i++)
				merged[head.length + i] = tail[i];
			return merged;
		}
	}
}
