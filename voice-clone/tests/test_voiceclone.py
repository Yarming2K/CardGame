"""Tests for voiceclone.py that don't need the (large) XTTS model.

Run with:  python -m pytest tests
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import voiceclone as vc  # noqa: E402


def make_clip(path: Path, seconds: float, sr: int = 44100, channels: int = 2,
              silence: float = 0.5, amplitude: float = 0.1) -> Path:
    """A fake 'voice' recording: a tone padded with silence."""
    t = np.arange(int(seconds * sr)) / sr
    tone = amplitude * np.sin(2 * np.pi * 220 * t) * (1 + 0.3 * np.sin(2 * np.pi * 3 * t))
    pad = np.zeros(int(silence * sr))
    mono = np.concatenate([pad, tone, pad]).astype(np.float32)
    data = np.stack([mono] * channels, axis=1) if channels > 1 else mono
    sf.write(str(path), data, sr)
    return path


class FakeEngine:
    sample_rate = 24000

    def __init__(self, device=None):
        self.calls = []

    def synthesize(self, text, reference_wavs, language):
        self.calls.append((text, list(reference_wavs), language))
        return np.full(self.sample_rate // 2, 0.25, dtype=np.float32)


CONSENT = {"confirmed": True, "method": "test"}


@pytest.fixture
def lib(tmp_path):
    return vc.VoiceLibrary(tmp_path / "voices")


def test_add_cleans_clips(tmp_path, lib):
    clip = make_clip(tmp_path / "a.wav", seconds=8, sr=44100, channels=2, amplitude=0.05)
    profile, warnings = lib.add("Sam Smith", [clip], CONSENT)

    assert profile.folder.name == "sam-smith"
    assert profile.samples == ["sample_01.wav"]
    info = sf.info(str(profile.sample_paths[0]))
    assert info.samplerate == vc.SAMPLE_RATE and info.channels == 1
    # Silence trimmed (~8s of tone, not 9s) and volume normalised.
    assert 7.5 < info.duration < 8.3
    audio, _ = sf.read(str(profile.sample_paths[0]))
    assert 0.85 < np.max(np.abs(audio)) <= 0.91
    # 8s is enough to work but below the recommended amount.
    assert any("usually sounds noticeably better" in w for w in warnings)

    saved = json.loads((profile.folder / "profile.json").read_text())
    assert saved["name"] == "Sam Smith" and saved["consent"]["confirmed"] is True


def test_add_more_clips_to_existing_voice(tmp_path, lib):
    lib.add("Sam", [make_clip(tmp_path / "a.wav", 8)], CONSENT)
    profile, warnings = lib.add("sam", [make_clip(tmp_path / "b.flac", 10)], {})
    assert profile.samples == ["sample_01.wav", "sample_02.wav"]
    assert profile.consent["confirmed"] is True  # original consent kept
    assert warnings == []  # 18s total
    assert len(lib.all()) == 1


def test_short_and_missing_clips(tmp_path, lib):
    short = make_clip(tmp_path / "short.wav", 1)
    with pytest.raises(vc.VoiceCloneError, match="None of the recordings"):
        lib.add("Sam", [short], CONSENT)
    assert not lib.exists("Sam")  # nothing half-created

    profile, warnings = lib.add("Sam", [short, make_clip(tmp_path / "ok.wav", 4)], CONSENT)
    assert len(profile.samples) == 1
    assert any("Skipped 'short.wav'" in w for w in warnings)
    assert any("add more" in w for w in warnings)

    with pytest.raises(vc.VoiceCloneError, match="File not found"):
        lib.add("Alex", [tmp_path / "nope.wav"], CONSENT)
    with pytest.raises(vc.VoiceCloneError, match="File not found"):
        lib.add("Alex", [make_clip(tmp_path / "c.wav", 8)], CONSENT, consent_recording=tmp_path / "nope.m4a")
    assert not lib.exists("Alex")


def test_silent_clip_rejected(tmp_path, lib):
    path = tmp_path / "silent.wav"
    sf.write(str(path), np.zeros(22050 * 5, dtype=np.float32), 22050)
    with pytest.raises(vc.VoiceCloneError, match="silent"):
        lib.add("Sam", [path], CONSENT)


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="ffmpeg not installed")
def test_m4a_via_ffmpeg(tmp_path, lib):
    wav = make_clip(tmp_path / "src.wav", 8)
    m4a = tmp_path / "memo.m4a"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), str(m4a)], check=True)
    profile, _ = lib.add("Sam", [m4a], CONSENT)
    assert 7.5 < profile.total_seconds() < 8.3


def test_consent_recording_kept(tmp_path, lib):
    rec = make_clip(tmp_path / "I agree.WAV", 3)
    profile, _ = lib.add("Sam", [make_clip(tmp_path / "a.wav", 8)], dict(CONSENT), consent_recording=rec)
    assert (profile.folder / "consent.wav").exists()
    assert vc.Profile.load(profile.folder).consent["recording"] == "consent.wav"


def test_speak_writes_tagged_wav(tmp_path, lib):
    profile, _ = lib.add("Sam", [make_clip(tmp_path / "a.wav", 8), make_clip(tmp_path / "b.wav", 8)], CONSENT)
    engine = FakeEngine()
    out = vc.speak(engine, profile, "  Hello there!  ", tmp_path / "out" / "hi.wav")

    text, refs, lang = engine.calls[0]
    assert text == "Hello there!" and lang == "en" and refs == profile.sample_paths
    with sf.SoundFile(str(out)) as f:
        assert f.samplerate == 24000 and f.frames == 12000
        assert "AI-GENERATED" in f.comment and "Sam" in f.title

    with pytest.raises(vc.VoiceCloneError, match="empty"):
        vc.speak(engine, profile, "   ", tmp_path / "x.wav")
    with pytest.raises(vc.VoiceCloneError, match="Unsupported language"):
        vc.speak(engine, profile, "hola", tmp_path / "x.wav", language="xx")


def test_cli_end_to_end(tmp_path, monkeypatch, capsys):
    voices = str(tmp_path / "voices")
    clip = str(make_clip(tmp_path / "a.wav", 20))

    # Without a TTY and without --consent, adding is refused.
    monkeypatch.setattr(sys.stdin, "isatty", lambda: False)
    assert vc.main(["--voices-dir", voices, "add", "Sam", clip]) == 1
    assert "--consent" in capsys.readouterr().err

    assert vc.main(["--voices-dir", voices, "add", "Sam", clip, "--consent", "--note", "said yes"]) == 0
    assert "Saved voice 'Sam'" in capsys.readouterr().out

    assert vc.main(["--voices-dir", voices, "list"]) == 0
    assert "Sam" in capsys.readouterr().out

    # `say` with the real engine swapped for the fake one.
    monkeypatch.setattr(vc, "XTTSEngine", FakeEngine)
    args = vc.build_parser().parse_args(
        ["--voices-dir", voices, "say", "Sam", "hi", "everyone", "-o", str(tmp_path / "o.wav")])
    assert vc.cmd_say(args, vc.VoiceLibrary(Path(voices)), engine_factory=FakeEngine) == 0
    assert (tmp_path / "o.wav").exists()

    assert vc.main(["--voices-dir", voices, "say", "Nobody", "hi"]) == 1
    assert "No voice called 'Nobody'" in capsys.readouterr().err

    assert vc.main(["--voices-dir", voices, "remove", "Sam"]) == 1  # needs --yes without a TTY
    assert vc.main(["--voices-dir", voices, "remove", "Sam", "--yes"]) == 0
    assert not (tmp_path / "voices" / "sam").exists()


def test_interactive_say(tmp_path, monkeypatch, lib):
    lib.add("Sam", [make_clip(tmp_path / "a.wav", 20)], CONSENT)
    lines = iter(["first line", "second line", ""])
    monkeypatch.setattr("builtins.input", lambda prompt="": next(lines))
    engine = FakeEngine()
    args = vc.build_parser().parse_args(
        ["--voices-dir", str(lib.root), "say", "Sam", "--output-dir", str(tmp_path / "out")])
    assert vc.cmd_say(args, lib, engine_factory=lambda device: engine) == 0
    assert [c[0] for c in engine.calls] == ["first line", "second line"]
    assert len(list((tmp_path / "out").glob("sam_*.wav"))) == 2


def test_interactive_consent_prompt():
    assert vc.confirm_consent("Sam", ask=lambda q: "yes")["confirmed"] is True
    with pytest.raises(vc.VoiceCloneError, match="without their permission"):
        vc.confirm_consent("Sam", ask=lambda q: "no")


def test_slugify():
    assert vc.slugify("  Big Mike!! ") == "big-mike"
    with pytest.raises(vc.VoiceCloneError):
        vc.slugify("!!!")
