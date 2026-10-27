# 📱 Running Karbar POS in an Android Virtual Machine (Emulator / AVD)

This guide outlines how to configure, set up, and run the **Karbar Mobile Point of Sale** app inside an Android Virtual Device (AVD) / Virtual Machine.

---

## 1. Prerequisites

Make sure you have the following installed:
- **Flutter SDK** (`^3.12.2` or later)
- **Android Studio** with **Android SDK** and **Android Emulator** components installed
- **Java Development Kit (JDK)** (bundled with Android Studio)

---

## 2. Setting up an Android Virtual Device (AVD)

1. Open **Android Studio**.
2. Navigate to **Tools > Device Manager** (or click the Device Manager icon on the side toolbar / welcome screen).
3. Click **Create Device**.
4. Choose a hardware definition suitable for a POS terminal or tablet/phone:
   - **Recommended:** *Pixel 6* or *Tablet* (e.g., *Pixel C* or *Nexus 10* for landscape/tablet POS layouts).
5. Select a system image (API level 33 or 34 recommended, e.g., **Tiramisu** or **UpsideDownCake** with Google APIs).
6. Click **Finish** to generate the AVD.

---

## 3. Launching the Virtual Machine (Emulator)

You can launch the AVD using any of the following methods:

### Option A: From Android Studio Device Manager
1. Open **Device Manager**.
2. Locate your created virtual device and click the **Play (▶)** button.

### Option B: From Terminal / CLI
List available emulators:
```bash
emulator -list-avds
```
Launch a specific AVD:
```bash
emulator -avd <Your_AVD_Name>
```

---

## 4. Running the App in the Virtual Machine

Once the emulator is running and fully booted:

### Using Android Studio
1. Select **Karbar POS (Android Emulator / VM)** from the run configuration dropdown in the top toolbar.
2. Ensure your running emulator is selected as the target device.
3. Click the **Run (▶)** button or press `Shift + F10`.

### Using VS Code
1. Open the **Run and Debug** panel (`Ctrl + Shift + D` / `Cmd + Shift + D`).
2. Select **Karbar POS (Android Emulator / Virtual Machine)**.
3. Press `F5`.

### Using Terminal (Flutter CLI)
```bash
flutter run
```
*(Flutter will automatically detect the running emulator and deploy the app).*

---

## 5. Troubleshooting Virtual Machine Performance

- **Enable Hardware Acceleration (HAXM / KVM / WHPX):** Ensure virtualization extensions (Intel VT-x, AMD-V, or Hyper-V) are enabled in your host machine's BIOS/UEFI.
- **Cold Boot:** If the emulator hangs or has state issues, cold boot it via Device Manager (`...` menu > **Cold Boot Now**).
