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

print("YouTubeLinkParser: all checks passed")
