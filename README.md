# Wisp

Wisp is a menu bar dictation app for macOS. You press Control-Shift-R, talk, and press it again. Wisp transcribes the speech on your Mac, pastes the text at the cursor, and saves it in a history window. An optional AI cleanup pass removes filler words, applies your self-corrections, and formats lists.

## Requirements

- macOS 14 or later on Apple Silicon.
- Xcode in `/Applications/Xcode.app`. If `xcode-select` points to the Command Line Tools, the build script still uses the Xcode toolchain.
- About 600 MB of disk space for each speech model. Wisp downloads the model on first use.
- For the AI cleanup only: an [OpenRouter](https://openrouter.ai) API key.

## Build and install

To build the app and install it in `/Applications`, run this command in the repository folder:

```sh
make install
```

The script quits a running copy of Wisp, replaces `/Applications/Wisp.app`, and opens the new copy. To build `build/Wisp.app` without installing it, run `make app`. Only one copy of Wisp runs at a time. If you open a second copy, it exits immediately.

On the first launch, Wisp does these things:

1. It adds itself to the login items. As a result, Wisp opens at each login.
2. It opens the transcripts window.
3. It asks for microphone access.
4. It asks for Accessibility access, so that it can paste the text.
5. It downloads and prepares the English speech model.

## Use Wisp

1. Press Control-Shift-R in any app. The indicator shows at the bottom of the screen with a yellow dot and "Starting mic".
2. Wait for the start sound. The bars replace "Starting mic" at the same time. If the microphone hears sound, the bars move.
3. Talk.
4. To finish, press Control-Shift-R again or click the red stop button. Wisp pastes the text at the cursor and shows "Pasted".

To discard a recording, click the X button on the indicator. Recordings shorter than 0.3 seconds are discarded automatically.

The menu bar icon opens a menu with these items:

- Start Dictation or Stop Dictation.
- Copy Last Transcript, and the three most recent transcripts. Click one to copy it.
- Paste Last Transcript, while auto-paste is on.
- Open Wisp, which opens the transcripts window.
- AI Cleanup, which turns the cleanup on or off.
- Auto-Paste, which turns the paste on or off.
- Microphone, which selects the microphone.
- Settings.

The transcripts window lists every transcript, newest first, grouped by day. Each entry shows the time, the length of the recording, and the word count. Hover over an entry to copy or delete it. After a delete, you can click Undo for five seconds. The search field filters the list. The gear button opens the settings.

## Auto-paste

Auto-paste works the same way as in Wispr Flow. When a transcript is ready, Wisp does these steps:

1. It checks whether the cursor is in a text field of the app in front.
2. It puts the text on the clipboard and presses Command-V.
3. After half a second, it puts back the previous contents of the clipboard. In a remote desktop or virtual machine app, Wisp waits five seconds, because these apps send the clipboard to the other computer first.

If the cursor is not in a text field, Wisp copies the text to the clipboard and shows "Copied. No text field to paste into". Click a text field and press Command-V.

To paste the last transcript again, press Control-Command-V, or choose Paste Last Transcript in the menu bar menu. Wisp holds this shortcut only while auto-paste is on.

Some apps draw their own text views and do not tell macOS where the cursor is, for example some terminals and Electron apps. In these apps, Wisp pastes without the check.

Clipboard managers do not save the pasted text, because Wisp marks it as transient with the [nspasteboard.org](http://nspasteboard.org) markers. If the previous clipboard contents are a password from a password manager, Wisp does not put them back. The password manager cannot clear a copy that Wisp puts back.

Wisp needs Accessibility access to find the text field and to press Command-V. Wisp reads only the type of the focused element, for example "text field". It does not read the text in the field.

To turn off auto-paste, use Settings > General or Auto-Paste in the menu bar menu. Wisp then copies each transcript to the clipboard and leaves it there.

## Microphone

A Bluetooth microphone, for example AirPods, takes about one second to start. The headphones must first switch to headset mode, and that mode also lowers their sound quality. The built-in MacBook microphone starts in about 0.2 seconds.

For this reason, the default microphone setting is Automatic. If your default microphone is Bluetooth, Wisp records from the built-in microphone. If the built-in microphone sends no audio within 1.2 seconds, Wisp switches to the system default.

To use one device, for example your AirPods, choose it in the Microphone menu of the menu bar icon, or in Settings > General > Microphone. Wisp then waits for that device, also when it is slow to start. If the device is not connected, Wisp uses the system default.

## Speech models

Wisp runs open-source NVIDIA Parakeet models on the Neural Engine through [FluidAudio](https://github.com/FluidInference/FluidAudio).

| Setting | Model | Languages | Note |
|---|---|---|---|
| English (default) | Parakeet Unified 0.6B | English | Most accurate for English |
| Multilingual | Parakeet Ultra 0.6B | 25 European languages | Detects the language automatically |

On an M4 MacBook Pro, 34 seconds of speech transcribes in about 0.25 seconds. Both models write punctuation, capital letters, and numbers ("$42,000", "7.30").

To change the model, use Settings > General > Speech model. Wisp downloads a model the first time you select it. If a dictation finishes before the model is ready, Wisp waits for the model and then transcribes.

## AI cleanup

The AI cleanup sends each transcript to a language model through OpenRouter. The model does these things:

- It removes filler words, false starts, and repeated words. It keeps the words that open a sentence, for example "OK", "So", or "Hey".
- It applies self-corrections. For example, "Tuesday, no, Wednesday" becomes "Wednesday".
- It fixes misheard words, names, punctuation, and sentence boundaries.
- It turns spoken lists into bullet points or numbered steps.

To set up the cleanup, do these steps:

1. Create a key at [openrouter.ai/keys](https://openrouter.ai/keys).
2. Open Settings > AI Cleanup.
3. Paste the key and click Save. Wisp stores the key in your login keychain, turns on the cleanup, and tests the key.
4. Optional: add your own names and terms under Names and terms, for example your company, products, and colleagues.

While the model works, the indicator shows "Cleaning up". To copy the transcript without the cleanup, click Skip. If the cleanup fails or takes longer than 8 seconds, Wisp copies the transcript without cleanup and shows "Copied without cleanup". If the model output is much longer or much shorter than the transcript, Wisp also keeps the transcript. This check stops a model that answers the dictated text instead of cleaning it.

In the transcripts window, a cleaned entry has a "Cleaned up" label. Click the label to see and copy the text before the cleanup.

| Model | Cost per dictation (about 150 words) |
|---|---|
| GPT-5.6 Luna (default) | about $0.0005 |
| Claude Haiku 4.5 | about $0.002 |
| gpt-oss-120b | about $0.0001 |

You can also enter any other OpenRouter model ID. Wisp reads the public OpenRouter model list and asks each model for its lowest reasoning setting, because the cleanup needs a fast answer.

Wisp sends the transcript text, the names and terms, and the name of the app that you dictate into. Your audio stays on your Mac.

## Where Wisp keeps data

- Transcripts: `~/Library/Application Support/Wisp/transcripts.json`
- Speech models: `~/Library/Application Support/FluidAudio/Models/`
- OpenRouter API key: the login keychain, item "Wisp OpenRouter key". Builds from before 1 October 2026 used an item named "Wisp OpenRouter API key". Wisp copies the key from it one time. Then you can delete the old item in Keychain Access.
- Settings: the `com.unculture.Wisp` user defaults domain

If Wisp cannot read the transcripts file, it keeps a copy named `transcripts.unreadable-<time>.json` next to it before it writes a new file.

## Troubleshooting

If the indicator says "Microphone access is off", click Open Settings. Then turn on Wisp in Privacy & Security > Microphone.

If the indicator shows an Allow Pasting button, Wisp has no Accessibility access. Click Allow Pasting, and turn on Wisp in Privacy & Security > Accessibility. If Wisp is on in that list but still cannot paste, turn it off and on again.

If the indicator says "Pasted" but no text shows up, the app did not take the paste. Choose Copy Last Transcript in the menu bar menu, click the text field, and press Command-V.

After each rebuild, macOS asks one time whether Wisp can use its keychain item. The reason is that the keychain ties an item to the exact build of an app that has no Apple team ID. Click Always Allow. If you click Allow, macOS asks again at each launch.

If Wisp says that the shortcut is not available, another app uses Control-Shift-R. Quit that app and open Wisp again.

If the model download fails, click Retry in the transcripts window.

If a transcription fails, the indicator shows a Retry button for six seconds. Wisp keeps the failed recording in memory until the next retry.

If the cleanup often shows "Copied without cleanup", click Test in Settings > AI Cleanup. The test shows the OpenRouter error, for example an invalid key or no credit.

## Developer commands

To transcribe an audio file with a speech model, run the app binary from the terminal:

```sh
.build/release/Wisp --transcribe speech.wav --engine english
.build/release/Wisp --transcribe speech.wav --engine multilingual
```

To run sample transcripts through the AI cleanup with each preset model, run the command below. The command reads the key from `OPENROUTER_API_KEY`, or else from the keychain. Run the installed binary, as shown: the keychain treats a binary in the build folder as a different app and asks for access. To test one model, add `--model <model ID>`. To test a list of names and terms, add `--glossary "<names and terms>"`.

```sh
/Applications/Wisp.app/Contents/MacOS/Wisp --cleanup-test
```

To list the microphones and measure how long one takes to start, run the command below. The `open -n` command makes macOS use the microphone permission of Wisp. Use `auto`, `system`, or a device UID from the list.

```sh
open -n -W --stdout /dev/stdout build/Wisp.app --args --mic-test auto
```

To check the parts of auto-paste, run the command below. It prints the Accessibility access and the key that types V in your keyboard layout. It also tests the clipboard copy on a private pasteboard, and prints the focus check for each open app. The command does not paste anything.

```sh
open -n -W --stdout /dev/stdout build/Wisp.app --args --paste-test
```

To render the indicator states, the transcripts window, and the settings to PNG files, run this command:

```sh
.build/release/Wisp --snapshot /tmp/wisp-snapshots
```

If a copy of the binary outside the app bundle added itself as a login item, run that binary with `--unregister-login-item` to remove the item.

To draw the app icon again, run `make icon`.

## Share Wisp with colleagues

Wisp has an ad-hoc signature, and Apple did not notarize it. For this reason, macOS blocks a copy of `Wisp.app` that arrives by download, AirDrop, or chat. You can give Wisp to a colleague in two ways:

1. The colleague clones this repository and runs `make install`. macOS does not block an app that was built on the same Mac. The colleague needs Xcode.
2. You sign Wisp with a Developer ID certificate and notarize it. This needs a membership in the Apple Developer Program, for example through your company.

Each colleague needs an Apple Silicon Mac with macOS 14 or later. The first launch downloads about 600 MB from Hugging Face. If a company network blocks Hugging Face, FluidAudio can use a mirror. For the AI cleanup, each colleague needs an OpenRouter key: their own key, or a key from the company.

## Licenses

Wisp downloads the speech models from Hugging Face at run time. This repository does not contain them.

- [FluidAudio](https://github.com/FluidInference/FluidAudio): Apache License 2.0.
- Parakeet Unified 0.6B (the English model): Licensed by NVIDIA Corporation under the [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/).
- Parakeet Ultra (the multilingual model): [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), by moondream. It is a post-training of NVIDIA Parakeet TDT 0.6B v3, which is also CC BY 4.0.

Both model licenses allow commercial use, with attribution.

## Project layout

- `Sources/Wisp/DictationController.swift`: the record, transcribe, clean up, copy, and save cycle.
- `Sources/Wisp/Audio/`: microphone selection, capture, conversion to 16 kHz mono, and the level meter.
- `Sources/Wisp/Speech/SpeechEngine.swift`: model download, loading, warm-up, and transcription.
- `Sources/Wisp/Cleanup/`: the OpenRouter client, the cleanup prompt and output checks, and the keychain storage.
- `Sources/Wisp/System/HotKey.swift`: the global shortcuts. They use Carbon hot keys, so they need no Accessibility permission.
- `Sources/Wisp/System/Paster.swift`: the text field check, the paste, and the clipboard restore.
- `Sources/Wisp/UI/`: the indicator, the transcripts window, the settings, and the menu bar item.
- `Sources/Wisp/Model/`: transcripts, storage, and preferences.
