---
title: Getting iOS apps
---

# Getting arm64 iOS apps for Perry

Perry runs an app's own Mach-O binary, but the copy the App Store gives you
is encrypted with Apple's FairPlay copy protection: the main executable is
scrambled, and an iPhone or Mac only decrypts it in memory when it launches
the app, with a key tied to your Apple Account. Perry can't run a scrambled
binary, so it needs a decrypted copy of the `.app` folder.

This guide makes that copy on your own Mac, from an app your Apple Account
already owns, with two free command-line tools: **ipatool** downloads the
app and **unfairplay** decrypts it.

## What you need

- A **Mac with Apple Silicon** (M1 or later). In the Apple menu, choose About This Mac:
  the Chip line should say "Apple M…". unfairplay borrows the mechanism
  macOS uses to run iPhone and iPad apps, which only Apple Silicon Macs
  have, so an Intel Mac can't do this.
- Your **Apple Account**, signed in to the App Store on that Mac.
- The app in your purchase history: bought, or "Get" for a free app.
- [Homebrew](https://brew.sh) and Terminal.

This route gives **arm64** binaries only. Apps from before 64-bit iOS
(armv7 and armv6) can't be decrypted this way, because Apple Silicon Macs
only run arm64 iOS apps.

## 1. Install the tools (once)

```sh
# ipatool downloads the copy of the app tied to your account
brew install ipatool

# unfairplay decrypts it; it builds with Go
brew install go
git clone https://github.com/DrWhax/unfairplay.git
cd unfairplay
go build -o unfairplay .
```

Sign ipatool in to your Apple Account once. It asks for your password and
a two-factor code, as the App Store does:

```sh
ipatool auth login -e YOUR_APPLE_ACCOUNT_EMAIL
```

## 2. Teach unfairplay your Mac's decryption (once)

unfairplay learns how your Mac decrypts apps from any iPhone or iPad app
you've installed from the Mac App Store. Install one first: in the App
Store, click your name at the bottom left, choose **iPhone & iPad Apps**,
and download any app you own. Then:

```sh
./unfairplay setup
```

It saves what it learned, so you do this once, however many apps you
decrypt later. After a macOS update you may need to run it again.

## 3. Download and decrypt an app

You need the app's **bundle ID**. For apps already tested, it is under each
app's name in the [compatibility table]({{ '/compatibility/' | relative_url }}).
For others, `ipatool search "App name"` lists the bundle IDs of matching
apps.

```sh
# A free app your account hasn't got yet needs a free "purchase" first
ipatool purchase -b com.example.app

# Download the encrypted copy
ipatool download -b com.example.app -o app-encrypted.ipa

# Decrypt it
./unfairplay decrypt --input app-encrypted.ipa --output app-decrypted.ipa
```

unfairplay prints a short report when it finishes. The line that matters is
`PlaintextVerified: true`. If it says `false`, run `./unfairplay setup`
again and decrypt again.

## 4. Unpack the app and check it

An `.ipa` is a zip file with the app folder inside `Payload/`:

```sh
unzip app-decrypted.ipa -d app
ls app/Payload
```

Check that the main executable is arm64 and no longer encrypted. Its name
is the app's `CFBundleExecutable`:

```sh
APP=app/Payload/Example.app
EXE="$APP/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Info.plist")"
lipo -archs "$EXE"                 # should list arm64
otool -l "$EXE" | grep cryptid     # should show cryptid 0
```

A `cryptid 1` means the binary is still encrypted, and Perry rejects it with
an error.

## 5. Run it with Perry

Copy the `.app` folder to the Linux machine and pass it to `perry`:

```sh
perry path/to/Example.app
```

The [README]({{ site.repository_url }}#quick-start) covers building Perry
and its settings. Many apps need more than the loader: the reports in the
[compatibility table]({{ '/compatibility/' | relative_url }}) say how far
each app gets and what it needs.

## If something goes wrong

- **`PlaintextVerified: false`:** run `./unfairplay setup` again, then
  decrypt again.
- **The decrypt fails outright:** check the Mac is Apple Silicon, and that
  the app is in your account's purchase history.
- **`ipatool download` fails:** sign in again with `ipatool auth login`.
  A free app needs `ipatool purchase` first.
- **`lipo` lists only armv7:** the app is 32-bit and this route can't
  decrypt it.

## Your copy is yours

Decrypt only apps your own Apple Account owns, on your own Mac, for your
own use. The decrypted copy is tied to your account: don't share it, and
don't upload it to an issue, a pull request or anywhere else. Reports in
this repository link screenshots, never app files.
