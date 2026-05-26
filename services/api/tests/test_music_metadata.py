from app.music_metadata import infer_track_and_artist


def test_infer_track_and_artist_from_noisy_mv_title():
    title, artist = infer_track_and_artist("【4K修复】周杰伦 - 晴天MV 2160P修复版", "zyl2012_音乐无限")

    assert title == "晴天"
    assert artist == "周杰伦"


def test_infer_track_and_artist_from_plain_title():
    title, artist = infer_track_and_artist("周杰伦 - 晴天 官方MV 2160P")

    assert title == "晴天"
    assert artist == "周杰伦"
