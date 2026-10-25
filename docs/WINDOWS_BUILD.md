# Building Stock Pilot for Windows

Stock Pilot can run as a native Windows desktop application. Here's how to build and distribute it.

## Option 1: Build via GitHub Actions (Recommended)

Since Flutter cannot cross-compile from macOS to Windows, use GitHub Actions to build automatically.

### Building

1. Push your code to the `main` or `master` branch, OR
2. Go to **Actions** tab → **Build Windows Release** → **Run workflow**

### Downloading the Build

1. Go to **Actions** tab
2. Click on the latest successful workflow run
3. Scroll down to **Artifacts**
4. Download `StockPilot-Windows.zip`

### Installing on Windows

1. Extract `StockPilot-Windows.zip`
2. Double-click `stock_pilot.exe`
3. The app opens! ✅

> **Note:** Windows may show a "Windows protected your PC" warning. Click "More info" → "Run anyway".

---

## Option 2: Build on a Windows Machine

If you have access to a Windows PC:

```bash
# Clone the repo
git clone <your-repo-url>
cd stock_pilot

# Get dependencies
flutter pub get

# Build
flutter build windows --release

# Output will be at:
# build/windows/x64/runner/Release/
```

Zip the `Release` folder and distribute.

---

## App Requirements

- Windows 10 or Windows 11 (64-bit)
- No installation required - just extract and run
- Internet connection (for Supabase sync)

## Included Files

The Windows build includes:
- `stock_pilot.exe` - The main application
- `flutter_windows.dll` - Flutter engine
- `sqlite3.dll` - SQLite database engine
- `data/` folder - App assets and code

**All files must stay together in the same folder!**