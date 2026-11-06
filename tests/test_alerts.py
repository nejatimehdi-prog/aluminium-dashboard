import json

import collector.alerts as A


def latest(lme=3160.0, ch=0.8, stale=False):
    return {"cards": {"lme_cash": {"title": "LME نقدی", "unit_fa": "دلار بر تن", "value": lme, "change_pct": ch,
                                   "date": "2026-11-05", "stale": stale}}, "gap": None}


def run(tmp_path, monkeypatch, rules, lat, topic="t"):
    (tmp_path / "manual").mkdir(exist_ok=True)
    (tmp_path / "manual" / "alerts.json").write_text(json.dumps({"rules": rules}), encoding="utf-8")
    (tmp_path / "latest.json").write_text(json.dumps(lat), encoding="utf-8")
    monkeypatch.setattr(A, "RULES_FILE", tmp_path / "manual" / "alerts.json")
    monkeypatch.setattr(A, "LATEST_FILE", tmp_path / "latest.json")
    monkeypatch.setattr(A, "STATE_FILE", tmp_path / "alerts.json")
    sent = []
    monkeypatch.setattr(A, "send", lambda topic, title, msg, tags: sent.append(msg))
    if topic:
        monkeypatch.setenv("NTFY_TOPIC", topic)
    else:
        monkeypatch.delenv("NTFY_TOPIC", raising=False)
    A.check_alerts()
    return sent, json.loads((tmp_path / "alerts.json").read_text(encoding="utf-8"))


def test_threshold_sends_once_per_crossing(tmp_path, monkeypatch):
    rule = [{"id": "hi", "series": "lme_cash", "op": "above", "value": 3100, "enabled": True}]
    sent, _ = run(tmp_path, monkeypatch, rule, latest(3160))
    assert len(sent) == 1 and "۳٬۱۶۰" in sent[0]
    sent, _ = run(tmp_path, monkeypatch, rule, latest(3170))       # still above: no repeat
    assert sent == []
    sent, _ = run(tmp_path, monkeypatch, rule, latest(3050))       # back below: re-armed
    assert sent == []
    sent, _ = run(tmp_path, monkeypatch, rule, latest(3200))       # crosses again
    assert len(sent) == 1


def test_change_rule_and_disabled(tmp_path, monkeypatch):
    rules = [{"id": "mv", "series": "lme_cash", "op": "change_above", "value": 2, "enabled": True},
             {"id": "off", "series": "lme_cash", "op": "below", "value": 9999, "enabled": False}]
    sent, st = run(tmp_path, monkeypatch, rules, latest(ch=-2.6))
    assert len(sent) == 1 and "کاهش" in sent[0]
    assert {r["id"]: r["status"] for r in st["rules"]} == {"mv": "met", "off": "disabled"}


def test_without_topic_nothing_is_sent_but_alert_stays_due(tmp_path, monkeypatch):
    rule = [{"id": "hi", "series": "lme_cash", "op": "above", "value": 3100, "enabled": True}]
    sent, st = run(tmp_path, monkeypatch, rule, latest(3160), topic=None)
    assert sent == [] and st["configured"] is False and st["rules"][0]["last_key"] is None
    sent, _ = run(tmp_path, monkeypatch, rule, latest(3160))       # once configured, it goes out
    assert len(sent) == 1
