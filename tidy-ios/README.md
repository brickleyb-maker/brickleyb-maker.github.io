# Tidy

A private, swipe-to-clean photo app for your own iPhone. Built so you control the code.

## What it does
- **Months:** swipe through your library month by month. Right = keep, left = bin. Undo anytime.
- **Clean Up:** similar-photo groups (on-device Apple Vision), large videos biggest first, screenshots.
- **Bin:** everything you swiped left waits here. One tap deletes it all. iOS asks you to confirm, and items sit in Recently Deleted for 30 days.

## Privacy
- No networking code, no analytics, no accounts, no third-party libraries.
- Your keep/bin choices live in one small file inside the app's sandbox.
- Verify it: Settings > Privacy & Security > App Privacy Report.
- If your photos are in iCloud, Apple's Photos system may download a full-size copy of your own photo for the preview. That is Apple's system service, not Tidy.

## Put it on your iPhone (about 10 minutes, first time)
1. On your Mac, clone this repo and open `tidy-ios/Tidy.xcodeproj` in Xcode (16 or newer).
2. Click the **Tidy** project in the left sidebar > **Signing & Capabilities** > pick your **Team** (your Apple Developer account).
   If Xcode says the bundle ID is taken, change `com.brickleyb.tidy` to anything unique.
3. Plug in your iPhone, trust the computer, and pick it as the run destination at the top of Xcode.
4. First time only: on the iPhone, Settings > Privacy & Security > **Developer Mode** > On (it restarts).
5. Press **Run** (Cmd+R). With a paid developer account the app stays installed for a year.

## Tuning
- Similar photos: the Strict/Loose slider regroups instantly without rescanning. Start strict.
