<div align="center">

<img src="StoryTeller4/Resources/Logo.png" alt="StoryTeller4 Logo" width="128" height="128" />

# StoryTeller

**A modern, native iOS & iPadOS client for [Audiobookshelf](https://www.audiobookshelf.org/).**

[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![iOS 17+](https://img.shields.io/badge/iOS-17.0+-blue.svg?style=flat-square&logo=apple)](https://developer.apple.com/ios/)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPLv3-green.svg?style=flat-square)](LICENSE)
[![Audiobookshelf Compatible](https://img.shields.io/badge/Audiobookshelf-API%20v2-purple.svg?style=flat-square)](https://www.audiobookshelf.org)

</div>

---

## 📖 Overview

**StoryTeller** is a high-performance, native audiobooks player designed specifically for self-hosted [Audiobookshelf](https://www.audiobookshelf.org/) servers. Built from the ground up using **SwiftUI** and **Swift 6 strict concurrency**, it delivers a fluid, responsive listening experience both online and completely offline.

---

## ✨ Features

### 🎧 Playback & Streaming
- **Native Audio Engine**: Built on `AVFoundation` with spoken-word audio session optimization.
- **Track & Chapter Navigation**: Support for both single-file embedded chapters and multi-file track-based audiobooks.
- **Background Playback & Remote Controls**: Full support for lock screen, Control Center, and headphone/CarPlay controls (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`).
- **Gapless Preloading**: Intelligent background preloading of subsequent audio tracks for seamless transitions.
- **Variable Playback Speed**: Flexible playback rate adjustment (0.5× to 2.0×+).
- **Sleep Timer**: Built-in sleep timer with countdown and auto-fade.

### 🔄 Server Sync & Progress Persistence
- **Bidirectional Progress Sync**: Seamlessly sync playback position between devices and the web interface.
- **Smart Heartbeat & Auto-Save**: Regular progress sync during active listening, upon pause, and when app moves to background.
- **Offline Sync Queue**: Listen offline without losing your spot; progress changes queue up and push to the server automatically once reconnected.
- **Personalized Home Feed**: Instant access to "*Continue Listening*", "*Recently Added*", "*Discover*", and series lists.

### 📥 Offline Downloads & Storage Management
- **One-Tap Downloads**: Download entire audiobooks with metadata and cover artwork for offline trips.
- **Background Orchestration**: Resilient multi-track audio downloading with automatic retry logic.
- **Integrity Validation**: Automated verification to detect missing or corrupted downloaded tracks.
- **Storage Monitoring**: Clear breakdown of downloaded storage with one-click cleanup options.

### 📑 Bookmarks
- **Rich Bookmarks**: Create custom timestamped bookmarks with titles and notes.
- **One-Tap Jump**: Seamless navigation back to saved moments.
- **Server Sync**: Automatic synchronization of bookmarks with your Audiobookshelf server.

### 📱 Modern User Interface
- **Clean SwiftUI Design**: Designed with Apple Human Interface Guidelines in mind.
- **Mini Player & Fullscreen Player**: Swipeable mini player with interactive progress bar and immersive fullscreen player view.
- **Dynamic Theming**: Adaptive color palettes, dark mode support, and ambient background styling.
- **iPad Optimized**: Native sidebar navigation and multi-column split views on iPadOS.

---

## 🏛 Architecture & Tech Stack

StoryTeller is built using **Clean Architecture** and modern Swift language features:

```
StoryTeller4/
├── API/              # Network layer, endpoints, Audiobookshelf REST API client
├── Core/
│   ├── Infrastructure/   # Device, networking, storage, and timers
│   ├── Manager/          # AudioPlayer, Preloader, DownloadManager, StateManagers
│   ├── Models/           # Sendable domain and DTO models
│   ├── Repositories/     # Swift Actors for thread-safe data persistence & sync
│   ├── Services/         # Audio, bookmarks, download orchestration, AVPlayer
│   └── UseCases/         # Application business logic (PlayBook, Downloads, etc.)
├── Presentation/
│   ├── ViewModels/       # Observation framework (@Observable) ViewModels
│   └── Views/            # Declarative SwiftUI views (Player, Library, Home, Books)
└── Resources/            # Assets, icons, launch screen
```

### Highlights:
- **Swift 6 & Strict Concurrency**: All models conform to `Sendable`, data persistence runs on thread-safe Swift `actor`s, and UI is strictly bound to `@MainActor`.
- **Observation Framework**: Clean reactive UI binding via `@Observable` without Combine boilerplate or memory leaks.
- **Zero Third-Party Binary Bloat**: Built purely on Apple system frameworks (`AVFoundation`, `SwiftUI`, `Observation`, `MediaPlayer`, `URLSession`).

---

## 🚀 Getting Started

### Prerequisites
- **macOS** 14.0 (Sonoma) or later
- **Xcode** 16.0 or later
- **iOS / iPadOS** 17.0+ deployment target
- A running instance of an [Audiobookshelf](https://www.audiobookshelf.org/) server (v2.x or later)

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/boriseder/StoryTeller4.git
   cd StoryTeller4
   ```

2. Open the project in Xcode:
   ```bash
   open StoryTeller4.xcodeproj
   ```

3. Select your development team under the **Signing & Capabilities** tab of the `StoryTeller4` target.

4. Select your target device or simulator (iPhone / iPad) and press **Run** (`⌘R`).

5. On first launch, enter your Audiobookshelf server URL (e.g. `https://audiobooks.example.com`) and your user credentials to log in.

---

## 📄 License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.

---

<div align="center">
<sub>Crafted for audiobook lovers self-hosting with Audiobookshelf.</sub>
</div>
