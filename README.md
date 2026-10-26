# 🚀 Android Ultimate Flasher

> **Version:** 1.1  
> **Crafted by:** Rudra (`rudra1212a`)  
> **Platform:** Termux (Android)

A professional, safety-first Android flashing and device management tool designed for Termux. It features built-in device validation, bootloader gates, and a classic interactive UI to make flashing operations secure and reliable.

---

## ✨ Features

- **🛡️ Safety First:** Automatic checks for bootloader unlock status and device model matching before running any flash commands.
- **📦 Fastboot ROM Preview:** Safely inspect package contents and verify compatibility without blind auto-flashing.
- **⚡ Flash Images:** Easily flash individual `.img` files (boot, recovery, vbmeta, dtbo, etc.) to target partitions.
- **📱 ADB Sideload:** Install custom ROMs or update packages via `.zip` files in recovery mode.
- **🔄 A/B Slot Management:** Check active slots and switch between Slot A and Slot B seamlessly.
- **🛠️ Device Tools:** Factory reset/wipe user data, advanced reboot options (System, Recovery, Bootloader), and live tool logs.
- **🎨 Classic UI:** Clean terminal user interface with status indicators for fastboot, adb, python, and device connection.

---

## 📥 Installation

You can install the tool instantly in Termux with a single one-liner command. Just copy and paste the command below into your terminal:

```bash
 rm -rf \~/.android-ultimate-flashing-tool $PREFIX/bin/rudra
mkdir -p \~/.android-ultimate-flashing-tool
curl -fsSL https://raw.githubusercontent.com/rudra1212a/android-ultimate-flasher/main/setup.sh -o \~/.android-ultimate-flashing-tool/setup.sh
chmod +x \~/.android-ultimate-flashing-tool/setup.sh
bash \~/.android-ultimate-flashing-tool/setup.sh
```

🚀 Usage

Once the installation is complete, you can launch the tool from anywhere in Termux by simply typing:

```bash
rudra
```

📋 Requirements


• Termux app installed on Android.

• adb and fastboot binaries installed in Termux.

• USB Debugging enabled on your target Android device with proper USB-OTG connection.


⚠️ Disclaimer

Flashing custom firmware carries risks of device bricking. Always verify your device model, firmware compatibility, and ensure your bootloader is unlocked. The author (Rudra) will not be responsible for any damage to your device.


⭐ If you find this tool useful, please give it a star on GitHub!
