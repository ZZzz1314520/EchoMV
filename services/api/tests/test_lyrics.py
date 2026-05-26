from app.lyrics import parse_lrc


def test_parse_lrc_supports_multiple_timestamps_and_millis():
    lines = parse_lrc("[00:01.20][00:02.345]Hello\n[01:00]World\n")

    assert [line.time_ms for line in lines] == [1200, 2345, 60000]
    assert [line.text for line in lines] == ["Hello", "Hello", "World"]


def test_parse_lrc_skips_empty_text():
    assert parse_lrc("[00:01.00]\n[ar:EchoMV]") == []
