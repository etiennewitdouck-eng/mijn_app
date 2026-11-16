# Chromecast / Google TV playback plan

## Goal
Keep the original MP3 library and its JPG/VTT sidecar files on the iPhone. Copy selected playback content to the Google TV device over the local Wi-Fi network so playback no longer depends on the iPhone app remaining open.

## Proposed architecture
- The iPhone app remains the library manager and keeps its existing iPhone and Kia Ceed CarPlay experience.
- A separate Android TV mode in the Flutter app runs on Chromecast with Google TV and is navigable with the TV remote (D-pad, select, back).
- The TV app receives selected audio files and associated metadata/artwork/subtitles over the local network and stores a playback cache in its own app-private storage.
- The TV app plays the cached files locally using the existing audio playback stack. The TV queue and transport controls remain available after the iPhone app is closed.
- The cache is a copy; the iPhone originals are not moved or deleted.

## Important distinction
This is an Android TV receiver app installed on Chromecast with Google TV, not ordinary AirPlay mirroring and not a promise that a generic Cast receiver can read iPhone app Documents files. The Google TV device must receive/cache the audio before the iPhone app is closed.

## Implementation stages
1. Add platform-safe CarPlay initialization so Android builds do not invoke iOS-only CarPlay APIs.
2. Add TV receiver mode: local-network transfer endpoint, cache management, and TV-remote-friendly playback/queue UI.
3. Add iPhone sender controls to discover or connect to the TV receiver and send a selected folder/queue with audio and companion files.
4. Test transfer, playback, pause/skip/seek from the TV remote, app termination on iPhone, and restart/reconnection.
5. Build and install the Android TV APK on Chromecast with Google TV; keep the iOS build and CarPlay behavior unchanged.

## Reliability and privacy
- Both devices need to be on the same local Wi-Fi network for transfer.
- Playback after transfer is local to the TV and does not require the iPhone to stay connected.
- Start with an explicit receiver connection/pairing flow. Add automatic discovery only after the basic transfer path is verified.
- Do not delete cached TV files automatically until queue behavior and storage limits are tested.
- Never alter or remove the iPhone originals as part of transfer.
