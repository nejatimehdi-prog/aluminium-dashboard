from collector.gitsync import merge_series, merge_status


def test_merge_status_newer_entry_wins():
    a = {"updated_at": "2026-11-06T10:00:00Z", "collectors": {
        "ime": {"ok": False, "last_attempt": "2026-11-06T10:00:00Z"},
        "yahoo": {"ok": True, "last_attempt": "2026-11-06T10:00:00Z"}}}
    b = {"updated_at": "2026-11-06T09:00:00Z", "collectors": {
        "ime": {"ok": True, "last_attempt": "2026-11-06T10:05:00Z"},
        "yahoo": {"ok": False, "last_attempt": "2026-11-06T09:00:00Z"}}}
    m = merge_status(a, b)
    assert m["collectors"]["ime"]["ok"] is True      # b is newer for ime
    assert m["collectors"]["yahoo"]["ok"] is True    # a is newer for yahoo
    assert m["updated_at"] == "2026-11-06T10:00:00Z"


def test_merge_series_unites_points():
    a = {"id": "x", "fetched_at": "2026-11-06T10:00:00Z", "points": [["2026-11-01", 1], ["2026-11-02", 2]]}
    b = {"id": "x", "fetched_at": "2026-11-06T11:00:00Z", "points": [["2026-11-02", 3], ["2026-11-03", 4]]}
    m = merge_series(a, b)
    assert m["points"] == [["2026-11-01", 1], ["2026-11-02", 3], ["2026-11-03", 4]]
    assert m["fetched_at"] == "2026-11-06T11:00:00Z"
