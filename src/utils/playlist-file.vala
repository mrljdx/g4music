namespace G4 {

    namespace PlayListType {
        public const uint NONE = 0;
        public const uint M3U = 1;
        public const uint PLS = 2;
    }

    public uint get_playlist_type (string mimetype) {
        switch (mimetype) {
            case "audio/x-mpegurl":
            case "public.m3u-playlist":
                return PlayListType.M3U;
            case "audio/x-scpls":
                return PlayListType.PLS;
            default:
                return PlayListType.NONE;
        }
    }

    public bool is_playlist_file (string mimetype) {
        return get_playlist_type (mimetype) != PlayListType.NONE;
    }

    public bool is_valid_uri (string uri, UriFlags flags = UriFlags.NONE) {
        try {
            return Uri.is_valid (uri, flags);
        } catch (Error e) {
        }
        return false;
    }

    public string? load_playlist_file (File file, GenericArray<string> uris) {
        try {
            var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
            var type = get_playlist_type (info.get_content_type () ?? "");
            switch (type) {
                case PlayListType.M3U:
                    return load_m3u_file (file, uris);
                case PlayListType.PLS:
                    return load_pls_file (file, uris);
            }
        } catch (Error e) {
        }
        return null;
    }

    public string load_m3u_file (File file, GenericArray<string> uris) throws Error {
        var fis = file.read ();
        var bis = new BufferedInputStream (fis);
        var dis = new DataInputStream (bis);
        var parent = file.get_parent ();
        size_t length = 0;
        string? str = null;
        while ((str = dis.read_line_utf8 (out length)) != null) {
            var uri = (!)str;
            if (length > 0 && uri[0] != '#') {
                var abs_uri = parse_relative_uri (uri.replace("\r", ""), parent);
                if (abs_uri != null)
                    uris.add ((!)abs_uri);
            }
        }
        return get_file_display_name (file);
    }

    public string load_pls_file (File file, GenericArray<string> uris) throws Error {
        var name = get_file_display_name (file);
        var fis = file.read ();
        var bis = new BufferedInputStream (fis);
        var dis = new DataInputStream (bis);
        var parent = file.get_parent ();
        bool list_found = false;
        size_t length = 0;
        int pos = -1;
        string? str = null;
        while ((str = dis.read_line_utf8 (out length)) != null) {
            var line = ((!)str).strip ();
            if (line.length > 1 && line[0] == '[') {
                list_found = strcmp (line, "[playlist]") == 0;
            } else if (list_found && (pos = line.index_of_char ('=')) > 0) {
                if (line.has_prefix ("File")) {
                    var uri = line.substring (pos + 1).strip ();
                    var abs_uri = parse_relative_uri (uri, parent);
                    if (abs_uri != null)
                        uris.add ((!)abs_uri);
                } else if (line.ascii_ncasecmp ("X-GNOME-Title", pos) == 0) {
                    var title = line.substring (pos + 1).strip ();
                    if (title.length > 0)
                        name = title;
                }
            }
        }
        return name;
    }

    public string? parse_relative_uri (string uri, File? parent = null) {
        if (uri.length > 0 && uri[0] == '/') {
            return File.new_for_path (uri).get_uri ();
        } else if (is_valid_uri (uri)) {
            //  Native files only
            return uri.has_prefix ("file://") ? (string?) uri : null;
        }
        return parent?.resolve_relative_path (uri)?.get_uri ();
    }

    public bool save_line_to_file (BufferedOutputStream bos, string str) throws Error {
        var cn = "\n";
        var cn_data = ((uint8[]) cn) [0:1];
        var data = ((uint8[]) str) [0:str.length];
        size_t written = 0;
        return bos.write_all (data, out written)
            && bos.write_all (cn_data, out written);
    }

    public bool save_m3u8_file (File file, GenericArray<string> uris) throws Error {
        var fos = file.replace (null, false, FileCreateFlags.NONE);
        var bos = new BufferedOutputStream (fos);
        var extm3u = ((uint8[]) "#EXTM3U\n") [0:8];
        size_t written = 0;
        if (!bos.write_all (extm3u, out written))
            return false;
        var extinf = ((uint8[]) "#EXTINF:,\n") [0:10];
        var parent = file.get_parent ();
        foreach (var uri in uris) {
            if (!bos.write_all (extinf, out written))
                return false;
            var f = File.new_for_uri (uri);
            var path = parent?.get_relative_path (f) ?? f.get_path () ?? "";
            if (!save_line_to_file (bos, path))
                return false;
        }
        return true;
    }

    public bool save_pls_file (File file, GenericArray<string> uris, string? name = null) throws Error {
        var fos = file.replace (null, false, FileCreateFlags.NONE);
        var bos = new BufferedOutputStream (fos);
        var section = ((uint8[]) "[playlist]\n") [0:11];
        size_t written = 0;
        if (!bos.write_all (section, out written))
            return false;
        var count = uris.length;
        if (!save_line_to_file (bos, @"NumberOfEntries=$count"))
            return false;
        for (var i = 0; i < count; i++) {
            var f = File.new_for_uri (uris[i]);
            var path = f.get_path () ?? "";
            var title = get_file_display_name (f);
            var n = i + 1;
            if (!save_line_to_file (bos, @"File$n=$path\nTitle$n=$title"))
                break;
        }
        return true;
    }

    public bool save_playlist_file (File file, GenericArray<string> uris, string? name = null) {
        var bname = file.get_basename () ?? "";
        var title = bname.substring (0, bname.index_of_char ('.'));
        var ext = bname.substring (bname.index_of_char ('.') + 1);
        try {
            if (ext.ascii_ncasecmp ("pls", 3) == 0) {
                return save_pls_file (file, uris, name ?? title);
            } else {
                return save_m3u8_file (file, uris);
            }
        } catch (Error e) {
        }
        return false;
    }
}