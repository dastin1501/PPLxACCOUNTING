# POS Stock Manager

A simple Flutter point-of-sale companion app for managing stock/inventory.
For now it focuses on full **CRUD for stock items** (Create, Read, Update,
Delete), with a tablet-friendly layout, designed to run on an Android tablet.

## Features

- Add new stock items (name, SKU/barcode, category, quantity, unit, selling
  price, cost price, low-stock threshold)
- View all stock items in a searchable list (search by name, SKU, or category)
- Edit existing stock items
- Delete stock items (with a confirmation dialog)
- Low-stock warning badges (item row + header chip count)
- Data is persisted locally on-device with SQLite (via `sqflite`), so it
  works fully offline — good for a tablet at a store counter
- Responsive layout: master-detail two-pane view on wide/tablet-landscape
  screens, single-pane with full-screen form on narrower/portrait screens

## Project structure

```
lib/
  main.dart                    App entry point, theme
  models/
    stock_item.dart            StockItem data model
  services/
    database_helper.dart       SQLite CRUD (sqflite)
  screens/
    home_screen.dart           Master-detail screen (list + form)
  widgets/
    stock_form.dart            Add/Edit form
    stock_list_tile.dart       Single row in the stock list
```

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.44+ / Dart 3.12+)
- Android SDK / Android Studio (for building the tablet APK)
- A tablet with **USB debugging enabled**, or an emulator

Check your setup any time with:

```bash
flutter doctor
```

### Run in debug mode (fastest way to try it)

1. Connect your Android tablet via USB (accept the "Allow USB debugging?"
   prompt on the tablet) or start an emulator.
2. Confirm Flutter sees the device:

   ```bash
   flutter devices
   ```

3. Run the app:

   ```bash
   flutter run
   ```

   Flutter will install and launch the app directly on the connected tablet.

### Build an installable APK for the tablet

```bash
flutter build apk --release
```

The APK will be generated at:

```
build/app/outputs/flutter-apk/app-release.apk
```

Copy that file to the tablet (via USB cable, email, cloud drive, etc.),
open it on the tablet, and allow "Install unknown apps" for the file
manager/browser you use to open it. Then install as usual.

Alternatively, with the tablet connected over USB, you can install directly
without copying files:

```bash
flutter install
```

### Run the tests / static analysis

```bash
flutter analyze
flutter test
```

## Notes on the data

- Stock data is stored in a local SQLite database on the device
  (`pos_app.db`), so it persists between app restarts but is specific to
  that tablet/device. There's no cloud sync yet — this can be added later
  (e.g. Firebase, or a REST backend) once the core POS features grow beyond
  stock management.
- SKU values must be unique across items; the form will flag duplicates.

## Roadmap ideas (not implemented yet)

- Sales / checkout screen that decrements stock quantities
- Stock movement history / audit log
- Barcode scanning via the tablet camera
- Multi-user / login support
- Cloud backup & sync across devices
