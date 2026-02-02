# RevEv - Engine Sound Simulator for EVs

A native iOS app that simulates realistic V8 engine sounds for electric vehicles using real-time OBD-II data via Bluetooth.

## Features

- **Real-time OBD-II Connection**: Connect to your EV via Bluetooth ELM327 adapter
- **Dynamic Engine Sounds**: V8 sounds that respond to actual motor RPM
- **Multiple Engine Profiles**: BAC Mono, Ferrari 458, ProCar Racing
- **Cyberpunk UI**: Neon-styled dashboard with animated RPM gauge
- **Demo Mode**: Test audio without vehicle connection
- **Auto-Connect**: Automatically reconnects to last known OBD adapter

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Bluetooth ELM327 OBD-II adapter (for live data)
- Compatible EV (Hyundai Ioniq 5, Kia EV6, or other E-GMP platform vehicles)

## Setup

1. Open `RevEv.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on your iOS device

## Project Structure

```
RevEv/
├── RevEvApp.swift              # App entry point
├── Models/
│   ├── EngineConfiguration.swift   # Sound configs
│   └── OBDData.swift               # OBD data models
├── Services/
│   ├── Audio/
│   │   └── AudioEngine.swift       # AVAudioEngine wrapper
│   └── Bluetooth/
│       ├── BluetoothService.swift  # CoreBluetooth manager
│       ├── BluetoothConstants.swift # UUIDs & commands
│       └── OBDParser.swift         # Response parsing
├── ViewModels/
│   └── DashboardViewModel.swift    # Main state manager
├── Views/
│   ├── DashboardView.swift         # Main UI
│   ├── Components/                 # Reusable UI components
│   └── Settings/                   # Settings screen
├── Utilities/
│   └── MathUtils.swift             # Math helpers
└── Resources/
    ├── Assets.xcassets             # Colors & icons
    └── Sounds/                     # Engine audio samples
```

## How It Works

### Audio Engine
- Uses AVAudioEngine with AVAudioPlayerNode for looped sample playback
- AVAudioUnitTimePitch for real-time pitch shifting based on RPM
- Equal-power crossfade between low/high RPM samples
- Throttle-based crossfade between on/off throttle samples

### Bluetooth OBD-II
- CoreBluetooth for ELM327 adapter connection
- Supports Veepeak, OBDLink, and generic adapters
- Polls RPM at 20Hz (50ms intervals)
- Auto-reconnect on connection loss

### Throttle Detection
- EVs don't have traditional throttle position
- Throttle inferred from RPM rate of change
- Positive delta = accelerating (throttle on)
- Negative/zero delta = coasting (throttle off)

## Supported OBD PIDs

| PID | Description | Vehicles |
|-----|-------------|----------|
| 220101 | Motor RPM | E-GMP (Ioniq 5, EV6) |
| 2101 | Motor RPM | Kona EV, Niro EV |
| 010C | Engine RPM | ICE vehicles |

## License

MIT License - See original engine-audio project for audio sample licensing.

## Credits

- Engine audio simulation ported from [engine-audio](../engine-audio)
- UI inspired by cyberpunk aesthetics
