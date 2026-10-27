# StudioViewer privacy policy

*Last updated 26 October 2026.*

StudioViewer runs on your Mac and shares your Capture One session with browsers you choose. It
has no accounts, no analytics, no ads and no crash reporting. **Nothing is ever sent to Faini
Made.** What it does keep, and the few times it goes online, are listed below.

## On your Mac

- **Your settings** are kept in StudioViewer's preferences and in
  `~/Library/Application Support/StudioViewer/settings.json`: the rating mode and PIN, the
  wrong-guess limits, the remote viewing code, how visitors' pages name you, and the devices
  you've removed (see below).
- **Your Cloudflare tunnel token**, if you add one, is kept in your Mac's Keychain. Only its
  tunnel ID (not secret) is kept in the preferences.
- **Capture One:** StudioViewer talks to Capture One on this Mac only. To show exposure details it
  reads your session's database file, without changing it.
- **The Log panel** is kept in memory and cleared when StudioViewer quits. It's only shared if you
  copy it yourself. It never contains your tunnel token.
- **Notifications** are shown on this Mac only.

Deleting the app, its folder in Application Support and
`~/Library/Preferences/Faini-Made.StudioViewer.plist` removes all of this; the tunnel token can be
deleted in Keychain Access.

## About the people who watch

The viewer keeps track of the browsers watching, for the **Viewers** panel. For each one it
records:

- what kind of device and browser it is (from the browser's own description of itself),
- its IP address,
- the folder and photo it's on, how many ratings and tags it has set, how much the viewer has sent
  it, and when it connected,
- for people watching from outside the studio, whatever Cloudflare passes on: their country, and if
  your Cloudflare settings add them, their city, region and rough coordinates, and the email
  address they signed in with if you protect your address with Cloudflare Access.

This is held in memory only, and forgotten an hour after the browser leaves (or when the viewer
stops). The exception is a device **you remove**: its name, IP address, email (if any) and the
time are saved in `settings.json` so it stays out, until you unblock it.

Each browser gets cookies from the viewer: a random device ID (kept a year) so the Viewers panel
can tell devices apart, and, once someone enters the PIN or viewing code, a cookie that remembers it
(kept 30 days). Cookies go only to the viewer on your Mac. The viewer page also remembers its own
layout, filters, last folder and overlay image in that browser's storage, which never leaves the
browser.

As the person running StudioViewer, you decide who can watch, and you're responsible for the
information above about the people you invite.

## When StudioViewer goes online

- **Remote sharing** (off until you switch it on): StudioViewer runs Cloudflare's `cloudflared`,
  which connects your Mac to Cloudflare. Everything remote visitors see, the photos included,
  passes through Cloudflare, under [Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/).
  With a temporary link, the address is on Cloudflare's trycloudflare.com.
- **Checking for StudioViewer updates:** when you press **Check for Updates…**, or once a day if you
  switch on automatic checks, StudioViewer asks GitHub for the latest release.
- **Keeping cloudflared current:** when you open the **Remote Sharing** panel, at most once an hour,
  StudioViewer asks GitHub for the latest cloudflared release. It downloads it only when you press
  **Update**.

These requests carry only what any web request does (your IP address, and the app's name and
version), nothing about you, your settings or your photos. [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement)
applies to them.

Links in the app open in your browser only when you click them: Faini Made's site, Buy Me a Coffee,
the Cloudflare dashboard, the websites of the open-source software it includes, Apple Maps (to show
where a remote visitor roughly is) and ipinfo.io (to look up a remote visitor's IP address).

## Changes and contact

If StudioViewer starts storing or sending anything new, this page will say so before that release.
Questions: [fainimade.com](https://fainimade.com).
