# LfS Web Viewer

See your Capture One shoot live in any web browser, on this Mac, on a client monitor, or on a
phone, tablet or laptop in the studio. No iPad app needed.

Capture One's **Live for Studio** feature shares your session with the Live for Studio iPad app.
LfS Web Viewer connects to that same feature and shows it in a web browser instead, so anyone
on your network can follow along, zoom in to check focus, and (if you allow it) rate and
color-tag photos.

*Made by [Faini Made](https://fainimade.com).*

---

## Contents

1. [What you need](#what-you-need)
2. [Starting the viewer](#starting-the-viewer)
3. [The LfS Viewer app](#the-lfs-viewer-app)
4. [The first time only](#the-first-time-only)
5. [Opening it on a phone, tablet or another computer](#opening-it-on-a-phone-tablet-or-another-computer)
6. [Finding your way around](#finding-your-way-around)
7. [Showing it to a client (fullscreen mode)](#showing-it-to-a-client-fullscreen-mode)
8. [Sharing outside the studio (remote clients)](#sharing-outside-the-studio-remote-clients)
9. [Who can rate and tag](#who-can-rate-and-tag)
10. [Keyboard shortcuts and touch gestures](#keyboard-shortcuts-and-touch-gestures)
11. [If something goes wrong](#if-something-goes-wrong)
12. [Good to know](#good-to-know)
13. [For the technically minded](#for-the-technically-minded)

---

## What you need

- **A Mac with Capture One**, with your session open. (Tested with Capture One 16.7.3.)
- **Live for Studio turned on** in Capture One (see step 1 below).
- **The LfS Viewer app** (macOS 15 or later), or **this folder** with the double-click launcher.
  The folder can live anywhere, for example in Google Drive or your Documents folder.
- **Python 3**, only for the double-click launcher: the app has its own built in. Most Macs already
  have it. If yours doesn't, macOS offers to install it the first time. See
  [The first time only](#the-first-time-only).
- To view on a phone, tablet or another computer: **the same Wi-Fi or network as the Mac**.

---

## Starting the viewer

Do this each time you want to use the viewer.

1. **In Capture One, turn on Live for Studio.** Open your session, find the **Live for Studio**
   tool, choose the folder you want to share, and click **Start Sharing**. The viewer shows
   exactly what you share here.

2. **Start the viewer**, in one of two ways:

   - **With the LfS Viewer app** (easiest): click its icon in the menu bar (an eye) and switch on
     **LfS Viewer**. Or open the window and click **Start**. The switch shows "Live" once Capture One
     answers. To stop, switch it off.
   - **With the double-click launcher:** double-click `Start LfS Viewer.command` in this folder. A
     Terminal window opens (a plain window with text in it) and a moment later your web browser opens
     the viewer. **Leave the Terminal window open** while you use the viewer (you can minimize it);
     **close it when you're done**, which stops the viewer.

> **Tip:** You can start the viewer before Capture One. It says "Waiting for Capture One…" and
> connects by itself once Live for Studio is on.

---

## The LfS Viewer app

The app runs the viewer for you and lives in the **menu bar**. Its menu:

| Item | What it does |
|---|---|
| **LfS Viewer** switch | Starts or stops the viewer. Under it: Live, how many are watching and the session name. |
| **Share Outside the Studio** switch | Remote sharing on or off (once it's set up; see [Sharing outside the studio](#sharing-outside-the-studio-remote-clients)). Under it: your address and how many are watching remotely. |
| **Open Viewer in Browser** (⌘O) | Opens the viewer on this Mac. |
| **Addresses** | Each address to give other devices, to copy, show as a QR code, or open. |
| **Open LfS Viewer Window** | The window, below. |

**The window** has the big **Start / Stop** button and status at the top, and these panels on the left:

| Panel | What's in it |
|---|---|
| **Addresses** | The addresses for phones, tablets and other computers, each with **Copy**, **Open** and a **QR code** to scan (with a fullscreen option for a client screen). |
| **Viewers** | Every browser watching right now: what it is, where it's from (remote visitors: IP and rough location, with a map), the folder and photo it's on, how long, what it has rated, and how much the viewer has sent it. Then those that left in the last hour. **Remove** shuts one out; **Unblock** lets it back. |
| **Remote Sharing** | Sharing outside the studio through Cloudflare, and the viewing code. |
| **Ratings & Tags** | Who else can rate and tag, the PIN, and how many wrong PINs are allowed. See [Who can rate and tag](#who-can-rate-and-tag). |
| **Settings** | Start the viewer when the app opens, open at login, the Dock icon, the port, "only this Mac", what visitors' pages call you, and notifications. |
| **Log** | What the viewer has been doing, with **Copy Log** for asking for help. |
| **About** | Version, **Check for Updates…**, the software policy and the privacy policy. |

Closing the window leaves the app running in the menu bar. It sends a **notification** if Capture One
stops answering, if the viewer stops unexpectedly (with a **Restart** button), if someone keeps guessing
the viewing code, or if remote sharing drops.

---

## The first time only

macOS may ask a few questions the first time. Here's what to click:

| macOS says… | Click |
|---|---|
| "Start LfS Viewer.command" **can't be opened** or is from an **unidentified developer** | **Right-click** the file, choose **Open**, then click **Open** again. After that, a normal double-click works. |
| Terminal would like to access files in **Google Drive** (or another folder) | **Allow** |
| Do you want **python3** to accept **incoming network connections**? | **Allow**. This lets phones and other computers reach the viewer. |
| The **"python3" command requires the command line developer tools.** Install them now? | **Install**, wait for it to finish (a few minutes), then double-click the launcher again. |

---

## Opening it on a phone, tablet or another computer

**With the app:** open the **Addresses** panel (or the menu bar icon › **Addresses**). Scan the
**QR code** with the phone's camera, or type the address.

**With the launcher:** when the viewer starts, the Terminal window lists its addresses, for example:

```
  On this Mac:      http://localhost:8787
  On your network:  http://192.168.8.185:8787   (en15)
  Apple devices:    http://Faini-book-14.local:8787
```

On the other device:

1. Make sure it's on the **same Wi-Fi or network** as the Mac.
2. Open its web browser (Safari, Chrome…) and type one of the **On your network** addresses, or
   the **Apple devices** address on an iPhone or iPad. Your numbers and name will be different
   from the example: use the ones in *your* app or Terminal window.

> **Tip for iPhone and iPad:** after opening the viewer, tap **Share → Add to Home Screen**.
> It then opens full-screen from its own icon, like an app.

Other devices can **look but not rate or tag** unless you allow it. See
[Who can rate and tag](#who-can-rate-and-tag).

---

## Finding your way around

**Hover labels:** rest the mouse on any button for a moment (or tab to it with the keyboard) and a
small label says what it is, with its shortcut key shown as a key cap. Stars say what a click does
("Rate 3 stars", "Clear rating"). Touch screens have no hover, so the tour below covers them.

**The intro tour:** the first time a browser opens the viewer, a short tour lights up each part of the
screen in turn and says what it does (it adapts to the device: no keyboard hints on a touch screen,
no overlay step on a phone). **Back** and **Next** move through it, **Esc** or **Skip tour** ends it,
and the arrow keys work too. Tick **Don't show this again** and it never starts by itself in that
browser; on the last step the box is already ticked, so finishing the tour is enough. Leave it
unticked when you skip and it comes back next visit. To play it again, use **☰ > Take the tour…**.
It doesn't appear in fullscreen mode, so a client monitor never sees it.

**The connection panel:** click the **Live** light for a small panel saying how this page is
connected, so a slow picture can be put down to the link or to Capture One. It shows the session
name; whether you're on this Mac, your network or remote; **when the last update arrived**; the
**response time** to the viewer (fast, fair or slow, with a ping every few seconds while the panel is
open and none otherwise); your connection as the browser reports it (Chrome and Edge only); **how
much data this page has received**, with the number of pictures and how many came from the browser's
cache; and how many pictures **Capture One drew** (and how long it took, on average) against how many
the viewer sent **from its memory**. If the link is slow but Capture One is quick, or the other way
round, it says so. The figures are for this browser tab since it was opened, and the panel shows
nothing about other devices.

**The top bar**, from left to right:

| Button | What it does |
|---|---|
| **▯ (panel icon)** | Shows or hides the list of folders, each with how many photos it holds, and at the bottom, centered, how many folders hold photos (a parent like "Capture" counts only if it has photos of its own). Drag the dotted grip on its edge to make it wider. On a phone, the folder list slides in over the photo. |
| **● Live** | Green when connected to Capture One, red if the connection is lost. **Click it** (or use **☰ > Connection details…**) for the connection panel, described below. |
| **Follow** | Right after the dot. A pill that is outlined with an empty dot when off, and filled amber with a solid dot when on: then the viewer jumps to each new photo as you shoot. |
| **Compare** (two panes) | Shows two photos side by side. See [Comparing two photos](#comparing-two-photos). |
| **Pin** | Sets the selected photo as the one to compare against. |
| **Grid** (four squares) | Switches between one big photo and a grid of thumbnails. |
| **Filter** (three lines, getting shorter) | Shows or hides the sort and filter bar. A small dot on the button means a filter is on. |
| **Overlay** (two overlapping squares; computers and tablets) | Lays a picture of your own (a PNG with a transparent background, or a JPG) over the photo. The first time it asks for the picture; after that it shows the overlay with its tool box: opacity, lock in place, fit to photo, replace, hide and remove. Drag the overlay to move it, drag a corner to scale it. The tool box also pops up while you point at (or tap) the overlay. The picture stays in your browser. |
| **☰ (menu)** | Filmstrip position and show/hide, exposure info, image background, aspect-ratio frame and overlay image (computers and tablets), network access, fullscreen mode, connection details, the intro tour, keyboard shortcuts and About. |

**Under the photo**, laid out as in Capture One: ISO, shutter speed and aperture on the left, the
file name in the middle, and the color tag and star rating on the right. Below that is the **filmstrip**. Rated photos show
their stars, and tagged photos a small colored square.

### Looking at photos

- **Next and previous photo:** click a thumbnail, use the **arrow keys**, or on a touch screen
  **swipe** left and right. The photo slides with your finger and the next one slides in beside
  it; a short quick flick counts too. At the first or last photo it springs back instead.
- **Check focus at 100%:** **double-click** (or **double-tap**) the photo. Drag to move around,
  and double-click again to see the whole photo. Only the part you're looking at is loaded, so
  this is quick even with 100-megapixel files.
- **Follow the shoot:** with **Follow** on, each new capture appears as soon as Capture One has it,
  even if it lands in a different folder from the one you're looking at: the viewer switches to
  that folder for you. Turning Follow on jumps straight to your latest capture. You can still
  browse other folders while Follow is on; the next new capture brings you back. Capture One's own
  **Trigger Follow** button does the same as pressing **Follow** on every open viewer at once: it
  turns Follow on and jumps to the latest capture, whether Follow was on or not.
- **Grid view:** shows all photos with their stars and color tags. Click one to see it large.

### Rating and color tags

- **Rate:** click a star under the photo, or press **1** to **5** on the keyboard. Click the same
  star again (or press **0**) to remove the rating.
- **Color tag:** click the small square next to the stars and pick a color, or **None**.
- Changes go **straight into Capture One**, and show up on the iPad app and every other open
  viewer too.

### Comparing two photos

Press **C** (or click the **Compare** button, two panes side by side) to see two photos next to each
other in place of the big photo. The **selected** photo is on the right. The photo on the left is, by
default, the one **captured just before it**, so with Follow on you see your latest shot next to the one
before it, handy for checking an expression, a pose or a lighting change. Use the arrow keys, the
filmstrip, or swipe, to move along; the pair moves with you. Press **C** (or **Esc**) to go back.

**Choosing the other photo yourself:** **right-click** any photo in the filmstrip or grid (on a phone or
tablet, **long-press** it) to make it the comparison. Or go to it and press **R** (or click the **pin**
button). A pin appears on its thumbnail, and it stays on the left while you step through the others on the
right. Do the same again on that photo, or click **Clear** under it, to go back to "the photo before it".
Setting a comparison works with Compare off too: then press **C** when you're ready.

Each photo is labeled underneath with its name and place in the folder: **Previous** or
**Comparison** on the left, and **Latest** (the newest photo) or **Selected** on the right. In a tall
window (a phone, or a tablet held upright) the two photos stack top and bottom instead. A comparison
belongs to one folder: it is cleared if Follow moves on to another folder. Compare is only in this
view: fullscreen mode always shows one photo.

### Sorting and filtering

Click **Filter** to show the bar:

- **Sort:** by **Date** or **Name**, and flip the order (oldest/newest first, or A→Z/Z→A).
- **Rating:** show only photos with, say, **★★ and up**, or only **Unrated** ones.
- **Tag:** click one or more colors to show only those. The outlined square means "no tag".
- Rating and tag filters work together, for example "★★★ and up" *and* "green".
- The bar shows how many photos match ("12 of 71"). **Clear** shows everything again.

> **Good to know:** if you change a photo's rating or tag so it no longer matches the filter,
> it disappears from the list. With a rating filter on, brand-new (unrated) captures stay hidden
> until you rate them or clear the filter.

### The ☰ menu

- **Filmstrip location:** Left, Right or Bottom.
- **Show filmstrip:** untick to hide the filmstrip and give the photo the whole area (works on phones too). Use the grid button to still browse thumbnails.
- **Exposure info:** show or hide aperture, shutter speed and ISO.
- **Image background:** the color behind the photo, from white through gray to black (press **B** to
  step through them). Handy for judging a photo against a light or dark page, or for matching a
  client monitor. Only the photo window changes, not the rest of the screen.
- **Aspect-ratio frame** (**A** turns it on and off; computers and tablets): a crop guide laid over the
  photo, with everything outside it dimmed. Pick **1:1**, **4:5**, **4:3**, **5:7**, **3:2** or **16:9**, or
  **Custom** and type any ratio in the two boxes (**7 : 4**, **2.39 : 1**, **1.91 : 1**). The frame
  follows as you type; a number that can't be a ratio (zero, negative, wider than 20 : 1) turns red and
  is ignored, and **Enter** closes the menu. Like the presets, a custom ratio takes the photo's
  orientation (typing 9 : 16 gives 16 : 9 on a landscape photo), and **Rotate frame 90°** flips it.
  Drag the frame to move it and a corner to scale it; **Rule-of-thirds grid**, **Lock in place** and
  **Center and fit frame** are below the ratios. It stays in the same place on the picture from photo
  to photo, and the viewer remembers your ratio, including a custom one.
- **Rating & tags:** shows what this device may do, with **Network access…** on the Mac and
  **Enter PIN to rate…** on other devices when a PIN is set. When the app runs the viewer, Network
  access is set in the app's **Ratings & Tags** panel instead.
- **Fullscreen mode** (press **P**): the clean client view. See the next section.
- **Connection details…**, **Take the tour…**, **Keyboard shortcuts** and **About LfS Web Viewer**.
- At the very bottom, the **session** name and this browser tab's **client ID** (the random ID the
  tab identifies itself with; select and copy it if you need to quote it when asking for help).

The viewer remembers your choices in each browser: panel width, filmstrip position, filters,
Follow, exposure info, image background and the last folder.

---

## Showing it to a client (fullscreen mode)

Fullscreen mode turns the viewer into a clean, full-screen live view for a client monitor, a TV
or a tablet: just the photo, on the same background as the main view, with no buttons in the way.

### Starting it

- **From the viewer:** choose **☰ → Fullscreen mode**, or press **P**. The page goes full screen
  (on a phone, where browsers can't, it simply hides everything else).
- **For a screen that should always show it:** add `?fullscreen` to the viewer's address, for example
  `http://Faini-book-14.local:8787/?fullscreen` (use the address from *your* app or Terminal window;
  in the app, the QR code window can add it for you). The older `?present` still works too.
  Bookmark that on the client's screen. A web page can't take over the whole screen by itself, so
  **click or tap once** on that screen to make it full screen.

### What the client sees

- **The photo, as large as it fits, on your image background** (☰ › Image background, or press **B**;
  black suits most client screens). The mouse pointer hides too.
- **It opens on the photo you were already looking at, in the same folder.** Fullscreen mode never
  moves you by itself. Whether it follows your shoot is up to the **Follow** setting, exactly as in
  the normal view: with Follow **on**, each new capture appears by itself, even when it lands in a
  different folder. With Follow **off**, the picture stays put. Either way it also moves if you
  press **Follow** or Capture One's **Trigger Follow** button (which turns Follow on and jumps to
  the latest capture).
- **A new capture fades in,** and a note such as **"New capture · 12 today"** shows for a few
  seconds, so it's clear the photo changed even when it looks much like the last one. (The number
  is how many photos in the open folder were shot on the same day.)
- **Two faint labels in the corners.** Top left: a green dot and the session name (or a red
  **"Reconnecting…"** if the connection to Capture One drops). It also says **"Follow off"** when
  Follow is off, and **"filtered"** if a filter is hiding photos, so a new shot that doesn't appear
  is never a mystery. Bottom right: the file name, its place in the folder (for example
  **44 / 44**) and its stars.

### The control bar

**On a computer:** move the mouse and a bar appears along the bottom. It hides itself again after a
few seconds.

**On a tablet:** **tap the photo once** to hide the bar, and tap once more to bring it back. Swiping to
another photo (or touching the bar) also brings it up, and it tucks itself away after a few seconds.
Double-tap still zooms to 100% without toggling the bar.

**On a phone** (or a phone held sideways): the controls live in a **tray** at the bottom of the
screen, so they don't cover the photo. When the tray is closed you see only a small **grab handle**
at the bottom edge. **Swipe up on the handle**, or tap it, to open the tray; **swipe down**, tap the
handle, or tap the photo to close it. It also closes by itself after about six seconds, and it
stays open while you're using it or while a color menu is showing. Tapping the photo doesn't open
it, so double-tap zoom and swiping between photos work as usual.

**Labels on a phone never sit on top of a photo.** The photo stops short of two bands of black: a thin
one at the top for the "Live" label, and one at the bottom for the file name, its place in the folder
and the grab handle. (Held sideways there's just one row at the bottom: "Live" on the left, the
handle in the middle, the file name on the right.) The open tray covers the bottom of the screen, so
it repeats the name (and number) of the photo on show at its top.

| Control | What it does |
|---|---|
| **‹ ›** and **44 / 44** | Previous / next photo (the arrow keys and swiping work too), and which photo this is in the folder |
| **Stars and color tag** | Rate and tag, if this device is allowed to (see [Who can rate and tag](#who-can-rate-and-tag)). A view-only device doesn't show them; with a PIN set, tapping them asks for it. |
| **Exposure** | Aperture, shutter speed and ISO (the **I** key turns this off) |
| **Follow** (**F**) | Turn Follow on or off. Turning it on jumps to your latest capture, in whatever folder it is, without the "New capture" note. It's the same setting as the Follow button in the normal view. |
| **Labels** (**L**) | Hide or show the corner labels. Handy when you'd rather the client didn't see your ratings or file names. The "Reconnecting…" warning still shows. |
| **Exit** (**Esc**) | Leave fullscreen mode |

### Leaving

Press **Esc** or **P**, or tap **Exit**. It steps back one layer at a time: a color menu, then
zoom, then fullscreen mode itself. When the screen is full screen, **Esc** leaves
full screen and fullscreen mode together.

### Good to know

- **Double-click or double-tap still zooms to 100%**, handy for checking focus with the client.
- **Not available here:** Compare, the grid, folder list, filmstrip, filters and image background. Leave
  fullscreen mode to get them back. To show a different folder, leave fullscreen mode, open
  the folder, and go back in (or turn **Follow** on to go to your latest capture).
- **It shows what that browser's sort and filter are set to.** If a filter is hiding new captures,
  the top-left label says "filtered". Set the filter before presenting, or clear it.
- **Keep the screen awake.** The viewer can't stop a monitor, TV or tablet from sleeping or
  locking. Set its sleep or auto-lock to **Never** for the shoot. (This is a limit of browsers on
  plain network addresses.)
- **iPhone:** browsers there don't allow full screen, so you get the clean layout inside Safari.
  For a true full-screen look, tap **Share → Add to Home Screen** and open it from that icon.

---

## Sharing outside the studio (remote clients)

With the **LfS Viewer app** (in the `App` folder), people who aren't in the studio can watch too, from
anywhere, through Cloudflare. It's free, nothing is opened on your router, and every remote visitor
needs a **viewing code** you choose.

> **The full step-by-step guide is [`remote-setup.html`](remote-setup.html)** in this folder. Double-click
> it to open it in your browser. In the app, it's the **Setup Guide…** button in the **Remote Sharing** panel.
> It covers everything from creating a Cloudflare account to testing on your phone, plus
> troubleshooting.

There are two ways to share:

| | Temporary link | Your own address |
|---|---|---|
| **Looks like** | `https://calm-river-word.trycloudflare.com` | `https://view.yourstudio.com` |
| **You need** | Nothing | A free Cloudflare account and a domain on Cloudflare |
| **Setup** | About a minute | About 20 minutes, once |
| **The address** | Changes every time you start sharing | Stays the same, shoot after shoot |

**The short version for your own address** (the guide has every detail):

1. **Create a free Cloudflare account** at [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up).
2. **Put your domain on Cloudflare.** Under **Domains**, onboard the domain you already have (this means
   changing its nameservers where you bought it, and checking that your website and email records come
   across), or buy one through Cloudflare. Wait until it shows **Active**.
3. **Create a tunnel:** **Networking › Tunnels › Create a tunnel**, name it, choose **macOS**, and copy the
   install command shown. Don't run it: paste it into **Tunnel token** in the app's **Remote Sharing**
   panel and click **Save**.
4. **Connect:** with a viewing code saved, switch on **Share outside the studio** in LfS Viewer. When the
   dashboard shows the tunnel connected, select **Continue**.
5. **Publish your address:** in the tunnel's **Routes** tab, **Add route › Published application**. Choose a
   subdomain such as `view` and your domain, and set **Service URL** to **`http://localhost:8797`**
   (exactly that, including `http://`). Then type the full address into **Public address** in LfS Viewer.
6. **Test** on your phone with Wi-Fi off: the address asks for the viewing code, then shows the live view.

Remote visitors can look, zoom and filter, and rate or tag only if you allow it (see
[Who can rate and tag](#who-can-rate-and-tag)). The link works while LfS Viewer is running and your Mac
is awake.

**Who's watching:** the app's **Viewers** panel lists every browser connected right now:
- what it is ("iPhone · Safari") and where it's from: this Mac, your network, or remote, with the
  visitor's email if Cloudflare Access is set up;
- for remote visitors, their **IP address** (click it to look it up on ipinfo.io) and **where they
  are**, roughly (click it to see it on a map). Cloudflare always sends the country; for the city too,
  turn on **Add visitor location headers** in the Cloudflare dashboard (your domain › **Rules** ›
  **Settings** › **Managed Transforms**). It's worked out from the IP address, so a phone on mobile
  data may show its carrier's city;
- the folder and **photo** it's on (handy for "go to 0398" with a remote client), how long it has been
  connected, how many photos it has **rated and tagged**, and how much data the viewer has sent it.

Browsers that left in the last hour (closed the page, or a tablet that went to sleep) are under
**Recently left**, with when they left and what they were on; they move back up if they return.
From the **⋯** menu you can **Remove** a device (it's cut off at once and stays out until you unblock
it, under **Removed** at the bottom of the panel), stop rating on just that device (and allow it
again), or copy, look up or map a remote visitor's address.

**What visitors' pages call you:** the code page says "Enter the viewing code *the photographer* gave
you", and a removed device is told *the photographer* removed it. In the app's **Settings › Visitors'
pages** you can change that to "the digi-tech", "the operator", "Studio 4" or anything else: type it
or pick one from **Choose**, then click **Save** (or press Return). A green line confirms it.

---

## Who can rate and tag

**This Mac can always rate and tag.** Other devices are **view only** by default: they can
browse, zoom and filter, but tapping a star just shows "View only".

To change this, open the app's **Ratings & Tags** panel. (With the double-click launcher, open the
viewer **on this Mac** and choose **☰ → Network access…**.)

| Setting | What other devices can do |
|---|---|
| **View only** *(default)* | Look, zoom and filter. No rating or tagging. |
| **PIN to rate** | Rate and tag after entering a PIN you choose (4–8 digits). |
| **Anyone can rate** | Everyone who opens the viewer can rate and tag. |

**With a PIN:**
- **Unlocking:** on the phone or tablet, tap a star, type the PIN, and tap **Unlock**. That
  device stays unlocked for **30 days**.
- **Changing the PIN** signs out every device that used the old one.
- **Wrong guesses:** after **5 wrong PINs**, a device has to wait a minute before trying again. In the
  app you can change both: 1 to 20 tries, and a wait of 30 seconds to an hour.
- **Locking again:** a device can give up its access with **☰ → Lock rating on this device**.

In the app's **Viewers** panel you can also stop one device rating, and allow it again later. The **Network access** window (launcher) also lists the addresses to give other people. Your
choice is saved, so it's the same the next time you start the viewer.

---

## Keyboard shortcuts and touch gestures

Press **?** in the viewer to see this list at any time.

| Key | Action |
|---|---|
| **← →** (or **↑ ↓**) | Previous / next photo |
| **Home** / **End** | First / last photo |
| **1**–**5** | Rate 1 to 5 stars |
| **0** | Remove the rating |
| **Z** | Zoom to 100% and back |
| **F** | Follow new captures on / off |
| **G** | Grid / large view |
| **S** | Move the filmstrip: bottom → left → right |
| **H** | Show / hide the filmstrip |
| **I** | Exposure info on / off |
| **B** | Change the image background |
| **[** | Show / hide folders |
| **C** | Compare: the selected photo beside the one before it (or your comparison photo) |
| **R** | Set the selected photo as the comparison (press again on it to clear) |
| **P** | Fullscreen mode (just the photo, for a client monitor) |
| **Esc** | Leave zoom, Compare or grid, or close a menu |
| **?** | Keyboard shortcuts |

| In fullscreen mode | Action |
|---|---|
| Move the mouse | Show the control bar (it hides itself). |
| Tap the photo (tablet) | Hide the control bar, or show it again. Swiping also shows it. On a phone: swipe up on the handle at the bottom. |
| **F** | Follow on / off |
| **L** | Corner labels on / off |
| **← →**, **Z**, **0**–**5**, **I** | Work as usual |
| **Esc** (or **P**) | Step back: color menu, zoom, then fullscreen mode |

| Touch | Action |
|---|---|
| Swipe left / right | Next / previous photo |
| Double-tap | Zoom to 100% and back |
| Drag (while zoomed) | Move around the photo |
| Long-press a photo | Set it as the comparison (again to clear) |

| Mouse | Action |
|---|---|
| Double-click | Zoom to 100% and back |
| Drag or scroll (while zoomed) | Move around the photo |
| Right-click a photo | Set it as the comparison (again to clear) |
| Drag the folder panel's edge | Make it wider or narrower (double-click the edge to fit the names) |

---

## If something goes wrong

| What you see | What to do |
|---|---|
| The app or Terminal says **"Waiting for Capture One…"** | Open Capture One and turn on Live for Studio (**Start Sharing**). The viewer connects by itself. |
| **No folders or photos** appear | In Capture One's Live for Studio tool, check which folder is shared. The viewer shows only what's shared there. |
| A **new photo doesn't appear** | Check that it went into the shared folder (or one inside it), that **Follow** is on, and that no filter is hiding it (a dot on **Filter** means a filter is on). Follow may take 2–3 seconds to switch folders. |
| The page says **"Viewer script isn't running"** | The viewer was stopped. Switch it on again in the app's menu (or, with the launcher, the Terminal window was closed: double-click `Start LfS Viewer.command` again), then reload the page. |
| The dot is **red** and says Capture One didn't answer | Capture One may be busy importing or was closed. It reconnects by itself; if not, check that Live for Studio is still sharing. |
| A **phone or tablet can't open** the address | Check it's on the same Wi-Fi as the Mac, and that the app's **Settings › Only this Mac can open the viewer** is off. Try each address in the app's Addresses panel (or the Terminal window). If macOS asked about python3 and network connections, it must be **Allow**: change it under System Settings → Network → Firewall → Options. |
| On a phone the **stars won't change** ("View only") | That's the default for other devices. In the app's **Ratings & Tags** panel (launcher: **☰ → Network access…** on the Mac), pick **PIN to rate** or **Anyone can rate**. |
| **"Wrong PIN"** or **"Too many tries"** | Check the PIN in the app's **Ratings & Tags** panel (launcher: **☰ → Network access…** on the Mac). After the wrong tries allowed (5 by default), wait (a minute by default). |
| A device says **it was removed** | You (or someone at this Mac) clicked **Remove** in the app's **Viewers** panel. **Unblock** it under **Removed** at the bottom of that panel. |
| **Aperture, shutter and ISO** don't show | Check that **Exposure info** is ticked in the ☰ menu. If it is and they still don't show, the viewer couldn't find your session file; see `--session` under [Options](#options). |
| **Thumbnails are black** after opening a folder | They load as they come on screen and retry by themselves if Capture One is busy, so give it a few seconds. Only if they stay black, reload the page. |
| Fullscreen mode **doesn't fill the screen** | Browsers only allow full screen after a click or key press. If you opened it with `?fullscreen`, click or tap the screen once. On an iPhone it can't go full screen at all; use **Share → Add to Home Screen**. |
| In fullscreen mode the **new capture doesn't appear** | Look at the top-left label: **"Follow off"** means Follow is off (press **F**, or the **Follow** button), **"Reconnecting…"** means the connection to Capture One dropped (it retries by itself), and **"filtered"** means a filter is hiding it (press **Esc**, then clear the filter). Otherwise check that the shot went into a shared folder. |
| On a phone in fullscreen mode I **can't find the controls** | Swipe up from the small **handle** at the bottom edge of the photo (or tap it). The tray closes by itself after a few seconds. |
| The **client monitor goes dark** or locks | Set that screen's sleep or auto-lock to **Never** for the shoot. The viewer can't stop it. |
| The address says **8788** instead of 8787 | Something else was already using 8787, often the viewer running in another Terminal window, so it took the next free port. Either address works. The app says so in orange under Addresses; to choose a port yourself, use **Settings › Network › Port** and **Use Port**. |
| The Terminal says Capture One **refused the connection** after a Capture One update | Capture One may now expect a newer app version. See [Updating for a new Capture One](#updating-for-a-new-capture-one). |

Restarting Capture One, or switching Live for Studio off and on, is fine: the viewer finds it
again by itself.

---

## Good to know

- **It only changes ratings and color tags.** Nothing else in your Capture One session is
  touched. Exposure info is read from the session file without changing it.
- **It runs only while the Mac does.** The Mac must be awake, with Capture One sharing and the
  viewer switched on in the app (or the Terminal window open).
- **Who can see it:** anyone on the same network who knows the address can *view* the shared
  folder. To keep it to this Mac only, turn on the app's **Settings › Only this Mac can open the
  viewer**, or start it with `--local` (see [Options](#options)).
- **A cookie per browser:** each browser gets a small cookie holding a random ID, so the app's
  **Viewers** panel can tell devices apart and a removed device stays out. Nothing else is in it.
- **Sessions:** exposure info has been tested with Capture One *sessions*. Catalogs should work
  the same way but haven't been tested.
- **Accessibility:** the colors were measured against the WCAG 2.1 AA standard in every screen.
  All text is at least 4.5:1 against its background (most is 5:1 or more), and icons, field borders
  and the "no tag" outline are at least 3.7:1 (3:1 is required). Keyboard focus shows a clear
  ring. Two things are outside what can be measured or controlled: the small stars and color
  squares drawn on top of filmstrip photos sit on a dark fade so they stay readable on bright
  photos, and color tags are, by nature, shown by color (the tag button names its color for
  screen readers, and hovering a color shows its name). In fullscreen mode the control bar and
  the "New capture" note meet the same standard even over a white photo (checked in that worst
  case). The two corner labels are deliberately faint so they don't compete with the photo, and
  they sit on top of it, so they aren't held to it; the **L** key hides them.
- LfS Web Viewer is **not affiliated with or endorsed by Capture One**. Capture One and Live for
  Studio are trademarks of their owner.

---

## For the technically minded

### Options

You can also start the viewer from Terminal, in this folder, with `python3 lfs_viewer.py`, and
add any of these:

| Option | What it does |
|---|---|
| `--local` | Only this Mac can open the viewer (default: your whole network). |
| `--port 9000` | Use another port. If it's taken, the next free one is used (never the tunnel's), and the window says so. In the LfS Viewer app: **Settings › Network › Port**, then **Use Port**. |
| `--no-open` | Don't open the browser automatically. |
| `--session "/path/to/Session.cosessiondb"` | Where to read exposure info, if it isn't found automatically. |
| `--c1 127.0.0.1:50163` | Connect to this Capture One address instead of finding it. |
| `--debug` | Print each change message from Capture One. |
| `--tunnel-port 8797` | Also listen on this port for a Cloudflare tunnel. See [How remote sharing works](#how-remote-sharing-works). |
| `--settings "/path/settings.json"` | Keep the settings file somewhere else instead of in this folder. |
| `--control` | Used by the LfS Viewer menu bar app (in the `App` folder; see its README) to run the viewer. See the top of `lfs_viewer.py`. |

The double-click launcher passes options through too. For example, run
`"./Start LfS Viewer.command" --local` in Terminal.

### Files in this folder

| File | What it is |
|---|---|
| `Start LfS Viewer.command` | The double-click launcher. |
| `lfs_viewer.py` | The viewer itself (Python 3, no extra packages). Its top section documents the protocol and endpoints. |
| `viewer.html` | The web page. It's read fresh on each load, so changes need only a page reload. |
| `gate.html` | The "enter the viewing code" page people see when they open the viewer through a tunnel. |
| `remote-setup.html` | The step-by-step guide to sharing outside the studio through Cloudflare. |
| `App/` | The LfS Viewer menu bar app (Xcode project; see `App/README.md`). It bundles `lfs_viewer.py`, `viewer.html`, `gate.html` and `remote-setup.html`. |
| `settings.json` | For the launcher and Terminal: your **Network access** choice, PIN, wrong-PIN limits and remote viewing code. Created on first run; delete it to reset to "View only". The app keeps its own, in `~/Library/Application Support/LfS Viewer/`. |
| `README.md` | This guide. |

### How it works

Capture One's Live for Studio runs a small web server on the Mac, on a port that changes each
time it starts, and announces it on the network with Bonjour. `lfs_viewer.py` finds that port,
opens its own session the same way the iPad app does, and relays folders, photos, changes and
ratings between Capture One and your browser. To zoom to 100%, it asks Capture One for just the
visible part of the photo at full resolution. Aperture, shutter speed and ISO aren't part of
Live for Studio, so they're read from the session's own database file instead.

Live for Studio only reports changes in the folder a viewer is looking at. For Follow to catch
captures in *other* folders, the page asks the viewer every 2 seconds for the newest capture.
The viewer reads which image is newest from the session database (a few milliseconds,
read-only), and only when that changes does it look through the shared folders to find it.

Capture One hands each change to only *one* listener on a session. If every browser shared one
session, an iPad and a Mac watching the same folder would each miss some of the changes (a rating
made on the iPad, a new capture). So the viewer gives every browser tab, and every folder it
opens, a private Capture One session for its updates (a "feed"). When you open another folder the
previous feed is closed, and a tab that has gone quiet for about five minutes is dropped. If a
feed ever stops working (Capture One restarted, or a tablet was asleep for a long while), the page
notices and starts a new one by itself. Photos, ratings, Follow and exposure info share a single
session, since they don't listen for changes.

### How remote sharing works

A Cloudflare tunnel can put the viewer on your own domain, so people outside the studio can watch.
Start the viewer with `--tunnel-port 8797` (the LfS Viewer app does this for you) and point the
tunnel at `http://localhost:8797`. The step-by-step setup is in [`remote-setup.html`](remote-setup.html).
Don't use the main port (8787): there, requests from the tunnel would count as this Mac and could
change everything. The main port refuses tunnel traffic, so a wrong setup shows an error instead
of opening the viewer to everyone.

Through the tunnel:

- **Visitors need a viewing code first** (6 to 12 digits), on a page of its own. Each browser
  remembers it for 30 days. A new code signs everyone out. Until a code is set, nobody gets in.
  If Cloudflare Access already protects the address, the code can be turned off (`remote_view: "open"`).
- **Rating follows your rating choice** (Ratings & Tags, or Network access), but a visitor is never treated as this Mac.
  A new rating PIN doesn't sign visitors out of viewing.
- **Wrong guesses are limited twice:** per visitor, as on your network, and for all visitors
  together. After 20 wrong codes or PINs in 10 minutes, remote unlocking pauses for everyone
  (it doesn't affect devices in the studio).
- **Signing everyone out** ends both PIN unlocks and viewing codes. An open page notices within
  about a minute and asks for the code again.

The LfS Viewer menu bar app (in `App/`) does all of this from its window: it starts cloudflared,
opens the tunnel port (8797 by default) and sets the viewing code. Run from Terminal, the viewing
code is set in `settings.json` (`remote_code`; restart the viewer after editing it).

### Updating for a new Capture One

The viewer introduces itself to Capture One as the Live for Studio iPad app, version `1.4.2.3`.
If a Capture One update rejects that ("refused the connection" in Terminal), set `APP_VERSION`
near the top of `lfs_viewer.py` to the current version of the Live for Studio iPad app (shown
in the App Store), then start the viewer again.

---

*LfS Web Viewer is made by [Faini Made](https://fainimade.com).*
