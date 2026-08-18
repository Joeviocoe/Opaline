// Checks for YouTubeLinkParser. Not standalone — check_youtube_link_parser.sh
// concatenates it with the real parser source, so there is no second copy to
// drift out of sync.

func check(_ urlString: String, expect: String?, line: UInt = #line) {
    let url = URL(string: urlString)
    let got = url.flatMap { YouTubeLinkParser.videoId(from: $0) }
    assert(
        got == expect,
        "line \(line): \(urlString) -> got \(got ?? "nil"), expected \(expect ?? "nil")"
    )
}

func checkStart(_ urlString: String, expect: Double?, line: UInt = #line) {
    let url = URL(string: urlString)
    let got = url.flatMap { YouTubeLinkParser.startSeconds(from: $0) }
    let gotText = got.map { "\($0)" } ?? "nil"
    let expectText = expect.map { "\($0)" } ?? "nil"
    assert(got == expect, "line \(line): \(urlString) -> got \(gotText), expected \(expectText)")
}

// Accepted shapes
check("https://www.youtube.com/watch?v=dQw4w9WgXcQ", expect: "dQw4w9WgXcQ")
check("https://youtube.com/watch?v=dQw4w9WgXcQ&list=PL123", expect: "dQw4w9WgXcQ")
check("https://youtu.be/dQw4w9WgXcQ", expect: "dQw4w9WgXcQ")
check("https://youtu.be/dQw4w9WgXcQ?t=42", expect: "dQw4w9WgXcQ")
check("https://www.youtube.com/shorts/dQw4w9WgXcQ", expect: "dQw4w9WgXcQ")
check("https://www.youtube.com/live/dQw4w9WgXcQ?feature=share", expect: "dQw4w9WgXcQ")
check("https://www.youtube.com/embed/dQw4w9WgXcQ", expect: "dQw4w9WgXcQ")
check("https://m.youtube.com/watch?v=dQw4w9WgXcQ", expect: "dQw4w9WgXcQ")
check("ytlite://watch?v=dQw4w9WgXcQ", expect: "dQw4w9WgXcQ")
check("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s", expect: "dQw4w9WgXcQ")
check("https://youtu.be/UsPIfGgwZYw?si=pb1j5tEy7zsTPi8W&t=87", expect: "UsPIfGgwZYw")
check("https://youtube.com/shorts/LdGE7FOnE8o?is=kKCMiXDHg8UqtTb8", expect: "LdGE7FOnE8o")

// Negative cases
check("https://www.youtube.com/feed/trending", expect: nil)
check("https://www.youtube.com/watch", expect: nil)
check("https://example.com/watch?v=dQw4w9WgXcQ", expect: nil)
check("https://example.com/shorts/dQw4w9WgXcQ", expect: nil)
check("not a url at all", expect: nil)
check("ytlite://watch", expect: nil)
check("https://www.youtube.com/", expect: nil)

// Timecodes
checkStart("https://youtu.be/UsPIfGgwZYw?si=pb1j5tEy7zsTPi8W&t=87", expect: 87)
checkStart("https://youtu.be/dQw4w9WgXcQ?t=87s", expect: 87)
checkStart("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s", expect: 90)
checkStart("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1h2m3s", expect: 3723)
checkStart("https://www.youtube.com/embed/dQw4w9WgXcQ?start=15", expect: 15)
checkStart("ytlite://watch?v=dQw4w9WgXcQ&t=87", expect: 87)
checkStart("https://youtu.be/dQw4w9WgXcQ", expect: nil)
checkStart("https://youtu.be/dQw4w9WgXcQ?t=0", expect: nil)
checkStart("https://youtu.be/dQw4w9WgXcQ?t=abc", expect: nil)
checkStart("https://youtu.be/dQw4w9WgXcQ?t=1m30", expect: nil)

func checkShort(_ urlString: String, expect: Bool, line: UInt = #line) {
    let url = URL(string: urlString)
    let got = url.map { YouTubeLinkParser.isShort($0) } ?? false
    assert(got == expect, "line \(line): \(urlString) -> got \(got), expected \(expect)")
}

// Shorts keep their shape through the deep link
checkShort("https://www.youtube.com/shorts/dQw4w9WgXcQ", expect: true)
checkShort("https://www.youtube.com/shorts/dQw4w9WgXcQ?si=abc", expect: true)
checkShort("https://youtube.com/shorts/LdGE7FOnE8o?is=kKCMiXDHg8UqtTb8", expect: true)
checkShort("ytlite://watch?v=dQw4w9WgXcQ&shorts=1", expect: true)
checkShort("https://www.youtube.com/watch?v=dQw4w9WgXcQ", expect: false)
checkShort("https://youtu.be/dQw4w9WgXcQ", expect: false)
checkShort("ytlite://watch?v=dQw4w9WgXcQ", expect: false)

func checkList(_ urlString: String, expect: String?, line: UInt = #line) {
    let url = URL(string: urlString)
    let got = url.flatMap { YouTubeLinkParser.playlistId(from: $0) }
    assert(
        got == expect,
        "line \(line): \(urlString) -> got \(got ?? "nil"), expected \(expect ?? "nil")"
    )
}

// Playlists
checkList(
    "https://youtube.com/playlist?list=PL2VOasSfo6Yu&si=L3-AVofd65iPproi",
    expect: "PL2VOasSfo6Yu"
)
checkList("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123", expect: "PL123")
checkList("ytlite://playlist?list=PL123", expect: "PL123")
checkList("https://youtu.be/dQw4w9WgXcQ", expect: nil)
checkList("https://example.com/playlist?list=PL123", expect: nil)

func checkMix(_ urlString: String, expect: String?, line: UInt = #line) {
    let url = URL(string: urlString)
    let got = url.flatMap { YouTubeLinkParser.mixSeedVideoId(from: $0) }
    assert(
        got == expect,
        "line \(line): \(urlString) -> got \(got ?? "nil"), expected \(expect ?? "nil")"
    )
}

// Mixes play, they have no page
checkMix("https://youtube.com/playlist?list=RDtB9TKsU22wU", expect: "tB9TKsU22wU")
checkMix("ytlite://playlist?list=RDtB9TKsU22wU", expect: "tB9TKsU22wU")
checkMix("https://youtube.com/playlist?list=RDMMdQw4w9WgXcQ", expect: nil)
checkMix("https://youtube.com/playlist?list=PL2VOasSfo6Yu", expect: nil)

// The one rule both the extension and the deep-link handler ask
assert(URL(string: "https://youtube.com/playlist?list=PL123").map(YouTubeLinkParser.handles) == true)
assert(URL(string: "https://youtu.be/dQw4w9WgXcQ").map(YouTubeLinkParser.handles) == true)
assert(URL(string: "https://youtube.com/feed/trending").map(YouTubeLinkParser.handles) == false)

print("YouTubeLinkParser: all checks passed")
