"""Tests for voice_split.py using a fake voiceprinter (no model needed).

Each fake "person" is a tone at their own pitch; the fake voiceprint is how much
energy a window has at each person's pitch, so mixed/overlapping speech gives a
mixed voiceprint - like the real thing.
"""

import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import voice_split as vs  # noqa: E402
import voiceclone as vc  # noqa: E402

PITCHES = {"A": 200.0, "B": 330.0, "C": 520.0}


class ToneVoiceprinter:
    def __init__(self):
        self.windows_seen = 0

    def embed(self, windows):
        self.windows_seen += len(windows)
        spec = np.abs(np.fft.rfft(windows, axis=1))
        freqs = np.fft.rfftfreq(windows.shape[1], 1 / vs.VAD_SR)
        feats = [spec[:, (freqs > f - 15) & (freqs < f + 15)].sum(axis=1) for f in PITCHES.values()]
        return np.stack(feats, axis=1) + 1e-3


def energy_vad(audio16k):
    frame = int(0.05 * vs.VAD_SR)
    rms = np.sqrt(np.mean(audio16k[: len(audio16k) // frame * frame].reshape(-1, frame) ** 2, axis=1))
    regions, start = [], None
    for i, loud in enumerate(rms > 0.01):
        if loud and start is None:
            start = i
        elif not loud and start is not None:
            regions.append((start * 0.05, i * 0.05))
            start = None
    if start is not None:
        regions.append((start * 0.05, len(rms) * 0.05))
    return regions


# (start, end, who) - "AB" means both talking at once.
SCRIPT = [
    (0.5, 7.0, "A"), (7.5, 12.0, "B"), (12.5, 18.0, "A"), (18.5, 21.5, "AB"),
    (22.0, 29.0, "C"), (29.5, 35.0, "B"), (35.5, 40.0, "C"), (40.5, 41.2, "B"),
]


def render(script, sr, length=42.0):
    t = np.arange(int(length * sr)) / sr
    audio = np.zeros_like(t)
    for start, end, who in script:
        mask = (t >= start) & (t < end)
        for person in who:
            audio[mask] += 0.3 * np.sin(2 * np.pi * PITCHES[person] * t[mask])
    return audio.astype(np.float32)


def truth_at(t):
    for start, end, who in SCRIPT:
        if start <= t < end:
            return who
    return ""


@pytest.fixture
def conversation(tmp_path):
    path = tmp_path / "Game Night.wav"
    sf.write(str(path), render(SCRIPT, 44100), 44100)
    return path


def test_make_windows():
    assert vs.make_windows([(0.0, 0.8)]) == []  # too short to identify
    assert vs.make_windows([(1.0, 2.5)]) == [(1.0, 2.5)]
    wins = vs.make_windows([(0.0, 3.2)])
    assert wins[0] == (0.0, 2.0) and wins[-1] == pytest.approx((1.2, 3.2))
    assert all(abs((e - s) - vs.WINDOW_S) < 1e-9 for s, e in wins)


def test_cluster_counts():
    rng = np.random.default_rng(0)
    centers = np.eye(3, 8)
    embs = np.concatenate([c + 0.05 * rng.standard_normal((20, 8)) for c in centers])
    embs /= np.linalg.norm(embs, axis=1, keepdims=True)
    labels = vs.cluster(embs)
    assert len(set(labels)) == 3
    assert all(len(set(labels[i * 20:(i + 1) * 20])) == 1 for i in range(3))
    assert len(set(vs.cluster(embs, n_speakers=2))) == 2
    with pytest.raises(vc.VoiceCloneError, match="enough speech"):
        vs.cluster(embs[:2], n_speakers=3)


def test_split_finds_each_voice_and_skips_overlap(conversation, tmp_path):
    out = tmp_path / "split"
    result = vs.split_file(conversation, out, ToneVoiceprinter, vad=energy_vad)

    # Three people; speaker_1 talks the most (A: 13s, B: 10s, C: 11.5s).
    assert len(result.speakers) == 3
    who = {}
    for spk in result.speakers:
        labels = {truth_at((s.start + s.end) / 2) for s in spk.segments}
        assert len(labels) == 1 and labels != {"AB"}, (spk.name, labels)
        who[spk.name] = labels.pop()
    assert who == {"speaker_1": "A", "speaker_2": "C", "speaker_3": "B"}
    assert result.unclear_seconds >= 2.5  # the 3 s overlap was skipped

    # No saved clip contains anyone else (short pauses inside a clip are fine).
    for spk in result.speakers:
        assert spk.clips and spk.clip_seconds <= vs.CLIPS_TARGET_S + vs.CLIP_MAX_S
        for clip in spk.clips:
            assert vs.CLIP_MIN_S <= clip.duration <= vs.CLIP_MAX_S + 1e-6
            heard = {truth_at(t) for t in np.arange(clip.start, clip.end, 0.05)}
            assert who[spk.name] in heard and heard <= {who[spk.name], ""}, (spk.name, clip, heard)
        files = sorted((out / spk.name).glob("clip_*.wav"))
        assert len(files) == len(spk.clips)
        assert sf.info(str(files[0])).samplerate == vc.SAMPLE_RATE
        assert (out / f"{spk.name}_preview.wav").exists()

    report = (out / "report.txt").read_text()
    assert "speaker_1" in report and "Game Night.wav" in report and "voiceclone.py add" in report


def test_merge_similar_voices():
    rng = np.random.default_rng(1)
    a = np.array([1.0, 0.0, 0.0, 0.0])
    a2 = np.array([0.85, 0.53, 0.0, 0.0])  # same person, sounding a bit different (sim ~0.85)
    b = np.array([0.0, 0.0, 1.0, 0.0])
    embs = np.concatenate([v + 0.03 * rng.standard_normal((15, 4)) for v in (a, a2, b)])
    embs /= np.linalg.norm(embs, axis=1, keepdims=True)
    labels = np.repeat([0, 1, 2], 15)
    merged = vs.merge_similar_voices(embs, labels)
    assert len(set(merged[:30])) == 1 and len(set(merged)) == 2


def test_fixed_speaker_count_and_rerun_cleans_up(conversation, tmp_path):
    out = tmp_path / "split"
    vs.split_file(conversation, out, ToneVoiceprinter, vad=energy_vad)
    assert (out / "speaker_3").exists()
    result = vs.split_file(conversation, out, ToneVoiceprinter, n_speakers=2, vad=energy_vad)
    assert len(result.speakers) == 2
    assert not (out / "speaker_3").exists() and not (out / "speaker_3_preview.wav").exists()


def test_no_speech(tmp_path):
    quiet = tmp_path / "quiet.wav"
    sf.write(str(quiet), np.zeros(22050 * 3, dtype=np.float32), 22050)
    with pytest.raises(vc.VoiceCloneError, match="no sound"):
        vs.split_file(quiet, tmp_path / "o", ToneVoiceprinter, vad=energy_vad)
    hum = tmp_path / "hum.wav"
    sf.write(str(hum), 0.001 * np.ones(22050 * 3, dtype=np.float32), 22050)
    with pytest.raises(vc.VoiceCloneError, match="Couldn't hear anyone"):
        vs.split_file(hum, tmp_path / "o", ToneVoiceprinter, vad=energy_vad)


def test_cli_split_then_add_folder(conversation, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(vs, "silero_vad", energy_vad)
    monkeypatch.setattr(sys.stdin, "isatty", lambda: False)
    voices = tmp_path / "voices"
    args = vc.build_parser().parse_args(
        ["--voices-dir", str(voices), "split", str(conversation), "--output-dir", str(tmp_path / "output")])
    assert vc.cmd_split(args, vc.VoiceLibrary(voices), printer_factory=ToneVoiceprinter) == 0
    printed = capsys.readouterr().out
    assert "Found 3 voices" in printed and "preview.wav" in printed
    folder = tmp_path / "output" / "split" / "game-night" / "speaker_1"
    assert folder.is_dir()

    # `add` takes the whole folder (and still requires consent).
    assert vc.main(["--voices-dir", str(voices), "add", "Alex", str(folder)]) == 1
    assert vc.main(["--voices-dir", str(voices), "add", "Alex", str(folder), "--consent"]) == 0
    assert len(vc.VoiceLibrary(voices).get("Alex").samples) == len(list(folder.glob("clip_*.wav")))


def test_expand_clip_args(tmp_path):
    (tmp_path / "d").mkdir()
    for name in ["b.wav", "a.m4a", "notes.txt"]:
        (tmp_path / "d" / name).write_bytes(b"x")
    assert [p.name for p in vc.expand_clip_args([str(tmp_path / "d")])] == ["a.m4a", "b.wav"]
    assert [p.name for p in vc.expand_clip_args([str(tmp_path / "d" / "*.wav")])] == ["b.wav"]
    (tmp_path / "empty").mkdir()
    with pytest.raises(vc.VoiceCloneError, match="No audio files"):
        vc.expand_clip_args([str(tmp_path / "empty")])
    with pytest.raises(vc.VoiceCloneError, match="No files match"):
        vc.expand_clip_args([str(tmp_path / "*.flac")])


def test_script_errors_are_friendly(tmp_path):
    """Run as a real script: errors from voice_split must be caught by main()."""
    quiet = tmp_path / "quiet.wav"
    sf.write(str(quiet), np.zeros(22050, dtype=np.float32), 22050)
    run = subprocess.run([sys.executable, str(ROOT / "voiceclone.py"), "split", str(quiet),
                          "--out", str(tmp_path / "o")], capture_output=True, text=True)
    assert run.returncode == 1
    assert "Error: 'quiet.wav' has no sound." in run.stderr and "Traceback" not in run.stderr
