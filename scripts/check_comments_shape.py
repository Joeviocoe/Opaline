#!/usr/bin/env python3
"""Assert the response shape `InnertubeClient+CommentParsing.swift` relies on.

The Swift parser reads comments *structurally* — top-level `continuationItems`
only — because a recursive search for a continuation token picks up the reply
token nested inside a thread instead, which silently caps the list at ~30.
This script fetches a real comments page and its first replies page and fails
if any of those structural assumptions stops holding.

Run: python3 scripts/check_comments_shape.py [videoId]
"""
import base64
import json
import sys
import urllib.request

CLIENT = {"client": {"clientName": "WEB", "clientVersion": "2.20240101.00.00",
                     "hl": "en", "gl": "US"}}
URL = "https://www.youtube.com/youtubei/v1/next?prettyPrint=false"


def varint(n):
    out = b""
    while n >= 0x80:
        out += bytes([n & 0x7F | 0x80])
        n >>= 7
    return out + bytes([n])


def field(num, wire):
    return varint((num << 3) | wire)


def string(num, value):
    raw = value.encode()
    return field(num, 2) + varint(len(raw)) + raw


def message(num, value):
    return field(num, 2) + varint(len(value)) + value


def token(video_id):
    """Mirrors InnertubeClient.buildCommentsContinuation(sortBy: 0)."""
    opts = string(4, video_id) + field(6, 0) + varint(0) + field(15, 0) + varint(2)
    params = message(4, opts) + string(8, "comments-section")
    root = message(2, string(2, video_id)) + field(3, 0) + varint(6) + message(6, params)
    return base64.b64encode(root).decode().replace("+", "-").replace("/", "_")


def fetch(continuation):
    body = json.dumps({"context": CLIENT, "continuation": continuation}).encode()
    request = urllib.request.Request(URL, data=body, headers={
        "Content-Type": "application/json",
        "X-Youtube-Client-Name": "1",
        "X-Youtube-Client-Version": "2.20240101.00.00",
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def items(page):
    """The flat top-level item list, as `commentsItems(in:)` reads it."""
    result = []
    for endpoint in page.get("onResponseReceivedEndpoints", []):
        action = (endpoint.get("reloadContinuationItemsCommand")
                  or endpoint.get("appendContinuationItemsAction") or {})
        result += action.get("continuationItems", [])
    return result


def continuation_of(item):
    renderer = item.get("continuationItemRenderer")
    if not renderer:
        return None
    endpoint = renderer.get("continuationEndpoint", {})
    return endpoint.get("continuationCommand", {}).get("token")


def main():
    video_id = sys.argv[1] if len(sys.argv) > 1 else "dQw4w9WgXcQ"
    page = fetch(token(video_id))
    top = items(page)
    threads = [i["commentThreadRenderer"] for i in top if "commentThreadRenderer" in i]
    assert threads, "no commentThreadRenderer items at the top level"
    assert "commentsHeaderRenderer" in json.dumps(top[:1]), "no header item"

    tokens = [t for t in (continuation_of(i) for i in top) if t]
    assert len(tokens) == 1, f"expected one top-level continuation, got {len(tokens)}"
    assert "comment-replies-item" not in tokens[-1], "next-page token is a replies token"

    # A thread nests its view model one level deeper than a reply does.
    outer = threads[0]["commentViewModel"]
    assert "commentViewModel" in outer, "thread view model is no longer double-wrapped"
    assert outer["commentViewModel"].get("commentId"), "thread has no commentId"

    with_replies = [t for t in threads if "replies" in t]
    assert with_replies, "no thread carried replies"
    reply_token = continuation_of(
        with_replies[0]["replies"]["commentRepliesRenderer"]["contents"][0])
    assert reply_token, "no replies continuation on the thread"

    replies = items(fetch(reply_token))
    bare = [r for r in replies if "commentViewModel" in r]
    assert bare, "replies page holds no bare commentViewModel items"
    assert bare[0]["commentViewModel"].get("commentId"), "reply has no commentId"

    print(f"OK — {len(threads)} threads, next page token, "
          f"{len(bare)} replies on thread 1")


if __name__ == "__main__":
    main()
