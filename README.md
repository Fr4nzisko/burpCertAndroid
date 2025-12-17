# BurpSuite Cert for Android Installer

## v3.0.1

## About
This is an automated script for install BurpSuite certificate in Android devices.

## Key Improvements in v3.0.0

### 🚀 Enhanced Cross-Platform Compatibility
- **Full macOS support**: Now works seamlessly on both Linux and macOS systems
- **Universal ADB detection**: Automatically finds ADB in common macOS locations (`/usr/local/bin/adb`, `~/Library/Android/sdk/platform-tools/adb`)
- **Portable process checking**: Uses compatible methods for detecting running processes on both platforms

### 🎨 Visual Improvements
- **Color-coded output**: Enhanced readability with consistent color scheme throughout the script
- **Better user feedback**: Clear visual indicators for success (green), warnings (yellow), and errors (red)
- **Improved formatting**: Cleaner console output with proper spacing and section separation

### 🔧 Technical Enhancements
- **Robust BurpSuite detection**: Multiple detection methods including process name patterns and port checking
- **Smart error handling**: Graceful fallbacks when root access is not available
- **Device type detection**: Automatically identifies Android Studio emulators, Genymotion, physical devices
- **Multiple root method support**: Handles `adb root`, `su -c`, and `su 0` syntax variations

### 🛡️ Reliability Features
- **Certificate verification**: Validates certificate installation at each step
- **Cleanup routines**: Automatically removes temporary files
- **User certificate fallback**: Offers alternative installation method when root is unavailable
- **Interactive prompts**: Asks for confirmation when critical checks fail

### 📱 Device Management
- **Multi-device support**: Lists all connected Android devices for selection
- **IP address detection**: Automatically extracts device IP for proxy configuration
- **Root access testing**: Verifies root permissions before attempting system install

## Setup your proxy in bash

```bash
alias adb_set_proxy="adb -s <deviceIP>:5555 shell settings put global http_proxy $(ip -o -4 addr show <interfaceNetwork> | awk '{print $4}' | sed 's/\/.*//g'):8080"
```
```bash
alias adb_unset_proxy='adb -s <deviceIP> shell settings put global http_proxy :0'
```
- **deviceIP**: Android IP Address.
- **interfaceNetwork**: Network interface where your local IPv4 address is located.

## Installation Requirements
### macOS:
```bash
brew install android-platform-tools openssl
```
### Linux (Debian/Ubuntu):
```bash
sudo apt install adb openssl
```

## Usage
Simply run the script with BurpSuite running and at least one Android device connected:
```bash
./install_burp_cert.sh
```

https://lautarovculic.com

**Modified by: Jose Francisco Flores (Fr4nzisko)** - For macOS/Linux compatibility
