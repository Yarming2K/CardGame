#!/usr/bin/env python3
"""voiceclone - make your friends' voices say things (with their permission).

Uses the open-source XTTS-v2 model (via the `coqui-tts` package) to clone a
voice from a few short recordings and then speak any text you type in it.
Everything runs locally on your own computer; no audio is uploaded anywhere.

Quick start:
    python voiceclone.py add "Sam" sam_clip1.m4a sam_clip2.wav
    python voiceclone.py say "Sam" "Hello! This is my cloned voice."
    python voiceclone.py say "Sam"            # interactive: type lines, get audio
    python voiceclone.py list
    python voiceclone.py remove "Sam"

See README.md for setup and tips on recording good samples.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Protocol, Sequence

import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
DEFAULT_VOICES_DIR = HERE / "voices"
DEFAULT_OUTPUT_DIR = HERE / "output"

# Reference clips are stored as clean mono WAVs at this rate (XTTS resamples
# internally to 22.05 kHz for speaker conditioning).
SAMPLE_RATE = 22050
MIN_CLIP_SECONDS = 2.0
MIN_TOTAL_SECONDS = 6.0
RECOMMENDED_TOTAL_SECONDS = 15.0

# Languages supported by XTTS-v2.
LANGUAGES = {
    "en": "English", "es": "Spanish", "fr": "French", "de": "German",
    "it": "Italian", "pt": "Portuguese", "pl": "Polish", "tr": "Turkish",
    "ru": "Russian", "nl": "Dutch", "cs": "Czech", "ar": "Arabic",
    "zh-cn": "Chinese", "hu": "Hungarian", "ko": "Korean", "ja": "Japanese",
    "hi": "Hindi",
}

CONSENT_NOTICE = """\
Voice cloning should only be done with the person's permission.
Cloned voices must not be used to trick anyone into thinking the real
person said something (e.g. prank calls, scams, fake messages)."""


class VoiceCloneError(Exception):
    """A user-facing error (bad input, missing profile, etc.)."""


# --------------------------------------------------------------------------
# Audio helpers
# --------------------------------------------------------------------------

def _read_audio_any(path: Path) -> tuple[np.ndarray, int]:
    """Read an audio file of (almost) any format as float32 [frames, channels]."""
    try:
        data, sr = sf.read(str(path), dtype="float32", always_2d=True)
        return data, sr
    except Exception as sf_error:  # noqa: BLE001 - fall back to ffmpeg below
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            raise VoiceCloneError(
                f"Couldn't read '{path.name}' ({sf_error}).\n"
                "  WAV, FLAC, OGG and MP3 work out of the box. For phone recordings "
                "(.m4a/.aac/.mp4) install ffmpeg (https://ffmpeg.org/download.html) "
                "or convert the file to WAV first."
            ) from sf_error
        with tempfile.TemporaryDirectory() as tmp:
            wav_path = Path(tmp) / "converted.wav"
            result = subprocess.run(
                [ffmpeg, "-nostdin", "-loglevel", "error", "-y", "-i", str(path),
                 "-ac", "1", "-ar", str(SAMPLE_RATE), str(wav_path)],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                raise VoiceCloneError(
                    f"ffmpeg couldn't convert '{path.name}': {result.stderr.strip()}"
                ) from sf_error
            data, sr = sf.read(str(wav_path), dtype="float32", always_2d=True)
            return data, sr


def clean_clip(path: Path) -> np.ndarray:
    """Load a recording and return a clean mono float32 clip at SAMPLE_RATE.

    Mixes to mono, resamples, trims leading/trailing silence and normalises the
    volume so quiet phone recordings work as well as loud ones.
    """
    import librosa  # imported lazily: it is slow to import

    data, sr = _read_audio_any(path)
    audio = data.mean(axis=1)
    if sr != SAMPLE_RATE:
        audio = librosa.resample(audio, orig_sr=sr, target_sr=SAMPLE_RATE)
    if audio.size == 0 or not np.any(audio):
        raise VoiceCloneError(f"'{path.name}' is empty or completely silent.")
    audio, _ = librosa.effects.trim(audio, top_db=35)
    peak = float(np.max(np.abs(audio)))
    if peak > 0:
        audio = audio * (0.9 / peak)
    return audio.astype(np.float32)


def write_wav(path: Path, audio: np.ndarray, sample_rate: int,
              title: str = "", comment: str = "") -> None:
    """Write a 16-bit mono WAV, optionally tagging it with metadata."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with sf.SoundFile(str(path), "w", samplerate=sample_rate, channels=1,
                      subtype="PCM_16", format="WAV") as f:
        if title:
            f.title = title
        if comment:
            f.comment = comment
        f.software = "voiceclone.py (XTTS-v2)"
        f.write(np.clip(audio, -1.0, 1.0))


# --------------------------------------------------------------------------
# Voice profiles
# --------------------------------------------------------------------------

def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    if not slug:
        raise VoiceCloneError(f"'{name}' isn't a usable name - use some letters or numbers.")
    return slug


@dataclass
class Profile:
    name: str
    folder: Path
    language: str
    samples: list[str]
    consent: dict
    created: str

    @property
    def sample_paths(self) -> list[Path]:
        return [self.folder / "samples" / s for s in self.samples]

    def total_seconds(self) -> float:
        return sum(sf.info(str(p)).duration for p in self.sample_paths if p.exists())

    def save(self) -> None:
        data = {
            "name": self.name,
            "language": self.language,
            "samples": self.samples,
            "consent": self.consent,
            "created": self.created,
        }
        (self.folder / "profile.json").write_text(json.dumps(data, indent=2), encoding="utf-8")

    @classmethod
    def load(cls, folder: Path) -> "Profile":
        data = json.loads((folder / "profile.json").read_text(encoding="utf-8"))
        return cls(
            name=data["name"],
            folder=folder,
            language=data.get("language", "en"),
            samples=list(data.get("samples", [])),
            consent=data.get("consent", {}),
            created=data.get("created", ""),
        )


class VoiceLibrary:
    """Stores one folder per friend under `voices/`."""

    def __init__(self, root: Path = DEFAULT_VOICES_DIR):
        self.root = Path(root)

    def folder_for(self, name: str) -> Path:
        return self.root / slugify(name)

    def exists(self, name: str) -> bool:
        return (self.folder_for(name) / "profile.json").exists()

    def get(self, name: str) -> Profile:
        folder = self.folder_for(name)
        if not (folder / "profile.json").exists():
            known = ", ".join(p.name for p in self.all()) or "none yet"
            raise VoiceCloneError(f"No voice called '{name}'. Saved voices: {known}.")
        return Profile.load(folder)

    def all(self) -> list[Profile]:
        if not self.root.exists():
            return []
        return [Profile.load(p.parent) for p in sorted(self.root.glob("*/profile.json"))]

    def add(self, name: str, clips: Sequence[Path], consent: dict,
            language: str = "en", consent_recording: Path | None = None) -> tuple[Profile, list[str]]:
        """Create a profile (or add clips to an existing one).

        Returns the profile and a list of warnings to show the user.
        """
        if language not in LANGUAGES:
            raise VoiceCloneError(f"Unsupported language '{language}'. Choose from: {', '.join(LANGUAGES)}")
        if not clips:
            raise VoiceCloneError("Give at least one recording of their voice.")
        for clip in [*clips, *([consent_recording] if consent_recording else [])]:
            if not Path(clip).is_file():
                raise VoiceCloneError(f"File not found: {clip}")

        # Process everything before touching disk so a bad file doesn't leave
        # a half-created profile behind.
        cleaned: list[np.ndarray] = []
        warnings: list[str] = []
        for clip in clips:
            audio = clean_clip(Path(clip))
            seconds = len(audio) / SAMPLE_RATE
            if seconds < MIN_CLIP_SECONDS:
                warnings.append(f"Skipped '{Path(clip).name}': only {seconds:.1f}s of speech.")
                continue
            cleaned.append(audio)
        if not cleaned:
            raise VoiceCloneError(
                f"None of the recordings had at least {MIN_CLIP_SECONDS:.0f}s of speech.")

        folder = self.folder_for(name)
        if self.exists(name):
            profile = Profile.load(folder)
            profile.consent = consent or profile.consent
            profile.language = language
        else:
            profile = Profile(
                name=name.strip(), folder=folder, language=language, samples=[],
                consent=consent, created=_dt.datetime.now().isoformat(timespec="seconds"),
            )
        samples_dir = folder / "samples"
        samples_dir.mkdir(parents=True, exist_ok=True)

        next_index = len(profile.samples) + 1
        for audio in cleaned:
            filename = f"sample_{next_index:02d}.wav"
            while (samples_dir / filename).exists():
                next_index += 1
                filename = f"sample_{next_index:02d}.wav"
            write_wav(samples_dir / filename, audio, SAMPLE_RATE)
            profile.samples.append(filename)
            next_index += 1

        if consent_recording is not None:
            dest = folder / f"consent{Path(consent_recording).suffix.lower()}"
            shutil.copyfile(consent_recording, dest)
            profile.consent["recording"] = dest.name

        profile.save()

        total = profile.total_seconds()
        if total < MIN_TOTAL_SECONDS:
            warnings.append(
                f"Only {total:.0f}s of audio so far - add more (aim for "
                f"{RECOMMENDED_TOTAL_SECONDS:.0f}-30s) or the voice won't sound much like them.")
        elif total < RECOMMENDED_TOTAL_SECONDS:
            warnings.append(
                f"{total:.0f}s of audio. That works, but {RECOMMENDED_TOTAL_SECONDS:.0f}-30s "
                "usually sounds noticeably better.")
        return profile, warnings

    def remove(self, name: str) -> Profile:
        profile = self.get(name)
        shutil.rmtree(profile.folder)
        return profile


# --------------------------------------------------------------------------
# Speech synthesis
# --------------------------------------------------------------------------

class Engine(Protocol):
    sample_rate: int

    def synthesize(self, text: str, reference_wavs: Sequence[Path], language: str) -> np.ndarray: ...


class XTTSEngine:
    """Wraps Coqui XTTS-v2. The model (~1.9 GB) downloads on first use."""

    MODEL = "tts_models/multilingual/multi-dataset/xtts_v2"

    def __init__(self, device: str | None = None):
        try:
            import torch
            from TTS.api import TTS
        except ImportError as e:
            raise VoiceCloneError(
                f"The speech engine isn't installed ({e}).\n"
                "  Run:  pip install -r requirements.txt   (see README.md)"
            ) from e
        if device is None:
            device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"Loading voice model on {device.upper()} (first run downloads ~1.9 GB)...",
              file=sys.stderr)
        self.tts = TTS(self.MODEL, progress_bar=True).to(device)
        self.sample_rate = int(self.tts.synthesizer.output_sample_rate)

    def synthesize(self, text: str, reference_wavs: Sequence[Path], language: str) -> np.ndarray:
        wav = self.tts.tts(
            text=text,
            speaker_wav=[str(p) for p in reference_wavs],
            language=language,
            split_sentences=True,
        )
        return np.asarray(wav, dtype=np.float32)


def speak(engine: Engine, profile: Profile, text: str, out_path: Path,
          language: str | None = None) -> Path:
    """Generate `text` in `profile`'s voice and save it as a WAV file."""
    text = text.strip()
    if not text:
        raise VoiceCloneError("Nothing to say - the text is empty.")
    refs = [p for p in profile.sample_paths if p.exists()]
    if not refs:
        raise VoiceCloneError(
            f"'{profile.name}' has no recordings left. Add some with: "
            f'python voiceclone.py add "{profile.name}" clip.wav')
    lang = language or profile.language
    if lang not in LANGUAGES:
        raise VoiceCloneError(f"Unsupported language '{lang}'. Choose from: {', '.join(LANGUAGES)}")
    audio = engine.synthesize(text, refs, lang)
    write_wav(
        out_path, audio, engine.sample_rate,
        title=f"AI voice clone of {profile.name}",
        comment=f"AI-GENERATED speech imitating {profile.name}'s voice. Not a real recording. Text: {text[:200]}",
    )
    return out_path


def default_output_path(profile: Profile, output_dir: Path = DEFAULT_OUTPUT_DIR) -> Path:
    stamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    path = output_dir / f"{profile.folder.name}_{stamp}.wav"
    n = 2
    while path.exists():
        path = output_dir / f"{profile.folder.name}_{stamp}_{n}.wav"
        n += 1
    return path


def open_file(path: Path) -> None:
    """Open a file in the system's default app (e.g. play the WAV)."""
    try:
        if sys.platform.startswith("win"):
            os.startfile(str(path))  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.Popen(["open", str(path)])
        else:
            subprocess.Popen(["xdg-open", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:  # noqa: BLE001 - playing is a nice-to-have
        print(f"(Couldn't open the file automatically: {e})", file=sys.stderr)


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------

def confirm_consent(name: str, ask: Callable[[str], str] = input) -> dict:
    """Ask the user to confirm the friend agreed. Returns a consent record."""
    print(CONSENT_NOTICE)
    print()
    answer = ask(f"Has {name} agreed to have their voice cloned? Type 'yes' to confirm: ")
    if answer.strip().lower() not in {"y", "yes"}:
        raise VoiceCloneError(f"Not adding {name}'s voice without their permission.")
    return {
        "confirmed": True,
        "method": "interactive",
        "date": _dt.date.today().isoformat(),
    }


def cmd_add(args: argparse.Namespace, library: VoiceLibrary) -> int:
    if args.consent:
        consent = {"confirmed": True, "method": "--consent flag", "date": _dt.date.today().isoformat()}
    elif sys.stdin.isatty():
        consent = confirm_consent(args.name)
    else:
        raise VoiceCloneError(
            "Confirm that your friend agreed by passing --consent (or run interactively).")
    if args.note:
        consent["note"] = args.note

    adding_more = library.exists(args.name)
    print(f"Processing {len(args.clips)} recording(s)...")
    profile, warnings = library.add(
        args.name, [Path(c) for c in args.clips], consent,
        language=args.language, consent_recording=Path(args.consent_recording) if args.consent_recording else None,
    )
    for w in warnings:
        print(f"  ! {w}")
    verb = "Updated" if adding_more else "Saved"
    print(f"{verb} voice '{profile.name}': {len(profile.samples)} clip(s), "
          f"{profile.total_seconds():.0f}s total, language {LANGUAGES[profile.language]}.")
    print(f'Try it:  python voiceclone.py say "{profile.name}" "Hey, it\'s me!"')
    return 0


def cmd_say(args: argparse.Namespace, library: VoiceLibrary,
            engine_factory: Callable[[str | None], Engine] = XTTSEngine) -> int:
    profile = library.get(args.name)
    engine = engine_factory(args.device)

    def one(text: str, out: Path | None) -> None:
        path = speak(engine, profile, text, out or default_output_path(profile, Path(args.output_dir)),
                     language=args.language)
        print(f"Saved: {path}")
        if args.play:
            open_file(path)

    if args.text:
        one(" ".join(args.text), Path(args.output) if args.output else None)
        return 0

    # Interactive mode: keep the model loaded and speak each line typed.
    print(f"Speaking as {profile.name}. Type a line and press Enter (empty line or Ctrl+C to quit).")
    while True:
        try:
            line = input(f"{profile.name}> ")
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line.strip():
            break
        try:
            one(line, None)
        except VoiceCloneError as e:
            print(f"Error: {e}", file=sys.stderr)
    return 0


def cmd_list(args: argparse.Namespace, library: VoiceLibrary) -> int:
    profiles = library.all()
    if not profiles:
        print('No voices saved yet. Add one with: python voiceclone.py add "Name" clip1.wav clip2.wav')
        return 0
    for p in profiles:
        print(f"{p.name:<20} {len(p.samples):>2} clip(s)  {p.total_seconds():5.0f}s  "
              f"{LANGUAGES.get(p.language, p.language):<10} added {p.created[:10]}")
    return 0


def cmd_remove(args: argparse.Namespace, library: VoiceLibrary) -> int:
    profile = library.get(args.name)
    if not args.yes:
        if not sys.stdin.isatty():
            raise VoiceCloneError("Pass --yes to confirm deleting the voice.")
        answer = input(f"Delete '{profile.name}' and all their recordings? [y/N] ")
        if answer.strip().lower() not in {"y", "yes"}:
            print("Cancelled.")
            return 1
    library.remove(args.name)
    print(f"Deleted voice '{profile.name}' and its recordings.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="voiceclone",
        description="Clone your friends' voices (with permission) and make them say things.",
    )
    parser.add_argument("--voices-dir", default=str(DEFAULT_VOICES_DIR),
                        help="where voice profiles are stored (default: ./voices)")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("add", help="add a friend's voice from recordings (or add more clips)")
    p.add_argument("name", help='your friend\'s name, e.g. "Sam"')
    p.add_argument("clips", nargs="+", help="audio files of them talking (wav, mp3, m4a, ...)")
    p.add_argument("--language", default="en", choices=sorted(LANGUAGES), help="language they speak (default: en)")
    p.add_argument("--consent", action="store_true", help="confirm they agreed to have their voice cloned")
    p.add_argument("--consent-recording", metavar="FILE",
                   help="optional: a clip of them saying they agree, kept with their profile")
    p.add_argument("--note", help='optional note saved with the consent record, e.g. "asked in group chat"')

    p = sub.add_parser("say", help="make a saved voice say something")
    p.add_argument("name", help="whose voice to use")
    p.add_argument("text", nargs="*", help="what to say (leave out for interactive mode)")
    p.add_argument("-o", "--output", help="output WAV path (default: output/<name>_<time>.wav)")
    p.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="folder for generated audio")
    p.add_argument("--language", choices=sorted(LANGUAGES), help="override the voice's language")
    p.add_argument("--play", action="store_true", help="open the result in your audio player")
    p.add_argument("--device", choices=["cpu", "cuda"], help="force CPU or NVIDIA GPU (default: auto)")

    sub.add_parser("list", help="list saved voices")

    p = sub.add_parser("remove", help="delete a saved voice and its recordings")
    p.add_argument("name")
    p.add_argument("--yes", action="store_true", help="don't ask for confirmation")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    library = VoiceLibrary(Path(args.voices_dir))
    commands = {"add": cmd_add, "say": cmd_say, "list": cmd_list, "remove": cmd_remove}
    try:
        return commands[args.command](args, library)
    except VoiceCloneError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
