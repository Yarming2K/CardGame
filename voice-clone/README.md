# Voice Clone

Clone your friends' voices from a few short recordings, then type anything and
hear it in their voice. It uses the open-source **XTTS-v2** model and runs
entirely on your own computer. Nothing gets uploaded.

> **Ask first.** Only clone someone's voice if they've said yes, and don't use
> it to make people think your friend really said something (prank calls,
> fake voice notes, getting past voice checks, and so on). That can get them
> into real trouble, and in many places it's illegal. The program asks you to
> confirm consent when you add a voice, and it tags every file it makes as
> AI-generated in the WAV metadata.

## 1. Install (one time)

You need **Python 3.10 to 3.13** ([python.org](https://www.python.org/downloads/),
and tick "Add Python to PATH" on Windows) and about 5 GB of free disk space.

Open a terminal in this `voice-clone` folder.

On Windows:

```bat
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

On macOS or Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

The first time you make a voice speak, the model (~1.9 GB) downloads
automatically. It asks you to accept Coqui's **non-commercial** licence; type
`y`. The model is free for personal use, but you can't sell what you make with
it.

**Optional:**
- **NVIDIA GPU:** before the step above, install a 2.8 CUDA build of PyTorch from
  [pytorch.org](https://pytorch.org/get-started/locally/). Generation becomes
  roughly 10× faster. On CPU, expect about 5 to 20 seconds per sentence.
- **iPhone/Android voice memos (`.m4a`):** install [FFmpeg](https://ffmpeg.org/download.html)
  so the program can read them. WAV, MP3, FLAC and OGG work without it.

## 2. Record your friend

Ask them for **2 or 3 clips of normal talking, 15 to 30 seconds in total**:

- one person talking, in a quiet room, with no music or TV behind them
- natural speech: reading a paragraph out loud or chatting about their day both work
- a phone voice memo held about 20 cm (8 in) from their mouth is fine
- more variety (calm, excited, a question) gives a more natural clone

## 3. Use it

```bash
# Add a voice (it asks you to confirm they agreed)
python voiceclone.py add "Sam" sam1.m4a sam2.m4a

# Make them say something; it saves a WAV in output/ and --play opens it
python voiceclone.py say "Sam" "Did you finish the card game yet?" --play

# Interactive mode: loads the model once, then speaks each line you type
python voiceclone.py say "Sam"

# Other commands
python voiceclone.py add "Sam" sam3.wav         # add more clips to improve the voice
python voiceclone.py list                       # show saved voices
python voiceclone.py remove "Sam"               # delete their voice and recordings
python voiceclone.py say "Sam" "Hola" --language es
python voiceclone.py say "Sam" "hi" -o hi.wav   # choose the output file
```

Supported languages: English, Spanish, French, German, Italian, Portuguese,
Polish, Turkish, Russian, Dutch, Czech, Arabic, Chinese (`zh-cn`), Hungarian,
Korean, Japanese and Hindi. A voice can speak languages its owner doesn't.

Optional extras when adding a voice:
- `--consent-recording yes.m4a` keeps a clip of them saying they agree alongside their profile
- `--note "asked in the group chat"` saves a note with the consent record
- `--consent` skips the yes/no prompt (useful for scripts)

## Tips

- **Doesn't sound like them?** Add more (and cleaner) clips. Background noise
  and music cause most bad results.
- **Weird pauses or mumbling?** Use full sentences with punctuation. Very short
  inputs like "ok" can come out strange.
- Each friend's data lives in `voices/<name>/`. The `.gitignore` here stops it
  (and everything in `output/`) from being committed to GitHub.

## Running the tests

The tests use a stand-in engine, so they don't need the big model:

```bash
pip install pytest
python -m pytest tests
```
