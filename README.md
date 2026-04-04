# OllamaHub

A native macOS app for browsing, downloading, and managing Ollama models. No more memorizing model names or typing `ollama pull` commands — just search, click, and go.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## What It Does

OllamaHub connects to the [Ollama model library](https://ollama.com/library) and your local Ollama installation, giving you a single window to:

- **Browse** all 200+ models from Ollama's registry
- **Search** by name or description
- **Pick a size** — click the parameter badge (1B, 7B, 70B, etc.) to choose exactly which variant to pull
- **Download with one click** — streams directly through your local Ollama with a live progress bar
- **Manage cloud models** — browse Ollama's cloud-hosted models in a dedicated tab
- **Delete models** — see what's installed, how much space each model uses, and remove what you don't need

## Install

### Build from Source

Requires Xcode 15+ and macOS 14 (Sonoma) or later.

```bash
git clone https://github.com/rynky2436/OllamaHub.git
cd OllamaHub
xcodebuild -project OllamaHub.xcodeproj -scheme OllamaHub -configuration Release build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/OllamaHub-*/Build/Products/Release/OllamaHub.app`.

Or just open `OllamaHub.xcodeproj` in Xcode and hit Run.

### Prerequisites

- [Ollama](https://ollama.com/download) must be installed and running locally
- The green "Ollama Running" indicator in the app confirms the connection

## Usage

1. **Launch OllamaHub** — models load automatically from ollama.com
2. **Search** — type in the search bar to filter by name or description
3. **Pick a size** — click a blue parameter badge (e.g., `7B`, `70B`) to select that variant
4. **Pull** — click the Pull button. Progress shows inline with size downloaded and percentage
5. **Switch tabs** — use All / Local / Cloud / My Models to filter the view
6. **Delete** — go to My Models tab, click Delete on any model you want to remove

## Tabs

| Tab | What it shows |
|-----|--------------|
| **All** | Every model in the Ollama registry |
| **Local** | Models with downloadable parameter sizes |
| **Cloud** | Models available through Ollama's cloud hosting |
| **My Models** | Your installed models with storage usage and delete option |

## How It Works

- Fetches the model catalog by parsing [ollama.com/library](https://ollama.com/library)
- Communicates with your local Ollama instance via its REST API on `localhost:11434`
- Downloads use `POST /api/pull` with streaming NDJSON for real-time progress
- Deletes use `DELETE /api/delete`
- Models are stored wherever your Ollama installation keeps them (default: `~/.ollama/models`)
- Zero third-party dependencies — pure SwiftUI + Foundation

## Project Structure

```
OllamaHub/
  OllamaHubApp.swift      App entry point
  ContentView.swift        Main UI, view model, tab logic
  ModelRowView.swift       Individual model row with size selection + pull button
  Models.swift             Data types for API responses and app state
  OllamaService.swift      API client for ollama.com and local Ollama
  Info.plist               ATS config for localhost HTTP
  OllamaHub.entitlements   App sandbox + network client
```

## License

MIT
