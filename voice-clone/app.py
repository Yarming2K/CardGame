"""Voice Clone app: a friendly window for voiceclone.py, in your web browser.

Start it with "Start Voice Clone.bat" (Windows) or `python app.py`. It only
listens on this computer (127.0.0.1): nothing is put on the internet.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import functools
import os
import threading
from pathlib import Path

os.environ.setdefault("GRADIO_ANALYTICS_ENABLED", "False")  # no usage stats sent anywhere

import gradio as gr  # noqa: E402

import voice_split  # noqa: E402
import voiceclone as vc  # noqa: E402

LIBRARY = vc.VoiceLibrary(vc.DEFAULT_VOICES_DIR)
OUTPUT_DIR = vc.DEFAULT_OUTPUT_DIR
LICENCE_FLAG = vc.HERE / ".model_licence_agreed"
LICENCE_URL = "https://tts-hub.github.io/cpml"
ENGINE_FACTORY = vc.XTTSEngine
MAX_SLOTS = 8
SAME_AS_VOICE = "same"
LANGUAGE_CHOICES = [(name, code) for code, name in vc.LANGUAGES.items()]

READ_ALOUD = (
    "If they're recording right now, they can read this out loud:\n\n"
    "> *\"Last weekend we tried that new pizza place by the station. The line was "
    "long, but honestly, it was worth it. Have you been there yet? Next time we "
    "should all go together - and this time I'm picking the toppings!\"*"
)

_engine = None
_model_lock = threading.Lock()  # one model, used by one task at a time


def get_engine():
    global _engine
    if _engine is None:
        _engine = ENGINE_FACTORY()
    return _engine


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def _ok(msg: str) -> str:
    return f"✅ {msg}"


def _err(msg: str) -> str:
    return f"⚠️ {msg}"


def licence_accepted() -> bool:
    return LICENCE_FLAG.exists() or os.environ.get("COQUI_TOS_AGREED") == "1"


def _require_licence() -> None:
    if not licence_accepted():
        raise vc.VoiceCloneError("First accept the voice model's licence at the top of the page.")


def _consent_record() -> dict:
    return {"confirmed": True, "method": "app checkbox", "date": _dt.date.today().isoformat()}


def _voice_names() -> list[str]:
    return [p.name for p in LIBRARY.all()]


def _voice_dropdowns(selected: str | None = None):
    names = _voice_names()
    value = selected if selected in names else (names[0] if names else None)
    return gr.Dropdown(choices=names, value=value), gr.Dropdown(choices=names, value=value)


def voices_markdown() -> str:
    profiles = LIBRARY.all()
    if not profiles:
        return "_No voices yet. Add one in **Add a voice** or **From a video**._"
    rows = ["| Voice | Clips | Audio | Language | Added |", "|---|---|---|---|---|"]
    for p in profiles:
        name = p.name.replace("|", "\\|")
        rows.append(f"| {name} | {len(p.samples)} | {p.total_seconds():.0f}s | "
                    f"{vc.LANGUAGES.get(p.language, p.language)} | {p.created[:10]} |")
    return "\n".join(rows)


def _added_message(profile: vc.Profile, existed: bool, warnings: list[str]) -> str:
    msg = _ok(f"{'Updated' if existed else 'Saved'} **{profile.name}**: {len(profile.samples)} clips, "
              f"{profile.total_seconds():.0f}s of audio. Try them in the **Speak** tab.")
    return msg + "".join(f"\n- {w}" for w in warnings)


# --------------------------------------------------------------------------
# Actions (each returns values for the UI; errors become friendly messages)
# --------------------------------------------------------------------------

def handle_accept_licence(agree: bool):
    if not agree:
        return gr.Group(visible=True), _err("Tick the box to accept the licence.")
    LICENCE_FLAG.write_text(f"Accepted in the app on {_dt.date.today().isoformat()}\n", encoding="utf-8")
    os.environ["COQUI_TOS_AGREED"] = "1"
    return gr.Group(visible=False), _ok("Licence accepted. You're all set!")


def handle_add(name, files, mic, language, consent):
    name = (name or "").strip()
    selected = None
    try:
        if not name:
            raise vc.VoiceCloneError("Type their name first.")
        clips = [Path(f) for f in (files or [])] + ([Path(mic)] if mic else [])
        if not clips:
            raise vc.VoiceCloneError("Upload recordings of them talking, or record them with the microphone.")
        if not consent:
            raise vc.VoiceCloneError(f"Tick the box to confirm {name} agreed to have their voice cloned.")
        existed = LIBRARY.exists(name)
        profile, warnings = LIBRARY.add(name, clips, _consent_record(), language=language or "en")
        status, selected = _added_message(profile, existed, warnings), profile.name
    except vc.VoiceCloneError as e:
        status = _err(str(e))
    return (status, *_voice_dropdowns(selected), voices_markdown())


def handle_speak(name, text, language):
    try:
        if not name:
            raise vc.VoiceCloneError("Pick a voice first (or add one in **Add a voice**).")
        if not (text or "").strip():
            raise vc.VoiceCloneError("Type what they should say.")
        _require_licence()
        profile = LIBRARY.get(name)
        lang = None if language in (None, "", SAME_AS_VOICE) else language
        with _model_lock:
            path = vc.speak(get_engine(), profile, text, vc.default_output_path(profile, OUTPUT_DIR), language=lang)
        return str(path), _ok(f"Saved as `{path.name}` in the output folder.")
    except vc.VoiceCloneError as e:
        return None, _err(str(e))


def _slot_values(spk=None, out_dir: Path | None = None):
    """(group, title, preview, name, consent, status) for one speaker card."""
    if spk is None:
        return gr.Group(visible=False), "", None, "", False, ""
    ft = voice_split.fmt_time
    info = f"{ft(spk.speech_seconds)} of speech · {len(spk.clips)} clips ({spk.clip_seconds:.0f}s)"
    if spk.clip_seconds < vc.MIN_TOTAL_SECONDS:
        info += "  \n_Too little clear speech to clone well._"
    elif spk.clip_seconds < vc.RECOMMENDED_TOTAL_SECONDS:
        info += "  \n_Not much audio: may be someone who barely spoke, or people talking at once. Listen first._"
    title = f"### {spk.name.replace('_', ' ').capitalize()}\n{info}"
    preview = str(out_dir / f"{spk.name}_preview.wav") if spk.clips and out_dir else None
    return gr.Group(visible=True), title, preview, "", False, ""


def handle_split(file, how_many):
    empty = [v for _ in range(MAX_SLOTS) for v in _slot_values()]
    try:
        if not file:
            raise vc.VoiceCloneError("Choose a video or recording first.")
        _require_licence()
        src = Path(file)
        n = None if how_many in (None, "", "auto") else int(how_many)
        out_dir = OUTPUT_DIR / "split" / vc.slugify(src.stem)
        with _model_lock:
            result = voice_split.split_file(src, out_dir, get_engine, n_speakers=n)
        if not result.speakers:
            raise vc.VoiceCloneError("Couldn't find any clear voices (too little speech, or people talking over each other).")
    except vc.VoiceCloneError as e:
        return ({}, _err(str(e)), *empty)

    ft = voice_split.fmt_time
    count = len(result.speakers)
    status = _ok(f"Found **{count} voice{'s' if count != 1 else ''}** in {src.name} "
                 f"({ft(result.duration)} long). Listen to each one, then name and add the people who agreed.")
    if result.unclear_seconds >= 1:
        status += f"\n\nSkipped {ft(result.unclear_seconds)} where voices overlapped or were unclear."
    if count > MAX_SLOTS:
        status += f"\n\nShowing the {MAX_SLOTS} people who talk most; the rest are in `{out_dir}`."
    if n is None and count > 1:
        status += "\n\nIf someone appears twice, or two people got merged, pick the right number above and try again."
    slots = [v for i in range(MAX_SLOTS)
             for v in _slot_values(result.speakers[i] if i < count else None, out_dir)]
    state = {"out_dir": str(out_dir), "speakers": [s.name for s in result.speakers[:MAX_SLOTS]]}
    return (state, status, *slots)


def handle_add_from_split(index, state, name, consent, language):
    name = (name or "").strip()
    selected = None
    try:
        speakers = (state or {}).get("speakers", [])
        if index >= len(speakers):
            raise vc.VoiceCloneError("Find the voices in a video first.")
        if not name:
            raise vc.VoiceCloneError("Type who this is first.")
        if not consent:
            raise vc.VoiceCloneError(f"Tick the box to confirm {name} agreed to have their voice cloned.")
        folder = Path(state["out_dir"]) / speakers[index]
        if not folder.is_dir():
            raise vc.VoiceCloneError("There isn't enough clear speech from this person to add them.")
        existed = LIBRARY.exists(name)
        profile, warnings = LIBRARY.add(name, vc.expand_clip_args([str(folder)]), _consent_record(),
                                        language=language or "en")
        status, selected = _added_message(profile, existed, warnings), profile.name
    except vc.VoiceCloneError as e:
        status = _err(str(e))
    return (status, *_voice_dropdowns(selected), voices_markdown())


def handle_delete(name, confirm):
    try:
        if not name:
            raise vc.VoiceCloneError("Pick a voice to delete.")
        if not confirm:
            raise vc.VoiceCloneError(f"Tick the box to confirm deleting {name}.")
        LIBRARY.remove(name)
        status = _ok(f"Deleted **{name}** and their recordings.")
    except vc.VoiceCloneError as e:
        status = _err(str(e))
    return (status, *_voice_dropdowns(), voices_markdown(), False)


def handle_open_output():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    vc.open_file(OUTPUT_DIR)
    return ""


def handle_load():
    return (*_voice_dropdowns(), voices_markdown(), gr.Group(visible=not licence_accepted()))


# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------

CSS = """
.gradio-container { max-width: 900px !important; margin: auto; }
.speaker-card { padding: 12px; }
footer { display: none !important; }
"""

THEME = gr.themes.Soft(primary_hue="violet", font=["system-ui", "Segoe UI", "sans-serif"],
                       font_mono=["ui-monospace", "Consolas", "monospace"])


def build_app() -> gr.Blocks:
    with gr.Blocks(title="Voice Clone", analytics_enabled=False) as app:
        gr.Markdown("# 🎙️ Voice Clone\nMake your friends' voices say things, **only with their permission**. "
                    "Everything stays on this computer.")

        with gr.Group(visible=not licence_accepted(), elem_id="licence") as licence_box:
            gr.Markdown(f"**One-time step:** the voice model (XTTS-v2 by Coqui) is free for **non-commercial** "
                        f"use under the [Coqui Public Model License]({LICENCE_URL}). The first time you make a "
                        "voice speak it downloads (~1.9 GB, a few minutes).")
            licence_cb = gr.Checkbox(label="I agree to use the model for non-commercial purposes only",
                                     elem_id="licence-agree")
            licence_btn = gr.Button("Accept", variant="primary", elem_id="licence-accept")
        licence_status = gr.Markdown(elem_id="licence-status")  # outside the box, so it stays visible

        with gr.Tabs():
            # ---- Speak --------------------------------------------------
            with gr.Tab("🗣️ Speak", id="speak"):
                with gr.Row():
                    speak_voice = gr.Dropdown(label="Voice", choices=[], scale=2, elem_id="speak-voice")
                    speak_lang = gr.Dropdown(label="Language",
                                             choices=[("Same as the voice", SAME_AS_VOICE)] + LANGUAGE_CHOICES,
                                             value=SAME_AS_VOICE, scale=1)
                speak_text = gr.Textbox(label="What should they say?", lines=3, elem_id="speak-text",
                                        placeholder="Did you finish the card game yet?")
                speak_btn = gr.Button("Speak", variant="primary", elem_id="speak-btn")
                speak_audio = gr.Audio(label="Result", type="filepath", interactive=False, autoplay=True,
                                       buttons=["download"], elem_id="speak-audio")
                speak_status = gr.Markdown(elem_id="speak-status")
                gr.Markdown("_The first time takes a few minutes while the voice model loads. "
                            "After that each line takes a few seconds._")
                open_btn = gr.Button("📂 Open the folder with everything I've made", size="sm")

            # ---- Add a voice --------------------------------------------
            with gr.Tab("➕ Add a voice", id="add"):
                add_name = gr.Textbox(label="Their name", placeholder="Sam", elem_id="add-name")
                add_files = gr.File(label="Recordings of them talking (15-30 seconds in total is ideal)",
                                    file_count="multiple", file_types=["audio", "video"], type="filepath",
                                    elem_id="add-files")
                add_mic = gr.Audio(label="...or record them right now", sources=["microphone"],
                                   type="filepath", buttons=["download"], elem_id="add-mic")
                with gr.Accordion("Something to read out loud", open=False):
                    gr.Markdown(READ_ALOUD)
                add_lang = gr.Dropdown(label="Language they speak", choices=LANGUAGE_CHOICES, value="en")
                add_consent = gr.Checkbox(label="They've agreed to have their voice cloned", elem_id="add-consent")
                add_btn = gr.Button("Add voice", variant="primary", elem_id="add-btn")
                add_status = gr.Markdown(elem_id="add-status")
                gr.Markdown("**Tips:** one person talking, quiet room, no music. Normal chatting works best. "
                            "Adding more clips to the same name improves the voice.")

            # ---- From a video -------------------------------------------
            with gr.Tab("🎬 From a video", id="split"):
                gr.Markdown("Upload a video or recording of people talking. The app finds each voice and "
                            "saves clean clips of them, skipping bits where people talk over each other.")
                split_file = gr.File(label="Video or recording", file_count="single",
                                     file_types=["video", "audio"], type="filepath", elem_id="split-file")
                with gr.Row():
                    split_count = gr.Dropdown(label="How many people talk?",
                                              choices=[("Work it out", "auto")] + [(str(i), str(i)) for i in range(1, 9)],
                                              value="auto")
                    split_lang = gr.Dropdown(label="Language they speak", choices=LANGUAGE_CHOICES, value="en")
                split_btn = gr.Button("Find voices", variant="primary", elem_id="split-btn")
                split_status = gr.Markdown(elem_id="split-status")
                split_state = gr.State({})
                slots = []
                for i in range(MAX_SLOTS):
                    with gr.Group(visible=False, elem_classes="speaker-card", elem_id=f"slot-{i}") as group:
                        title = gr.Markdown()
                        preview = gr.Audio(label="Listen", type="filepath", interactive=False,
                                           buttons=["download"], elem_id=f"slot-{i}-audio")
                        with gr.Row():
                            slot_name = gr.Textbox(label="Who is this?", placeholder="Name", scale=2,
                                                   elem_id=f"slot-{i}-name")
                            slot_consent = gr.Checkbox(label="They agreed to be cloned", scale=1,
                                                       elem_id=f"slot-{i}-consent")
                            slot_btn = gr.Button("Add as a voice", scale=1, elem_id=f"slot-{i}-add")
                        slot_status = gr.Markdown(elem_id=f"slot-{i}-status")
                    slots.append((group, title, preview, slot_name, slot_consent, slot_status, slot_btn))

            # ---- My voices ----------------------------------------------
            with gr.Tab("👥 My voices", id="voices"):
                voices_md = gr.Markdown(voices_markdown(), elem_id="voices-table")
                with gr.Row():
                    manage_voice = gr.Dropdown(label="Delete a voice", choices=[], scale=2)
                    manage_confirm = gr.Checkbox(label="Yes, delete it and its recordings", scale=1)
                delete_btn = gr.Button("Delete", variant="stop")
                manage_status = gr.Markdown()

        # ---- Wiring -----------------------------------------------------
        voice_outputs = [speak_voice, manage_voice, voices_md]
        licence_btn.click(handle_accept_licence, [licence_cb], [licence_box, licence_status])
        speak_btn.click(handle_speak, [speak_voice, speak_text, speak_lang], [speak_audio, speak_status])
        speak_text.submit(handle_speak, [speak_voice, speak_text, speak_lang], [speak_audio, speak_status])
        open_btn.click(handle_open_output, None, [speak_status])
        add_btn.click(handle_add, [add_name, add_files, add_mic, add_lang, add_consent],
                      [add_status, *voice_outputs])
        slot_outputs = [c for (group, title, preview, name, consent, status, _btn) in slots
                        for c in (group, title, preview, name, consent, status)]
        split_btn.click(handle_split, [split_file, split_count], [split_state, split_status, *slot_outputs])
        for i, (_g, _t, _p, slot_name, slot_consent, slot_status, slot_btn) in enumerate(slots):
            slot_btn.click(functools.partial(handle_add_from_split, i),
                           [split_state, slot_name, slot_consent, split_lang], [slot_status, *voice_outputs])
        delete_btn.click(handle_delete, [manage_voice, manage_confirm],
                         [manage_status, *voice_outputs, manage_confirm])
        app.load(handle_load, None, [*voice_outputs[:2], voices_md, licence_box])
    return app


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description="Open the Voice Clone app in your browser.")
    parser.add_argument("--port", type=int, help="port to use (default: the first free one from 7860)")
    parser.add_argument("--no-browser", action="store_true", help="don't open a browser tab")
    args = parser.parse_args(argv)
    if LICENCE_FLAG.exists():
        os.environ["COQUI_TOS_AGREED"] = "1"
    for folder in (OUTPUT_DIR, LIBRARY.root):
        folder.mkdir(parents=True, exist_ok=True)
    print("  Starting Voice Clone...")
    app = build_app().queue(default_concurrency_limit=1)
    _, url, _ = app.launch(
        server_name="127.0.0.1",  # this computer only
        server_port=args.port,
        inbrowser=not args.no_browser,
        share=False,
        quiet=True,
        prevent_thread_lock=True,
        show_error=True,
        footer_links=[],
        allowed_paths=[str(OUTPUT_DIR.resolve()), str(LIBRARY.root.resolve())],
        theme=THEME,
        css=CSS,
    )
    print(f"  Voice Clone is running at {url}")
    print("  (If your browser didn't open by itself, open that address.)")
    app.block_thread()


if __name__ == "__main__":
    main()
