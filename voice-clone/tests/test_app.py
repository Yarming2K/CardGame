"""Tests for the app's actions (app.py), with fake engines - no model needed."""

import sys
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf

gr = pytest.importorskip("gradio")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import app  # noqa: E402
import voice_split as vs  # noqa: E402
from test_voice_split import SCRIPT, ToneVoiceprinter, energy_vad, render  # noqa: E402
from test_voiceclone import make_clip  # noqa: E402


class FakeEngine(ToneVoiceprinter):
    """Speaks (a constant tone) and voiceprints (by pitch)."""
    sample_rate = 24000

    def synthesize(self, text, reference_wavs, language):
        self.last = (text, list(reference_wavs), language)
        return np.full(12000, 0.2, dtype=np.float32)


@pytest.fixture
def fresh(tmp_path, monkeypatch):
    monkeypatch.setattr(app, "LIBRARY", app.vc.VoiceLibrary(tmp_path / "voices"))
    monkeypatch.setattr(app, "OUTPUT_DIR", tmp_path / "output")
    monkeypatch.setattr(app, "LICENCE_FLAG", tmp_path / ".model_licence_agreed")
    monkeypatch.setattr(app, "ENGINE_FACTORY", FakeEngine)
    monkeypatch.setattr(app, "_engine", None)
    monkeypatch.setattr(vs, "silero_vad", energy_vad)
    monkeypatch.delenv("COQUI_TOS_AGREED", raising=False)
    return tmp_path


def choices(dropdown):
    return [c[0] if isinstance(c, (tuple, list)) else c for c in dropdown.choices]


def test_ui_builds(fresh):
    assert isinstance(app.build_app(), gr.Blocks)


def test_add_voice_needs_name_audio_and_consent(fresh):
    clip = str(make_clip(fresh / "a.wav", 20))
    assert "Type their name" in app.handle_add("", [clip], None, "en", True)[0]
    assert "Upload recordings" in app.handle_add("Sam", [], None, "en", True)[0]
    assert "agreed" in app.handle_add("Sam", [clip], None, "en", False)[0]
    assert not app.LIBRARY.exists("Sam")

    status, speak_dd, manage_dd, table = app.handle_add("Sam", [clip], None, "en", True)
    assert status.startswith("✅") and "Saved **Sam**" in status
    assert choices(speak_dd) == ["Sam"] and speak_dd.value == "Sam"
    assert "| Sam |" in table
    assert app.LIBRARY.get("Sam").consent["method"] == "app checkbox"

    # A microphone recording can be added to the same voice.
    mic = str(make_clip(fresh / "mic.wav", 6))
    status = app.handle_add("Sam", None, mic, "en", True)[0]
    assert "Updated **Sam**" in status and len(app.LIBRARY.get("Sam").samples) == 2


def test_speak_requires_licence_then_works(fresh):
    app.handle_add("Sam", [str(make_clip(fresh / "a.wav", 20))], None, "en", True)
    audio, status = app.handle_speak("Sam", "Hello!", app.SAME_AS_VOICE)
    assert audio is None and "licence" in status

    box, msg = app.handle_accept_licence(False)
    assert "Tick the box" in msg and not app.licence_accepted()
    box, msg = app.handle_accept_licence(True)
    assert app.licence_accepted() and app.LICENCE_FLAG.exists()
    assert box.visible is False and "all set" in msg

    audio, status = app.handle_speak("Sam", "Hello!", app.SAME_AS_VOICE)
    assert status.startswith("✅") and Path(audio).exists()
    assert Path(audio).parent == app.OUTPUT_DIR
    with sf.SoundFile(audio) as f:
        assert "AI-GENERATED" in f.comment
    assert app._engine.last[2] == "en"
    app.handle_speak("Sam", "Hola", "es")
    assert app._engine.last[2] == "es"

    assert "Type what" in app.handle_speak("Sam", "  ", "en")[1]
    assert "Pick a voice" in app.handle_speak(None, "hi", "en")[1]
    assert "No voice called" in app.handle_speak("Nobody", "hi", "en")[1]


def test_split_video_then_add_a_speaker(fresh):
    app.handle_accept_licence(True)
    video = fresh / "Game Night.wav"
    sf.write(str(video), render(SCRIPT, 44100), 44100)

    out = app.handle_split(str(video), "auto")
    state, status, slots = out[0], out[1], out[2:]
    assert "Found **3 voices**" in status
    assert len(slots) == 6 * app.MAX_SLOTS
    cards = [slots[i * 6:(i + 1) * 6] for i in range(app.MAX_SLOTS)]
    assert [c[0].visible for c in cards[:4]] == [True, True, True, False]
    assert "Speaker 1" in cards[0][1] and Path(cards[0][2]).exists()
    assert state["speakers"] == ["speaker_1", "speaker_2", "speaker_3"]

    assert "Type who" in app.handle_add_from_split(0, state, "", True, "en")[0]
    assert "agreed" in app.handle_add_from_split(0, state, "Alex", False, "en")[0]
    status, speak_dd, _, table = app.handle_add_from_split(0, state, "Alex", True, "en")
    assert status.startswith("✅") and choices(speak_dd) == ["Alex"]
    assert "Find the voices" in app.handle_add_from_split(5, state, "X", True, "en")[0]

    # Choosing the number of people works too.
    out = app.handle_split(str(video), "2")
    assert "Found **2 voices**" in out[1]


def test_split_errors_are_friendly(fresh):
    assert "Choose a video" in app.handle_split(None, "auto")[1]
    app.handle_accept_licence(True)
    quiet = fresh / "quiet.wav"
    sf.write(str(quiet), np.zeros(22050, dtype=np.float32), 22050)
    out = app.handle_split(str(quiet), "auto")
    assert "has no sound" in out[1] and out[0] == {}
    assert all(not c.visible for c in out[2::6])


def test_delete_voice(fresh):
    app.handle_add("Sam", [str(make_clip(fresh / "a.wav", 20))], None, "en", True)
    assert "confirm deleting" in app.handle_delete("Sam", False)[0]
    status, speak_dd, _, table, confirm = app.handle_delete("Sam", True)
    assert "Deleted **Sam**" in status and choices(speak_dd) == [] and confirm is False
    assert "No voices yet" in table
