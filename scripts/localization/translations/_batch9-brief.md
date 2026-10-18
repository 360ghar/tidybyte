# Translation batch 9 — 9 Siri phrases

These are the App Shortcut phrases for Siri and Spotlight. They reached the
catalog only after the extractor learned to read them: the Swift compiler
extracts a shortcut's `shortTitle` but not its `phrases`, so all nine had been
shipping in English in every language while the catalog reported full coverage.

Write each into `scripts/localization/translations/<lang>.json` under
`"strings"`. Key is the exact English text. Do not add, rename, or reorder keys.

| English |
|---|
| `Start a cleanup session with %@` |
| `Clean up photos with %@` |
| `Tidy my photos with %@` |
| `Show storage in %@` |
| `Check my storage with %@` |
| `Clean screenshots with %@` |
| `How much can I free with %@` |
| `Check free space with %@` |
| `Show my savings in %@` |

## These are spoken, not read

This is the one batch where the string is **said out loud to Siri**. That
changes what matters:

1. **`%@` is the app's name** — Siri substitutes "TidyByte" for it. It appears
   exactly once per phrase. Keep it in a position where the sentence still
   parses when the name is dropped in, and where it reads naturally spoken
   aloud. If your language would place the name at the start of the sentence
   rather than the end, reorder it — with one placeholder there is no positional
   syntax to worry about.
2. **Write it the way someone actually talks.** Not a menu label, not a
   command form you would only ever see printed. If a person asking their phone
   to do this would phrase it differently from a literal translation, write what
   they would say. Apple's own App Shortcut phrases in your language are the
   register to match.
3. **Keep it short.** Siri matches on the phrase, and a long one is harder to
   say and harder to match. Aim for roughly the length of the English.
4. **`Clean screenshots with %@`** — "screenshots" must use the glossary term
   for your language. It is the same noun the Screenshots tool uses.
5. **`Show my savings in %@`** — "savings" is the space the user has freed up,
   the total on the Activity & Savings screen. Not money, and not "discount".
6. **`How much can I free with %@`** — a question, with no question mark in the
   English (Siri phrases omit it). Follow your language's convention: add the
   question mark if your language normally writes one, since Siri's matcher
   ignores punctuation.

## Placeholder reminder

`%@` appears exactly once in every phrase. Do not drop it, do not add a second.
The phrase must contain the app name placeholder or Siri will not register the
shortcut — that is a hard requirement of `AppShortcutsProvider`, not a style
preference.

## Right-to-left languages (ar, he)

Everything above applies. Phrase these the way a speaker of your language would
ask their phone, and place `%@` where the name naturally falls in the spoken
sentence.
