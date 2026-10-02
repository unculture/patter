# Patter

Patter is a menu bar dictation app for macOS. You press Control-Shift-R, talk, and press it again. For a short message, you can also hold a push-to-talk shortcut while you talk. Patter transcribes the speech on your Mac, pastes the text at the cursor, and saves it in a history window. An optional AI cleanup pass removes filler words, applies your self-corrections, and formats lists.

## Requirements

- macOS 14 or later on Apple Silicon.
- Xcode in `/Applications/Xcode.app`. If `xcode-select` points to the Command Line Tools, the build script still uses the Xcode toolchain.
- About 600 MB of disk space for each speech model. Patter downloads the model on first use.
- For the AI cleanup only: an [OpenRouter](https://openrouter.ai) API key.

## Build and install

To build the app and install it in `/Applications`, run this command in the repository folder:

```sh
make install
```

The script quits a running copy of Patter, replaces `/Applications/Patter.app`, and opens the new copy. To build `build/Patter.app` without installing it, run `make app`. Only one copy of Patter runs at a time. If you open a second copy, it exits immediately.

On the first launch, Patter does these things:

1. It adds itself to the login items. As a result, Patter opens at each login.
2. It opens the transcripts window.
3. It asks for microphone access.
4. It asks for Accessibility access, so that it can paste the text.
5. It downloads and prepares the English speech model.

## Use Patter

1. Press Control-Shift-R in any app. The indicator shows at the bottom of the screen with a yellow dot and "Starting mic".
2. Wait for the start sound. The bars replace "Starting mic" at the same time. If the microphone hears sound, the bars move.
3. Talk.
4. To finish, press Control-Shift-R again or click the red stop button. Patter pastes the text at the cursor and shows "Pasted".

To discard a recording, click the X button on the indicator. Recordings shorter than 0.3 seconds are discarded automatically.

Control-Shift-R is the default shortcut. To use different keys, see [Shortcuts](#shortcuts).

The menu bar icon opens a menu with these items:

- Start Dictation or Stop Dictation.
- Copy Last Transcript, and the three most recent transcripts. Click one to copy it.
- Paste Last Transcript, while auto-paste is on.
- Open Patter, which opens the transcripts window.
- AI Cleanup, which turns the cleanup on or off.
- Auto-Paste, which turns the paste on or off.
- Microphone, which selects the microphone.
- Settings.

The transcripts window lists every transcript, newest first, grouped by day. Each entry shows the time, the length of the recording, and the word count. Hover over an entry to copy or delete it. After a delete, you can click Undo for five seconds. The search field filters the list. The gear button opens the settings.

## Shortcuts

Patter has two shortcuts for dictation. You press the dictation shortcut one time to start and again to stop. The default is Control-Shift-R.

The push-to-talk shortcut records only while you hold it down. When you release it, Patter stops the recording and pastes the text. Push to talk is good for short messages. It is off until you set a shortcut.

To set or change a shortcut, do these steps:

1. Open Settings > General.
2. Under Shortcuts, click the field next to "Start and stop dictation" or "Push to talk".
3. Press the new keys, for example Control-Option-Space. To cancel, press Escape.

To remove a shortcut, click the X button in its field. Without a dictation shortcut, you can start dictation from the menu bar icon.

To use push to talk, hold the shortcut down. Wait for the start sound, then talk. Release the shortcut when you finish. If you release it before the start sound, Patter discards the recording. A Bluetooth microphone takes about one second to start.

A shortcut must include Control or Command, because Patter must not take a key that you type. A function key, for example F5, also works alone. The two shortcuts must be different. Patter does not accept Control-Command-V, because that shortcut pastes the last transcript.

If another app uses the shortcut, Settings shows a warning. Choose a different shortcut.

## Auto-paste

Auto-paste works the same way as in Wispr Flow. When a transcript is ready, Patter does these steps:

1. It checks whether the cursor is in a text field of the app in front.
2. It puts the text on the clipboard and presses Command-V.
3. After half a second, it puts back the previous contents of the clipboard. In a remote desktop or virtual machine app, Patter waits five seconds, because these apps send the clipboard to the other computer first.

If the cursor is not in a text field, Patter copies the text to the clipboard and shows "Copied. No text field to paste into". Click a text field and press Command-V.

To paste the last transcript again, press Control-Command-V, or choose Paste Last Transcript in the menu bar menu. Patter holds this shortcut only while auto-paste is on.

Some apps draw their own text views and do not tell macOS where the cursor is, for example some terminals and Electron apps. In these apps, Patter pastes without the check.

Clipboard managers do not save the pasted text, because Patter marks it as transient with the [nspasteboard.org](http://nspasteboard.org) markers. If the previous clipboard contents are a password from a password manager, Patter does not put them back. The password manager cannot clear a copy that Patter puts back.

Patter needs Accessibility access to find the text field and to press Command-V. Patter reads only the type of the focused element, for example "text field". It does not read the text in the field.

To turn off auto-paste, use Settings > General or Auto-Paste in the menu bar menu. Patter then copies each transcript to the clipboard and leaves it there.

## Microphone

A Bluetooth microphone, for example AirPods, takes about one second to start. The headphones must first switch to headset mode, and that mode also lowers their sound quality. The built-in MacBook microphone starts in about 0.2 seconds.

For this reason, the default microphone setting is Automatic. If your default microphone is Bluetooth, Patter records from the built-in microphone. If the built-in microphone sends no audio within 1.2 seconds, Patter switches to the system default.

To use one device, for example your AirPods, choose it in the Microphone menu of the menu bar icon, or in Settings > General > Microphone. Patter then waits for that device, also when it is slow to start. If the device is not connected, Patter uses the system default.

## Speech models

Patter runs open-source NVIDIA Parakeet models on the Neural Engine through [FluidAudio](https://github.com/FluidInference/FluidAudio).

| Setting | Model | Languages | Note |
|---|---|---|---|
| English (default) | Parakeet Unified 0.6B | English | Most accurate for English |
| Multilingual | Parakeet Ultra 0.6B | 25 European languages | Detects the language automatically |

On an M4 MacBook Pro, 34 seconds of speech transcribes in about 0.25 seconds. Both models write punctuation, capital letters, and numbers ("$42,000", "7.30").

To change the model, use Settings > General > Speech model. Patter downloads a model the first time you select it. If a dictation finishes before the model is ready, Patter waits for the model and then transcribes.

## AI cleanup

The AI cleanup sends each transcript to a language model through OpenRouter. The model does these things:

- It removes filler words, false starts, and repeated words. It keeps the words that open a sentence, for example "OK", "So", or "Hey".
- It applies self-corrections. For example, "Tuesday, no, Wednesday" becomes "Wednesday".
- It fixes misheard words, names, punctuation, and sentence boundaries.
- It turns spoken lists into bullet points or numbered steps.

To set up the cleanup, do these steps:

1. Create a key at [openrouter.ai/keys](https://openrouter.ai/keys).
2. Open Settings > AI Cleanup.
3. Paste the key and click Save. Patter stores the key in your login keychain, turns on the cleanup, and tests the key.
4. Optional: add your own names and terms under Names and terms, for example your company, products, and colleagues.

While the model works, the indicator shows "Cleaning up". To copy the transcript without the cleanup, click Skip. If the cleanup fails or takes longer than 8 seconds, Patter copies the transcript without cleanup and shows "Copied without cleanup". If the model output is much longer or much shorter than the transcript, Patter also keeps the transcript. This check stops a model that answers the dictated text instead of cleaning it.

In the transcripts window, a cleaned entry has a "Cleaned up" label. Click the label to see and copy the text before the cleanup.

| Model | Cost per dictation (about 150 words) |
|---|---|
| GPT-5.6 Luna (default) | about $0.0005 |
| Claude Haiku 4.5 | about $0.002 |
| gpt-oss-120b | about $0.0001 |

You can also enter any other OpenRouter model ID. Patter reads the public OpenRouter model list and asks each model for its lowest reasoning setting, because the cleanup needs a fast answer.

Patter sends the transcript text, the names and terms, and the name of the app that you dictate into. Your audio stays on your Mac.

## Where Patter keeps data

- Transcripts: `~/Library/Application Support/Patter/transcripts.json`
- Speech models: `~/Library/Application Support/FluidAudio/Models/`
- OpenRouter API key: the login keychain, item "Patter OpenRouter key"
- Settings: the `com.unculture.Patter` user defaults domain

If Patter cannot read the transcripts file, it keeps a copy named `transcripts.unreadable-<time>.json` next to it before it writes a new file.

## Update from Wisp

Patter was called Wisp until 1 October 2026. When you run `make install`, the script quits Wisp, removes its login item, and deletes `/Applications/Wisp.app`. On the first launch, Patter copies these items from Wisp:

1. The settings, for example the microphone, the speech model, and the names and terms.
2. The transcripts.
3. The OpenRouter API key. macOS asks one time whether Patter can read the key of Wisp. Click Allow.

macOS treats Patter as a new app. As a result, Patter asks again for microphone access and Accessibility access, and it adds its own login item.

Patter does not delete the data of Wisp. When Patter works, you can delete these items:

- The folder `~/Library/Application Support/Wisp`.
- The items "Wisp OpenRouter key" and "Wisp OpenRouter API key" in Keychain Access.
- The settings, with the command `defaults delete com.unculture.Wisp`.
- The Wisp entries in Privacy & Security > Microphone and Accessibility, with the commands `tccutil reset Microphone com.unculture.Wisp` and `tccutil reset Accessibility com.unculture.Wisp`.

## Troubleshooting

If the indicator says "Microphone access is off", click Open Settings. Then turn on Patter in Privacy & Security > Microphone.

If the indicator shows an Allow Pasting button, Patter has no Accessibility access. Click Allow Pasting, and turn on Patter in Privacy & Security > Accessibility. If Patter is on in that list but still cannot paste, turn it off and on again.

If the indicator says "Pasted" but no text shows up, the app did not take the paste. Choose Copy Last Transcript in the menu bar menu, click the text field, and press Command-V.

After each rebuild, macOS asks one time whether Patter can use its keychain item. The reason is that the keychain ties an item to the exact build of an app that has no Apple team ID. Click Always Allow. If you click Allow, macOS asks again at each launch.

If Patter says that a shortcut is not available, another app uses the same keys. Choose a different shortcut in Settings > General, or quit the other app and open Patter again.

If the model download fails, click Retry in the transcripts window.

If a transcription fails, the indicator shows a Retry button for six seconds. Patter keeps the failed recording in memory until the next retry.

If the cleanup often shows "Copied without cleanup", click Test in Settings > AI Cleanup. The test shows the OpenRouter error, for example an invalid key or no credit.

## Developer commands

To transcribe an audio file with a speech model, run the app binary from the terminal:

```sh
.build/release/Patter --transcribe speech.wav --engine english
.build/release/Patter --transcribe speech.wav --engine multilingual
```

To run sample transcripts through the AI cleanup with each preset model, run the command below. The command reads the key from `OPENROUTER_API_KEY`, or else from the keychain. Run the installed binary, as shown: the keychain treats a binary in the build folder as a different app and asks for access. To test one model, add `--model <model ID>`. To test a list of names and terms, add `--glossary "<names and terms>"`.

```sh
/Applications/Patter.app/Contents/MacOS/Patter --cleanup-test
```

To list the microphones and measure how long one takes to start, run the command below. The `open -n` command makes macOS use the microphone permission of Patter. Use `auto`, `system`, or a device UID from the list.

```sh
open -n -W --stdout /dev/stdout build/Patter.app --args --mic-test auto
```

To check the parts of auto-paste, run the command below. It prints the Accessibility access and the key that types V in your keyboard layout. It also tests the clipboard copy on a private pasteboard, and prints the focus check for each open app. The command does not paste anything.

```sh
open -n -W --stdout /dev/stdout build/Patter.app --args --paste-test
```

To render the indicator states, the transcripts window, and the settings to PNG files, run this command:

```sh
.build/release/Patter --snapshot /tmp/patter-snapshots
```

If a copy of the binary outside the app bundle added itself as a login item, run that binary with `--unregister-login-item` to remove the item.

To draw the app icon again, run `make icon`.

## Share Patter with colleagues

Patter has an ad-hoc signature, and Apple did not notarize it. For this reason, macOS blocks a copy of `Patter.app` that arrives by download, AirDrop, or chat. You can give Patter to a colleague in two ways:

1. The colleague clones this repository and runs `make install`. macOS does not block an app that was built on the same Mac. The colleague needs Xcode.
2. You sign Patter with a Developer ID certificate and notarize it. This needs a membership in the Apple Developer Program, for example through your company.

Each colleague needs an Apple Silicon Mac with macOS 14 or later. The first launch downloads about 600 MB from Hugging Face. If a company network blocks Hugging Face, FluidAudio can use a mirror. For the AI cleanup, each colleague needs an OpenRouter key: their own key, or a key from the company.

## Licenses

Patter downloads the speech models from Hugging Face at run time. This repository does not contain them.

- [FluidAudio](https://github.com/FluidInference/FluidAudio): Apache License 2.0.
- Parakeet Unified 0.6B (the English model): Licensed by NVIDIA Corporation under the [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/).
- Parakeet Ultra (the multilingual model): [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), by moondream. It is a post-training of NVIDIA Parakeet TDT 0.6B v3, which is also CC BY 4.0.

Both model licenses allow commercial use, with attribution.

## Project layout

- `Sources/Patter/DictationController.swift`: the record, transcribe, clean up, copy, and save cycle.
- `Sources/Patter/Audio/`: microphone selection, capture, conversion to 16 kHz mono, and the level meter.
- `Sources/Patter/Speech/SpeechEngine.swift`: model download, loading, warm-up, and transcription.
- `Sources/Patter/Cleanup/`: the OpenRouter client, the cleanup prompt and output checks, and the keychain storage.
- `Sources/Patter/System/HotKey.swift`, `Shortcut.swift`, and `ShortcutController.swift`: the global shortcuts, the names of their keys, and the recording of a new shortcut in the settings. The shortcuts use Carbon hot keys, so they need no Accessibility permission.
- `Sources/Patter/System/Paster.swift`: the text field check, the paste, and the clipboard restore.
- `Sources/Patter/UI/`: the indicator, the transcripts window, the settings, and the menu bar item.
- `Sources/Patter/Model/`: transcripts, storage, and preferences.
