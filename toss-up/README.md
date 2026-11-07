# Toss-Up

A small desktop app for when you can't decide. Type the question, list your options, and pick
one of eight ways to settle it. Everything runs on your own computer: no account, no install,
no internet needed (except for the fonts, which fall back to built-in ones when you're offline).

## Open it

**Windows**

- Double-click **`Toss-Up.bat`**. It opens Toss-Up in its own window, like an installed app
  (Microsoft Edge or Google Chrome "app mode").
- To keep it handy, double-click **`Add-Shortcuts.bat`** once. It puts a Toss-Up shortcut with
  its own icon on your Desktop and in the Start menu. Pin that to the taskbar if you like.
  If you move the folder later, run it again. To remove them, delete the two shortcuts.

**Mac or Linux**

- Double-click **`index.html`** to open it in your browser.
- In Chrome or Edge you can also start it as its own window from a terminal:

```bash
google-chrome --app="file://$PWD/index.html"
```

## The eight ways to decide

| Game | How it works | Good for |
|---|---|---|
| **Spin the wheel** | Every option gets an equal slice. Spin and the pointer picks. | Any list. |
| **Pick a card** | Options are dealt face down. Shuffle, then turn one over. The others flip afterwards so you can see what you passed up. | Feeling it out. |
| **Flip a coin** | Pick two options for heads and tails. When it lands you get a gut check: relieved or disappointed? If you were disappointed, you wanted the other one. | Two-way choices. |
| **Peg drop** | Each option gets a bin. Click along the top to aim, and the ball bounces through the pegs. | Watching chaos decide. |
| **Head to head** | A bracket where you pick the winner of each matchup until one is left. Arrow keys work. | When you don't know what you want. |
| **Last one standing** | Options are knocked out at random. Tap a knocked-out one to rescue it (once each). What you rescue is a clue. | Finding out what you'd miss. |
| **Weigh it up** | Add reasons to each side of a balance scale, from a feather (1) to an anvil (5), and watch it tip. | Choices with real pros. |
| **Ask the oracle** | A crystal ball for yes-or-no questions. Ask the same thing twice and it notices. | Fun, mostly. |

Every result is written to **the ledger** (top right), so you can look back at what you decided.

## Tips

- Press **Space** to play the current game.
- **Load a set** fills in ready-made options (dinner, weekend plans, game night and more).
- Up to 16 options. The wheel, cards, peg drop and knockout all handle the full 16.
- Your options, reasons and ledger are saved in the browser on this computer. Clearing your
  browser's site data for local files removes them.
- Sound can be turned off with the **Sound on** button.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole app in one file. |
| `Toss-Up.bat` | Opens the app in its own window on Windows. |
| `Add-Shortcuts.bat` | Adds Desktop and Start menu shortcuts (runs `tools/make-shortcuts.ps1`). |
| `toss-up.ico` | The app icon used by the shortcuts. |
