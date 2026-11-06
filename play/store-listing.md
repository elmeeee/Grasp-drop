# Google Play listing: Otter (org.otter.app)

Everything below is copy-ready for Play Console.

## App details
- **App name:** Otter
- **Default language:** English (United States)
- **App or game:** App
- **Category:** Tools
- **Tags (optional):** File sharing, Productivity
- **Contact email:** (fill in the address you use for the developer account)
- **Privacy policy URL:** https://otterr.web.app/privacy
- **Website:** https://otterr.web.app

## Store listing
**Short description (80 characters max)**
> Send files between your devices over local Wi-Fi. No cloud, no account.

**Full description**
> Otter moves photos, videos, and documents between your Android phone and your other devices on the same Wi-Fi network. Files go directly from one device to another. They never pass through a server, and there is no account to create.
>
> HOW IT WORKS
> • Open Otter on both devices, on the same Wi-Fi.
> • Otter shows nearby devices. Pick one and choose the files to send.
> • Several files can be sent in one go.
> • Watch live progress for every transfer, in the app and in the notification.
>
> RECEIVING
> • Photos and videos you receive can be saved straight to your Gallery.
> • Other files are saved to Downloads.
> • Received files wait in the Inbox until you save or delete them.
>
> BROWSER ACCESS
> • Otter shows an address you can open in any browser on the same network. From there, a phone, tablet, or computer can upload several files or download files from your phone.
>
> PRIVATE BY DESIGN
> • Transfers are encrypted (HTTPS) between your own devices.
> • Otter collects no personal data, has no analytics or ads, and needs no account.
> • Transfer history stays on your device and can be cleared at any time.
>
> Otter works on Wi-Fi networks where devices can see each other. Some routers and guest networks block device-to-device traffic.

**Release notes (version 1.0.0)**
> First release. Send and receive files with nearby devices on the same Wi-Fi. Live progress, batch sending, a browser web hub, a Gallery-aware inbox, and transfer history.

## Graphics (in play/graphics and play/screenshots)
- App icon, 512 × 512 PNG: play/graphics/icon-512.png
- Feature graphic, 1024 × 500 PNG: play/graphics/feature-1024x500.png
- Phone screenshots, 1080 × 2400 PNG: play/screenshots/01-home.png, 02-web-hub.png

## App content
**Privacy policy:** https://otterr.web.app/privacy

**Ads:** No, the app does not contain ads.

**App access:** All functionality is available without special access. No login is needed.

**Content rating questionnaire:** Answer No to violence, sexual content, profanity, drugs, gambling, user-generated content shared with others, location sharing, and in-app purchases. Expected rating: Everyone.

**Target audience:** 18 and over (or 13 and over). Not designed for children.

**News app / COVID / government / financial / health:** No to all.

**Data safety form**
- Does the app collect or share any user data? **No**.
  - Otter processes files on the device and sends them only to the device the user chooses, over local HTTPS. Transfers are not "collected" by the developer.
- Data encrypted in transit: **Yes** (HTTPS between devices).
- Users can request data deletion: **Yes** (clear history in the app, and delete files from the app or the device).

**Permissions declarations you may be asked about**
- **Foreground service (specialUse):** Keeps Otter reachable while it runs in the background, so nearby devices can send files to this device. Subtype: "Keeps the Otter node reachable so nearby devices can send files to this device."
- **Notifications (POST_NOTIFICATIONS):** Shows live transfer progress and the service status.
- **Multicast (CHANGE_WIFI_MULTICAST_STATE):** Required to discover nearby devices on the local Wi-Fi.
- **Local network (INTERNET):** Transfers go directly between devices on the local network.

## Release checklist
- [ ] Upload play/otter-release.aab to Internal testing first (it is signed with the upload key).
- [ ] Enable Play App Signing when Play offers it, and keep ~/.otter-keys/ backed up.
- [ ] Add testers and run the closed test with 12 testers for 14 days (required for new personal accounts).
- [ ] Confirm target API 36 is accepted in the release overview.
- [ ] Check the pre-launch report for crashes on the test devices.
- [ ] Promote to production.
