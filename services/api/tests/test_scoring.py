from app.scoring import score_result


def test_score_prefers_official_mv():
    official, official_tags = score_result("晴天", "晴天 官方MV", 240)
    cover, cover_tags = score_result("晴天", "晴天 翻唱 cover", 240)

    assert official > cover
    assert "官方" in official_tags or "mv" in official_tags
    assert "cover" in cover_tags


def test_score_penalizes_unusual_duration():
    normal, _ = score_result("夜曲", "夜曲 Official MV", 260)
    long, tags = score_result("夜曲", "夜曲 Official MV 10 hours", 36000)

    assert normal > long
    assert "duration-risk" in tags
