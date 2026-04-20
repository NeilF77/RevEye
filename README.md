# RevEye

RevEye is an iOS app I built for my final year project at TU Dublin. It identifies cars from photos, and when you upload a video it also captures the engine audio and saves it to a public dataset that researchers can use. All the identification happens on the phone itself, so it works without an internet connection.

## The idea

The whole thing started from a simple problem. I like cars, and like a lot of people I'd see something interesting in a car park or driving past and have no idea what it was. Most people can recognise a Ferrari or a Mustang, but telling an Audi S5 Coupe apart from an Audi TT Coupe, or spotting a rare import, is much harder.

Shazam solved this for music twenty years ago — one tap, any song, anywhere. I wanted to build that same experience for cars, but I also wanted it to work offline so you could use it anywhere, even without signal.

While researching the area I noticed something else. There are image-based car classifiers out there, but there are no audio-based ones. The reason is pretty simple — nobody has published a public dataset of labelled car engine sounds. Without training data, no one can train a model. So I decided the app should do more than just identify cars. Every time someone uploads a video of a car, RevEye pulls the audio out, asks the user a few quick questions about it (was the engine audible, was the car accelerating, how noisy was the background), and adds it to an open dataset anyone can download and use.

That dataset is the actual research contribution. The app is the way it gets built.

## How it works

You point your phone at a car, tap the scan ring, and the app classifies it using a machine learning model stored on the device. The model is an EfficientNet-B4 convolutional neural network, trained on the Stanford Cars dataset which covers 196 different makes and models. Classification runs in under 200 milliseconds, all on the phone, no server involved.

If the model isn't sure — say it's only 34% confident — the app shows a correction screen with its top three guesses, and you pick the right one or save it as unknown. That correction gets logged so future versions of the model can learn from it.

If you upload a video instead of a photo, the app samples multiple frames, classifies each one, and picks the most common prediction (a technique called consensus voting that handles shaky footage better than single-frame classification). It also extracts the audio from the video using AVFoundation. Before the audio gets uploaded, you're asked a short series of questions to tag it — this is what makes the data useful as training material later.

To keep people contributing, the app has a gamification layer built on top. There are 22 badges across six categories (first scan, audio contributions, streaks, variety of makes, and so on), a "Garage" tab where you collect the cars you've identified, and progress bars showing how close you are to each unlockable badge. The gamification isn't just decorative — the whole point of the app is sustained contribution to the dataset, so users needed a reason to keep coming back.

Everything syncs to Firebase in the background, but the app is built offline-first. You can scan cars all day with no signal and everything uploads quietly when you reconnect.

## What I built

The app is about 6,200 lines of Swift across 30 files, using the MVVM architecture pattern. The ML training pipeline is Python using PyTorch, which I then converted to Core ML for use on iOS. The public dataset website is a static site on GitHub Pages that reads directly from Firebase Firestore and lets you filter by make, vehicle state, noise level, and engine audibility.

The training itself went through a few iterations. My first attempt used Apple's Create ML and plateaued at 22% accuracy, which was nowhere near usable. I pivoted to PyTorch with EfficientNet-B4, added custom video augmentation (motion blur, JPEG compression, random erase) in a second training phase, and ended up at 86.6% accuracy on the test set — well above the 75% target I'd set. Top-5 accuracy came out at 97.4%, meaning the correct answer is in the top three or four guesses almost every time.

User testing with eight participants using a think-aloud protocol gave the app a System Usability Scale score of 75.4, which is above the "good" threshold of 68. All eight participants completed every task, and the issues they raised during testing (the badge card wasn't obviously tappable, the correction flow wasn't clear) were all fixed and re-tested before submission.

## The dataset

The public dataset lives at [neilf77.github.io](https://neilf77.github.io). Every audio sample uploaded from the app appears on that site, filterable by make, vehicle state, audibility, and noise level, and playable directly in the browser. Anyone can use it for research — audio classification, pedestrian safety research around silent electric vehicles, urban noise monitoring, accessibility tooling. The whole point is that the data was missing, so I've tried to make it as easy as possible to access.

## Running it

The project isn't on the App Store yet. If you want to run it yourself, you'll need Xcode 15 or newer, an iOS 17+ device or simulator, and a Firebase project of your own with Email/Password auth and Firestore enabled. Drop your own `GoogleService-Info.plist` into the project, set your signing team, and build. The full Xcode project is in this repository.

## What's next

A few things I'd have built if I'd had more time, and which I'll probably keep working on:

Train the audio classifier itself, once the dataset is big enough. The whole app was designed around collecting this data, so the next step is actually using it.

Real-time camera classification, so you just point the phone and see predictions live instead of taking a photo. This needs a smaller model or Neural Engine optimisation to hit 100ms inference.

A proper first-run onboarding flow. I built one during the project but had to pull it before submission because the trigger logic didn't work reliably for new users on a shared device.

App Store release. TestFlight has been fine for testing but limits how many people can contribute to the dataset.

Multi-modal classification combining image and audio predictions, once the audio side exists.

## Credits

Supervisor: Emma Murphy, School of Computer Science, TU Dublin. Thank you to the eight user-testing participants who gave up their time.

The app is built on top of work by a lot of other people — the Stanford Cars dataset from Jonathan Krause and colleagues, the EfficientNet architecture from Mingxing Tan and Quoc Le, the `timm` library from Ross Wightman, Apple's `coremltools`, and the Firebase iOS SDK. Without any of those this project would have been impossible.

## Author

**Neil Fitzgerald**
BSc (Hons) Computer Science · TU856 · TU Dublin
Student ID: C22405604
Final Year Project 2025–2026

