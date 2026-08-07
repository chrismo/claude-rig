---
name: kaomoji
description: Summon a Japanese-style emoticon (kaomoji) and put it on the clipboard. Pick one that fits the mood — the user's, the moment's, or the conversation's. Invoked as /kaomoji, optionally with a mood or a free-text vibe.
allowed-tools: Bash
model: haiku
effort: low
---

# kaomoji — summon a face

Pick the face that fits, copy it, say one line. **Do it in a single Bash call.**
The full catalog is below, so you never need to run `--list` first.

## Do exactly this

One tool call, then one line of prose. Nothing else:

```
printf '%s' '(・へ・)' | pbcopy
```

Single-quote the face — they're full of backslashes and parens. If the face
itself contains a single quote, use `kaomoji <mood>` instead to draw one.

Then reply with just the face and a short clause on why. Example:

> `(・へ・)` — copied. Rage was too hot for "blerg"; this is the *oh, come on* face.

Do not run `--list`, do not verify with `pbpaste`, do not explain your process.
One call, one line.

## Choosing

Match the *intensity*, not just the valence. "Bummed" is deflated, not weeping.
"Blerg" is exasperated, not enraged. When the argument is free text, map it to
the nearest face below rather than the nearest mood name.

With no argument, read the session: just shipped → celebrate, third failed test
→ table-flip, Friday afternoon → friday. If nothing stands out, run bare
`kaomoji`.

## The catalog

```
happy         (◕‿◕)  (＾▽＾)  (´･ω･`)ﾉ  ヽ(´▽`)/  (*^▽^*)
              (๑˃ᴗ˂)ﻭ  (✿◠‿◠)  (≧◡≦)  ＼(^o^)／  (◍•ᴗ•◍)

excited       ヽ(°〇°)ﾉ  (ﾉ◕ヮ◕)ﾉ*:･ﾟ✧  ＼(≧▽≦)／  o(≧∇≦o)
              (★^O^★)  ヽ(＾Д＾)ﾉ  (๑>◡<๑)  ٩(◕‿◕)۶

shrug         ¯\_(ツ)_/¯  ╮(￣▽￣)╭  ┐(´д`)┌  ᕕ( ᐛ )ᕗ
              ╮(︶︿︶)╭  乁( ⁰͡ Ĺ̯ ⁰͡ )ㄏ

table-flip    (╯°□°)╯︵ ┻━┻  (ノಠ益ಠ)ノ彡┻━┻  (ノ`Д´)ノ彡┻━┻
              ┻━┻ ︵ヽ(`Д´)ﾉ︵ ┻━┻

table-unflip  ┬─┬ノ( º _ ºノ)  ┬──┬ ¯\_(ツ)  (╮°-°)╮┳━┳

rage          (╬ ಠ益ಠ)  ヽ(≧Д≦)ノ  (＃`Д´)  (ﾉಥ益ಥ)ﾉ  ୧((#Φ益Φ#))୨

sad           (╥﹏╥)  (っ- ‸ - ς)  (｡•́︿•̀｡)  (ಥ﹏ಥ)  (´；ω；`)  (◞‸◟)

confused      (・_・?)  (⊙_⊙)?  (°ロ°) !  ٩(͡๏_๏)۶  (¬_¬)  (・∀・)?

smug          (¬‿¬)  ( ͡° ͜ʖ ͡°)  (￣ω￣)  ヽ(・∀・)ﾉ  (^_~)  ( •_•)>⌐■-■  (⌐■_■)

tired         (－_－) zzZ  (｡-‿-｡)  ( ˘･з･)  (・_・;)  (￣﹃￣)  （￣o￣） . z Z

love          (♥ω♥*)  (*♡∀♡)  (´,,•ω•,,)♡  ♡( ◡‿◡ )  (っ˘з(˘⌣˘ )

bear          ʕ•ᴥ•ʔ  ʕ￫ᴥ￩ʔ  ʕっ•ᴥ•ʔっ  ʕ•̀ω•́ʔ✧

cat           (=^･ω･^=)  ฅ^•ﻌ•^ฅ  (=①ω①=)  ヾ(=｀ω´=)ノ”

celebrate     ヽ(*⌒▽⌒*)ﾉ  (っ˘ω˘ς )  ＼(^▽^)／  (*≧▽≦)ﾉ ~☆  ٩(ˊᗜˋ*)و

friday        ヽ(o^▽^o)ノ  (´｡• ᵕ •｡`) ♡  (ノ^_^)ノ  ＼(٥⁀▽⁀ )／
              (っ^▿^)۶🍺  (*≧∀≦*)

dunno         (•_•)  (￢_￢)  ( ˘⌒˘ )  (・へ・)

determined    (ง •̀_•́)ง  ᕦ(ò_óˇ)ᕤ  (๑•̀ㅂ•́)و✧  o(￣ヘ￣o＃)

oops          (・_・;)  (￣▽￣;)  (； ･`д･´)  (°ロ°;)  (⁄ ⁄•⁄ω⁄•⁄ ⁄)
```

## Adding faces

Faces live in the `MOODS` array in `bin/kaomoji` in the claude-rig repo — edit
there, never `~/.local/bin/kaomoji` (a symlink). **Update the catalog above to
match**, then re-run the tests, which check the two stay in sync:

```
PATH="/opt/homebrew/opt/bash/bin:$PATH" bats bin/kaomoji.bats
```
