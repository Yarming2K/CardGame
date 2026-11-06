"""Find the different voices in a recording or video and cut out clean clips of each.

How it works:
  1. Pull the audio out of the file (FFmpeg handles videos).
  2. Find where anyone is talking (Silero voice-activity detection).
  3. Take a "voiceprint" of every couple of seconds of speech, using XTTS's own
     speaker encoder - the same idea of "a voice" the cloning uses.
  4. Group similar voiceprints together: each group is one person.
  5. Keep only the stretches where exactly one person is clearly talking
     (overlaps and unclear bits are skipped) and save the best ones per person,
     ready for `voiceclone.py add`.

Used through `python voiceclone.py split <file>`.
"""

from __future__ import annotations

import math
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Protocol, Sequence

import numpy as np

from voiceclone import SAMPLE_RATE, VoiceCloneError, load_audio, write_wav

VAD_SR = 16000             # the VAD and the speaker encoder both work at 16 kHz
WINDOW_S = 2.0             # each voiceprint is taken from this much audio...
HOP_S = 0.5                # ...every this many seconds
MERGE_GAP_S = 0.6          # pauses shorter than this don't split up speech
MIN_REGION_S = 1.0         # speech bursts shorter than this are too short to identify
FRAME_S = 0.05             # time resolution of the final speaker timeline
DISTANCE_THRESHOLD = 0.62  # how different two voiceprints must be to count as different people
CENTROID_MERGE_SIM = 0.72  # voice groups whose averages are this similar are one person
MIN_MARGIN = 0.04          # a window must match its own voice this much better than any other
AGREEMENT = 0.75           # share of overlapping windows that must agree on who's talking
OUTLIER_MADS = 3.0         # windows this atypical for their voice are skipped (overlaps, laughs)
MIN_MAD = 0.02
MIN_SPEAKER_S = 5.0        # "voices" with less clear speech than this are noise, laughs, etc.
MIN_SEGMENT_S = 1.0
BOUNDARY_TRIM_S = 0.2      # trimmed where one voice hands over to another, to avoid bleed
CLIP_MIN_S = 2.0
CLIP_MAX_S = 12.0
CLIPS_TARGET_S = 30.0      # XTTS gains little from more reference audio than this
PREVIEW_MAX_S = 15.0
MAX_CLUSTER_WINDOWS = 2500 # cluster a sample of very long files, then assign the rest
BATCH = 32

Region = tuple[float, float]


class Voiceprinter(Protocol):
    def embed(self, windows: np.ndarray) -> np.ndarray:
        """[B, T] float32 audio at 16 kHz -> [B, D] voiceprints."""
        ...


VadFn = Callable[[np.ndarray], list[Region]]


def silero_vad(audio16k: np.ndarray) -> list[Region]:
    """Return (start, end) seconds of every stretch of speech."""
    import torch
    from silero_vad import get_speech_timestamps, load_silero_vad

    stamps = get_speech_timestamps(
        torch.from_numpy(audio16k), load_silero_vad(), sampling_rate=VAD_SR,
        return_seconds=True, min_speech_duration_ms=400, min_silence_duration_ms=250,
        speech_pad_ms=50,
    )
    return [(float(s["start"]), float(s["end"])) for s in stamps]


@dataclass
class Segment:
    start: float
    end: float
    speaker: int
    confidence: float = 0.0

    @property
    def duration(self) -> float:
        return self.end - self.start


@dataclass
class Speaker:
    number: int
    segments: list[Segment]
    clips: list[Segment] = field(default_factory=list)

    @property
    def name(self) -> str:
        return f"speaker_{self.number}"

    @property
    def speech_seconds(self) -> float:
        return sum(s.duration for s in self.segments)

    @property
    def clip_seconds(self) -> float:
        return sum(c.duration for c in self.clips)


@dataclass
class SplitResult:
    duration: float
    speech_seconds: float
    unclear_seconds: float
    speakers: list[Speaker]
    out_dir: Path | None = None


def fmt_time(seconds: float) -> str:
    seconds = max(0, int(round(seconds)))
    h, rest = divmod(seconds, 3600)
    m, s = divmod(rest, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


# --------------------------------------------------------------------------
# Who is talking when
# --------------------------------------------------------------------------

def make_windows(regions: Sequence[Region]) -> list[Region]:
    """Overlapping WINDOW_S chunks covering each speech region."""
    windows: list[Region] = []
    for start, end in regions:
        length = end - start
        if length < MIN_REGION_S:
            continue
        if length <= WINDOW_S:
            windows.append((start, end))
            continue
        count = int(math.floor((length - WINDOW_S) / HOP_S + 1e-9)) + 1
        windows.extend((start + i * HOP_S, start + i * HOP_S + WINDOW_S) for i in range(count))
        if windows[-1][1] < end - 1e-6:
            windows.append((end - WINDOW_S, end))
    return windows


def embed_windows(audio16k: np.ndarray, windows: Sequence[Region], printer: Voiceprinter) -> np.ndarray:
    """L2-normalised voiceprint for each window (batched by length)."""
    by_length: dict[int, list[tuple[int, int]]] = {}
    for i, (start, end) in enumerate(windows):
        length = min(int(round((end - start) * VAD_SR)), len(audio16k))
        offset = min(int(round(start * VAD_SR)), len(audio16k) - length)
        by_length.setdefault(length, []).append((i, offset))

    out: list[np.ndarray | None] = [None] * len(windows)
    for length, items in by_length.items():
        for k in range(0, len(items), BATCH):
            chunk = items[k:k + BATCH]
            batch = np.stack([audio16k[o:o + length] for _, o in chunk])
            for (i, _), emb in zip(chunk, printer.embed(batch)):
                emb = np.asarray(emb, dtype=np.float64).ravel()
                out[i] = emb / (np.linalg.norm(emb) + 1e-9)
    return np.stack(out)  # type: ignore[arg-type]


def _centroids(embs: np.ndarray, labels: np.ndarray, k: int) -> np.ndarray:
    cents = np.zeros((k, embs.shape[1]))
    for c in range(k):
        members = embs[labels == c]
        if len(members):
            mean = members.mean(axis=0)
            cents[c] = mean / (np.linalg.norm(mean) + 1e-9)
    return cents


def cluster(embs: np.ndarray, n_speakers: int | None = None,
            threshold: float | None = None) -> np.ndarray:
    """Group voiceprints into speakers. Returns a label per window (0..k-1)."""
    threshold = DISTANCE_THRESHOLD if threshold is None else threshold
    n = len(embs)
    if n_speakers is not None and n_speakers > n:
        raise VoiceCloneError(
            f"There isn't enough speech to tell {n_speakers} voices apart. "
            "Try a longer recording or a smaller --speakers number.")
    if n <= 1 or n_speakers == 1:
        return np.zeros(n, dtype=int)

    from sklearn.cluster import AgglomerativeClustering

    sample = np.arange(n)
    if n > MAX_CLUSTER_WINDOWS:
        sample = np.unique(np.linspace(0, n - 1, MAX_CLUSTER_WINDOWS).round().astype(int))
    algo = AgglomerativeClustering(
        n_clusters=n_speakers, distance_threshold=None if n_speakers else threshold,
        metric="cosine", linkage="average",
    )
    first = algo.fit_predict(embs[sample])
    k = int(first.max()) + 1
    labels = (embs @ _centroids(embs[sample], first, k).T).argmax(axis=1)

    # A couple of rounds of "move each window to the closest voice", dropping
    # any voice that ends up empty.
    for _ in range(3):
        used = np.unique(labels)
        labels = np.searchsorted(used, labels)
        cents = _centroids(embs, labels, len(used))
        new = (embs @ cents.T).argmax(axis=1)
        if np.array_equal(new, labels):
            break
        labels = new
    return np.searchsorted(np.unique(labels), labels)


def diarize(audio16k: np.ndarray, regions: Sequence[Region], printer: Voiceprinter,
            n_speakers: int | None = None) -> SplitResult:
    """Work out who is talking when. Only clear, single-voice speech is kept."""
    duration = len(audio16k) / VAD_SR
    speech_seconds = float(sum(e - s for s, e in regions))
    # The VAD splits at every breath; join pauses so whole sentences are kept.
    # Speaker changes inside a joined stretch are still found by the voting below.
    regions = merge_regions(regions)
    windows = make_windows(regions)
    if not windows:
        return SplitResult(duration, speech_seconds, speech_seconds, [])

    embs = embed_windows(audio16k, windows, printer)
    labels = cluster(embs, n_speakers)
    if n_speakers is None:
        labels = merge_similar_voices(embs, labels)
    k = int(labels.max()) + 1

    # Overlapping voices, laughs and noise give voiceprints that sit between or
    # away from everyone. Find those outliers, rebuild each person's average
    # voiceprint from their typical windows only, then check again.
    keep = np.ones(len(labels), dtype=bool)
    for _ in range(2):
        cents = _centroids(embs[keep], labels[keep], k)
        sims = embs @ cents.T
        own = sims[np.arange(len(labels)), labels]
        keep = _typical(own, labels, k)
    others = np.where(np.eye(k, dtype=bool)[labels], -np.inf, sims).max(axis=1) if k > 1 \
        else np.full(len(labels), -1.0)
    margins = np.where(keep, own - others, -np.inf)

    # Vote on a fine timeline: each confident window votes for its speaker.
    n_frames = int(math.ceil(duration / FRAME_S)) + 1
    votes = np.zeros((n_frames, k))
    for (start, end), label, margin in zip(windows, labels, margins):
        if margin >= MIN_MARGIN:
            votes[int(start / FRAME_S):int(math.ceil(end / FRAME_S)), label] += 1
    in_speech = np.zeros(n_frames, dtype=bool)
    for start, end in regions:
        in_speech[int(start / FRAME_S):int(math.ceil(end / FRAME_S))] = True

    total = votes.sum(axis=1)
    top = votes.argmax(axis=1)
    agreed = (total > 0) & (votes.max(axis=1) >= AGREEMENT * np.maximum(total, 1e-9)) & in_speech
    frame_label = np.where(agreed, top, -1)

    segments = _frames_to_segments(frame_label, in_speech)
    for seg in segments:
        inside = [m for (s, e), lab, m in zip(windows, labels, margins)
                  if lab == seg.speaker and s < seg.end and e > seg.start and m >= MIN_MARGIN]
        seg.confidence = float(np.mean(inside)) if inside else 0.0

    by_speaker: dict[int, list[Segment]] = {}
    for seg in segments:
        by_speaker.setdefault(seg.speaker, []).append(seg)
    speakers = [Speaker(0, segs) for segs in by_speaker.values()]
    if n_speakers is None:  # in auto mode, tiny "voices" are noise, laughs or bleed
        speakers = [s for s in speakers if s.speech_seconds >= MIN_SPEAKER_S]
    speakers.sort(key=lambda s: -s.speech_seconds)
    for number, spk in enumerate(speakers, 1):
        spk.number = number

    kept = np.zeros(n_frames, dtype=bool)
    for spk in speakers:
        for seg in spk.segments:
            kept[int(seg.start / FRAME_S):int(seg.end / FRAME_S)] = True
    unclear = float((in_speech & ~kept).sum() * FRAME_S)
    return SplitResult(duration, speech_seconds, min(unclear, speech_seconds), speakers)


def merge_regions(regions: Sequence[Region], gap: float | None = None) -> list[Region]:
    """Join speech regions separated by pauses shorter than `gap` seconds."""
    gap = MERGE_GAP_S if gap is None else gap
    merged: list[Region] = []
    for start, end in sorted(regions):
        if merged and start - merged[-1][1] <= gap:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def merge_similar_voices(embs: np.ndarray, labels: np.ndarray, min_sim: float | None = None) -> np.ndarray:
    """Merge groups whose typical voiceprints are this similar: they're one person.

    Window-by-window grouping can split one person into two (e.g. when they sound
    different across a recording); whole-group averages are far less noisy.
    """
    min_sim = CENTROID_MERGE_SIM if min_sim is None else min_sim
    labels = labels.copy()
    while True:
        labels = np.searchsorted(np.unique(labels), labels)
        k = int(labels.max()) + 1 if len(labels) else 0
        if k < 2:
            return labels
        cents = _centroids(embs, labels, k)
        keep = _typical((embs @ cents.T)[np.arange(len(labels)), labels], labels, k)
        cents = _centroids(embs[keep], labels[keep], k)
        sim = cents @ cents.T
        np.fill_diagonal(sim, -1.0)
        i, j = np.unravel_index(int(sim.argmax()), sim.shape)
        if sim[i, j] < min_sim:
            return labels
        labels[labels == j] = i


def _typical(own: np.ndarray, labels: np.ndarray, k: int) -> np.ndarray:
    """True for windows whose match to their own voice is normal for that voice
    (robust outlier test: within OUTLIER_MADS median-absolute-deviations)."""
    keep = np.ones(len(own), dtype=bool)
    for c in range(k):
        members = labels == c
        if members.sum() < 5:
            continue
        med = np.median(own[members])
        mad = max(float(np.median(np.abs(own[members] - med))), MIN_MAD)
        keep[members] = own[members] >= med - OUTLIER_MADS * mad
    return keep


def _frames_to_segments(frame_label: np.ndarray, in_speech: np.ndarray) -> list[Segment]:
    """Runs of one speaker -> segments, trimmed where they touch someone else."""
    segments: list[Segment] = []
    n = len(frame_label)
    near = int(round(0.5 / FRAME_S))
    i = 0
    while i < n:
        label = frame_label[i]
        if label < 0:
            i += 1
            continue
        j = i
        while j < n and frame_label[j] == label:
            j += 1
        start, end = i * FRAME_S, j * FRAME_S
        before = slice(max(0, i - near), i)
        after = slice(j, min(n, j + near))
        if _someone_else(frame_label[before], in_speech[before], label):
            start += BOUNDARY_TRIM_S
        if _someone_else(frame_label[after], in_speech[after], label):
            end -= BOUNDARY_TRIM_S
        if end - start >= MIN_SEGMENT_S:
            segments.append(Segment(start, end, int(label)))
        i = j
    return segments


def _someone_else(labels: np.ndarray, speech: np.ndarray, me: int) -> bool:
    return bool(np.any((labels >= 0) & (labels != me)) or np.any(speech & (labels < 0)))


# --------------------------------------------------------------------------
# Picking and saving clips
# --------------------------------------------------------------------------

def choose_clips(speaker: Speaker) -> list[Segment]:
    """Best CLIP_MIN_S..CLIP_MAX_S pieces of a speaker, up to CLIPS_TARGET_S total."""
    pieces: list[Segment] = []
    for seg in speaker.segments:
        if seg.duration < CLIP_MIN_S:
            continue
        parts = int(math.ceil(seg.duration / CLIP_MAX_S))
        step = seg.duration / parts
        pieces.extend(Segment(seg.start + p * step, seg.start + (p + 1) * step, seg.speaker, seg.confidence)
                      for p in range(parts))
    # Prefer confident, longer pieces.
    pieces.sort(key=lambda p: -(max(p.confidence, 1e-3) * min(p.duration, 8.0)))
    chosen: list[Segment] = []
    for piece in pieces:
        if sum(c.duration for c in chosen) >= CLIPS_TARGET_S:
            break
        chosen.append(piece)
    return sorted(chosen, key=lambda c: c.start)


def export(result: SplitResult, audio: np.ndarray, out_dir: Path, source_name: str) -> Path:
    """Write speaker_N/clip_XX.wav, speaker_N_preview.wav and report.txt."""
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("speaker_*"):  # clear a previous run of the same file
        shutil.rmtree(old) if old.is_dir() else old.unlink()

    def cut(seg: Segment) -> np.ndarray:
        return audio[int(seg.start * SAMPLE_RATE):int(seg.end * SAMPLE_RATE)]

    for spk in result.speakers:
        spk.clips = choose_clips(spk)
        if not spk.clips:
            continue
        for n, clip in enumerate(spk.clips, 1):
            write_wav(out_dir / spk.name / f"clip_{n:02d}.wav", cut(clip), SAMPLE_RATE,
                      title=f"{spk.name} from {source_name}",
                      comment=f"{fmt_time(clip.start)}-{fmt_time(clip.end)} of {source_name}")
        gap = np.zeros(int(0.4 * SAMPLE_RATE), dtype=np.float32)
        parts: list[np.ndarray] = []
        for clip in spk.clips:
            parts += [cut(clip), gap]
        preview = np.concatenate(parts)[:int(PREVIEW_MAX_S * SAMPLE_RATE)]
        peak = float(np.max(np.abs(preview))) or 1.0
        write_wav(out_dir / f"{spk.name}_preview.wav", preview * (0.9 / peak), SAMPLE_RATE,
                  title=f"{spk.name} preview from {source_name}")

    report = out_dir / "report.txt"
    report.write_text(format_report(result, source_name, out_dir), encoding="utf-8")
    result.out_dir = out_dir
    return report


def format_report(result: SplitResult, source_name: str, out_dir: Path) -> str:
    lines = [f"Voices found in {source_name} ({fmt_time(result.duration)} long, "
             f"{fmt_time(result.speech_seconds)} of speech)", ""]
    for spk in result.speakers:
        lines.append(f"{spk.name}: {fmt_time(spk.speech_seconds)} of clear speech in "
                     f"{len(spk.segments)} stretches; {len(spk.clips)} clips saved "
                     f"({spk.clip_seconds:.0f}s)")
        stamps = [f"{fmt_time(s.start)}-{fmt_time(s.end)}" for s in spk.segments]
        for k in range(0, len(stamps), 8):
            lines.append("  " + ", ".join(stamps[k:k + 8]))
        lines.append("")
    if not result.speakers:
        lines += ["No clear voices found.", ""]
    lines.append(f"{fmt_time(result.unclear_seconds)} of speech was skipped (people talking over "
                 "each other, very short bits, or unclear who was talking).")
    if result.speakers:
        lines += ["", "To clone one of them (only with their permission):",
                  f'  python voiceclone.py add "Their Name" "{out_dir / result.speakers[0].name}"']
    return "\n".join(lines) + "\n"


def split_file(path: Path, out_dir: Path, printer_factory: Callable[[], Voiceprinter],
               n_speakers: int | None = None, vad: VadFn | None = None) -> SplitResult:
    """Full pipeline for one file. The voice model is only loaded once speech is found."""
    import librosa

    vad = vad or silero_vad

    audio = load_audio(path, SAMPLE_RATE)
    if audio.size == 0 or not np.any(audio):
        raise VoiceCloneError(f"'{path.name}' has no sound.")
    peak = float(np.max(np.abs(audio)))
    audio = audio * min(0.9 / peak, 10.0)  # even out very quiet recordings
    audio16k = np.ascontiguousarray(
        librosa.resample(audio, orig_sr=SAMPLE_RATE, target_sr=VAD_SR), dtype=np.float32)

    regions = vad(audio16k)
    if not regions:
        raise VoiceCloneError(f"Couldn't hear anyone talking in '{path.name}'.")
    result = diarize(audio16k, regions, printer_factory(), n_speakers)
    export(result, audio, out_dir, path.name)
    return result
