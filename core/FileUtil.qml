// FileUtil — helpers for building safe URLs from local paths.
//
// `file://` URLs are parsed by QUrl, which treats '#' as a fragment
// delimiter and '?' as a query delimiter. Naively concatenating
// "file://" + path silently truncates filenames containing those
// characters (e.g. "*_#arcane_Twitter.png" became "*_"). JS's
// encodeURI() does NOT escape '#' or '?' since RFC 3986 marks them
// reserved, so it can't be used here. Escape the three bytes that
// actually collide with URL syntax — '%' first so previously-encoded
// bytes don't get doubled.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    function fileUrl(path) {
        if (!path) return ""
        return "file://" + String(path)
            .replace(/%/g, "%25")
            .replace(/#/g, "%23")
            .replace(/\?/g, "%3F")
    }
}
