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

## The easy way: the app (Windows)

1. Install **Python 3.13** from [python.org](https://www.python.org/downloads/):
   the 3.13.x "Windows installer (64-bit)", **not** 3.14 or newer. Tick
   "Add python.exe to PATH".
2. Install **FFmpeg** (for videos and phone recordings): open PowerShell and run
   `winget install Gyan.FFmpeg`.
3. Put this `voice-clone` folder somewhere with a short path, like
   `C:\Users\<you>\voice-clone` (not deep inside Downloads).
4. Double-click **`Install.bat`**. It takes 5-10 minutes the first time.
5. Double-click **`Start Voice Clone.bat`**. The app opens in your browser.
   Keep the black window open while you use it; close it to quit.

Tip: right-click `Start Voice Clone.bat` and choose **Send to > Desktop
(create shortcut)** for a desktop icon.

In the app:
- **Speak:** pick a voice, type what they should say, press Speak.
- **Add a voice:** upload recordings of a friend, or record them with your microphone.
- **From a video:** upload a video and the app finds each person's voice; listen,
  type their name and add them.
- **My voices:** see and delete saved voices.

The app only runs on your computer (`127.0.0.1`); nobody else can open it.
On macOS/Linux, do the install below, then run `python app.py`.

Everything below is for using it from the command line instead.

## 1. Install (one time)

You need **Python 3.10 to 3.13** ([python.org](https://www.python.org/downloads/),
and tick "Add Python to PATH" on Windows) and about 5 GB of free disk space.
Python 3.14 and newer won't work yet: PyTorch 2.8 has no builds for them.

**On Windows, put this folder somewhere with a short path**, like
`C:\Users\<you>\voice-clone`. PyTorch has very long file names, and installing
fails with "No such file or directory" / "Long Path support" if the folder's
path is longer than about 115 characters (e.g. deep inside `Downloads`).

Open a terminal in this `voice-clone` folder.

On Windows:

```bat
py -3.13 -m venv .venv
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

## 4. Get voices out of a video or group recording

Got a video of everyone hanging out? `split` works out how many people are
talking, then saves clean clips of each one (ready to clone) and skips the bits
where people talk over each other.

```bash
python voiceclone.py split "Game Night.mp4"
```

```
Found 3 voices in Game Night.mp4 (1:29 long, 1:02 of speech):
  speaker_1     0:26 of speech   5 clips (26s)
  speaker_2     0:23 of speech   4 clips (23s)
  speaker_3     0:18 of speech   4 clips (16s)
  (skipped 0:03 where voices overlapped or were unclear)
```

1. Listen to `output/split/game-night/speaker_1_preview.wav`, `speaker_2_preview.wav`
   and so on to work out who is who.
2. If that person agreed, add them straight from their folder:
   ```bash
   python voiceclone.py add "Maya" output/split/game-night/speaker_1
   ```
   You can add clips from several videos to the same person to improve their voice.

`report.txt` in the same folder lists exactly when each person talks.

- **Videos** (`.mp4`, `.mov`, `.mkv`, ...) need [FFmpeg](https://ffmpeg.org/download.html) installed.
- **Wrong number of people?** If one person shows up twice, or two people got
  merged into one, run it again with the right count: `--speakers 3`.
- Speakers with only a few seconds of clips are often someone who barely spoke,
  or a mix of people talking at once. Listen before adding them.
- It works best with people taking turns: lots of crosstalk, loud music or
  a noisy room leave fewer clean clips.
- Clones made from video clips sound a little less like the person than ones made
  from a clean voice memo, because video audio is noisier and compressed. If you can,
  add a voice memo to the same person too: `add "Maya" memo.m4a`.
- The first run takes about a minute per 5 minutes of video on a typical CPU
  (it uses the same voice model as cloning, so nothing extra downloads).

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
