# ESO Addons for Mac — Minion Alternative for macOS

[English](README.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md)

[![Build and tests](https://github.com/TheMoldex/minion-alternative-eso-macos/actions/workflows/build.yml/badge.svg)](https://github.com/TheMoldex/minion-alternative-eso-macos/actions/workflows/build.yml)

A native **ESO addon manager for macOS**, built with SwiftUI for Apple Silicon. A Minion alternative for **The Elder Scrolls Online**, with the ESOUI catalog, automatic addon updates, required library installation and manual settings backups. English, Russian, French and Spanish interface.

**[Download for Mac](https://github.com/TheMoldex/minion-alternative-eso-macos/releases/latest/download/ESO-Addons-for-Mac.zip)** · [Releases and checksums](https://github.com/TheMoldex/minion-alternative-eso-macos/releases) · [Report a problem](https://github.com/TheMoldex/minion-alternative-eso-macos/issues)

## Install

1. Download **`ESO-Addons-for-Mac.zip`** from [the latest release](https://github.com/TheMoldex/minion-alternative-eso-macos/releases/latest), then unzip it. Do not choose GitHub’s automatic “Source code” ZIP unless you want to build the app.
2. Drag `ESO Addons for Mac.app` into **Applications** and open it.
3. Allow access to **Documents** when macOS asks. The app needs it to read and manage ESO addons.
4. Confirm your ESO `live/AddOns` folder, or open the sidebar gear → **General → Choose folder** and select `live`. The usual path is `~/Documents/Elder Scrolls Online/live/AddOns`. Select `pts` for the test server.
5. Open **Installed** and check that your existing addons appear. Use **Find addons** to install more or **Updates → Update all** to review available updates. After changing addons, run `/reloadui` in ESO.

Requires **macOS 14 or later and Apple Silicon**. This build is locally signed, without Apple Developer ID signing or notarization. If macOS offers **Open Anyway**, it is under System Settings → Privacy & Security. See [Apple’s instructions](https://support.apple.com/en-us/102445). You do not need an Apple developer account or certificate to use the app. Intel Macs are not supported by this release.

## Coming from Minion on macOS?

Select the same ESO AddOns folder you used in Minion. Existing addons are detected, and matching Minion records can identify their ESOUI source. There is no need to reinstall everything or move SavedVariables. Minion’s configuration is read without modifying it. Quit Minion before installing or updating addons here. This is an independent application, not an official Minion release or fork.

## Use

Drag either vertical divider to resize the sidebar or addon details. Widths persist across restarts. A focused divider also responds to the left/right arrow keys. Controls wrap in narrow windows. The gear at the bottom of the sidebar opens Settings (also available with Command–comma). Settings → General contains ESO folders, language and backup options; Settings → Updates contains automatic updates, download concurrency, ignored addons and app version checks.

Right-click an addon row for its context menu: details, install/update/reinstall, ignore/resume updates, reset settings, ESOUI page, installed folder and removal. The menu acts on the clicked row even if another addon is selected. Removal uses the same confirmation and dependency checks as the card button.

- **Installed** detects existing addons. Matching Minion records are imported read-only; Minion's configuration is not changed.
- **Find addons** searches names, authors and folder names in the cached ESOUI catalog. Select an addon, click **Install**, review the addon and dependency list, then confirm.
- Rows show **Update available**, **Up to date**, **Local version is newer** or **Version could not be checked**, with installed and available versions. Unrecognized addons never receive an up-to-date checkmark. Catalog entries not yet installed are labelled separately.
- Total downloads, monthly downloads and favorites are shown when provided by ESOUI. Category names and icons come from ESOUI, like in Minion. Icons are downloaded only when displayed and cached locally; a generic addon or library icon appears when unavailable. These are category icons, not individual addon screenshots.
- **Updates** lists recognized addons whose manifest version is older than the catalog. **Update all** opens the same preview before changing files. Newer local versions are not automatically downgraded.
- **Backups → Settings and transfer** creates optional manual copies of SavedVariables, game settings and the installed-addon inventory. **Update rollback** contains copies of folders affected by installations and updates.
- **Remove addon** previews the folders to remove and lists required libraries with other addons that use them. Libraries are preserved by default. **Remove unused libraries** optionally includes the dependency libraries needed only by this addon and its library group; shared libraries always stay. A required library cannot be removed while another retained addon depends on it. Selected folders move to macOS Trash without creating an application backup. Use **Put Back** in Trash to restore them. SavedVariables remain in place. If removal fails, folders already moved are put back; if this cannot complete, the error lists their Trash locations.
- Addon cards show **Description / What's new**, loaded from the ESOUI API and cached for one hour. Text is displayed without executing HTML. The author's language is preserved. Screenshots from the separate ESOUI image list appear near the top of the card; click a thumbnail for a larger viewer with previous/next buttons, arrow keys and an enlarge/fit toggle. Full images load when opened. Missing screenshots are labelled; network failures offer Retry in the viewer.
- After installing or updating, run **`/reloadui`** in ESO.
- Switch **Русский / English / Français / Español** in Settings → General. The choice persists across restarts. Addon descriptions stay in their author's language.
- **Addon / Library** badges appear in lists, details and the install preview. Types come from ESOUI metadata or local manifests, not name prefixes. Automatically included dependencies are also labelled in the preview.

Use the controls below search to combine **Category**, **Addon / Library** and **ESO version** filters. Compatibility versions come from the author’s ESOUI list; entries with unknown compatibility are excluded when a specific version is selected. Sort by **Name**, **Downloads** or **Last updated**, then use the arrow to reverse the order. **Reset filters** also clears search and restores the default order: name for installed addons, downloads for the catalog. The result counter shows how many entries match. Catalog filters are kept separately from Installed / Updates while the app is open. These controls affect the displayed list; **Update all** continues to preview all recognized updates except ignored addons before confirmation.

The catalog is cached for one hour; explicit refreshes are limited to once per minute. Manual installations show a preview before downloading. Do not run manual addon updates in Minion and this application simultaneously.

## Ignoring updates, folders and history

Choose **Ignore updates** from an installed addon's context menu or details. Manage all exclusions for the selected folder in **Settings → Updates → Ignored addons**. It is excluded from **Update all** and automatic updates for this ESO folder. Its individual update button remains available. **Resume updates** restores normal behavior. If another addon needs a newer version of an ignored library, the operation stops and asks you to resume that library's updates first.

The folder menu in Settings → General switches between saved ESO installations, including `live` and `pts`. **Choose folder** registers another folder; **Remove from folder list** forgets the selection without deleting any files. Addon sources, ignored updates, rollback copies and operation history are separate for each folder. The automatic updater operates only on the currently selected folder.

**Concurrent downloads** in Settings → Updates accepts 1–4 downloads (default 3). Files are downloaded and checked before the batch is installed. A failed download or invalid archive skips that package. Other updates continue when their required libraries are available, including compatible installed versions. The result lists skipped packages and the reason for each.

**Operation history** persists the latest 500 entries for the selected folder, including addon names, timestamps and error stages. Use **Errors only** or **Copy history** for diagnostics.

## Manual backups, transfer and settings reset

1. Quit ESO and Minion.
2. Open **Settings → General → Backups** and choose a backup folder, including a folder on another disk or a locally synced cloud drive.
3. Open **Backups → Settings and transfer** and leave **Include addon files** enabled for a full transfer without redownloading. Without it, the copy contains settings and an addon inventory only; the inventory does not reinstall addons.
4. Click **Create manual backup**. Copies remain until you delete them in the app or Finder. The rollback retention setting does not delete these copies.
5. To transfer, copy the entire `ESO-Backup-…` folder to another computer. Choose the target ESO folder, click **Open backup from another computer**, select the copy and review the files before restoring.

You can give a manual copy an optional name before creating it. Select a copy and use **Rename** or its right-click menu to change the name later. Empty names use the creation date. Names are stored inside the portable backup and survive transfer.

Both backup lists support multiple selection with Command or Shift. Use **Delete selected**, the Delete key, or right-click → **Delete backups**. The app confirms the selection and moves the complete backup folders to macOS Trash. Use **Put Back** in Trash to return them. Deleting a backup does not remove installed addons or game settings; unfinished recovery copies are protected.

The copy contains `SavedVariables/*.lua`, their `.lua.bak` files, `UserSettings.txt`, `AddOnSettings.txt`, source mappings and ignore preferences, plus addon files when selected. Files are verified using SHA-256 before restore. Only the listed files and addon folders are replaced; unrelated entries stay in place. An interrupted or failed restore rolls back using a local transaction journal. Moving files does not rewrite account or character identifiers in addon settings.

**Reset addon settings** is a separate action in the addon card and context menu. It previews the SavedVariables files belonging to that addon's manifests, then moves only those files to macOS Trash. Shared settings are protected, and separate dependency libraries are preserved. Reset does not create an addon backup. ESO must be closed so it cannot write the old settings back on exit. [ESOUI SavedVariables guide](https://www.esoui.com/forums/showthread.php?t=9235).

## Automatic updates

**Automatic updates** is enabled by default and can be switched off in Settings → Updates or the menu bar. The first scheduled check is one hour after enabling it; the next check time is shown in Settings → Updates. It updates only recognized installed addons that are not ignored, includes required dependencies and creates backups before replacement. It never installs unrelated catalog addons.

Automatic checks are postponed while ESO or Minion is running, while an operation or confirmation is open, or if recovery is blocked. The process list is checked again immediately before replacement. Paused checks retry in five minutes; other failures retry in fifteen minutes. Status and full errors are visible in Settings → Updates and the menu bar. A compact error indicator in the sidebar opens the update settings. Automatic addon updates pause while Settings is open.

Closing the window leaves the application running in the menu bar while automatic updates are enabled. Use **Show window** to reopen it and **Quit ESO Addons** to stop it. Sleep pauses execution; overdue checks resume after wake. There is no system service, scheduled launch while the app is quit, or automatic login launch. Open the application again after restarting the Mac.

## Matching and dependencies

Some ESOUI projects share folder names. The manager first uses its own saved selection or matching Minion records. It then considers unambiguous catalog matches. If the source remains ambiguous, select the installed addon and choose **Choose ESOUI source**. Unrecognized folders are left untouched by bulk updates.

Required `DependsOn` libraries and minimum `AddOnVersion` values are resolved from catalog metadata. Optional dependencies are not installed automatically. If a library cannot be resolved safely, installation stops and lists it. Downloaded manifests are checked again before installation; newly discovered unresolved requirements also stop the operation.

Only ZIP addons with a catalog folder list are supported. Discontinued projects are excluded from search. Unsupported or unsafe archives are rejected rather than partially installed. Extra folders containing only small text documentation are ignored; unexpected executable files or active addon manifests remain blocked. This also handles Ravalox Quest Tracker’s obsolete-folder placeholders.

## Files and recovery

Starting with 0.5.5, automatic rollback copies include SHA-256 hashes. Restore and startup recovery verify every recorded file before replacing an addon. Older automatic copies without hashes remain on disk and can be inspected or deleted, but their Restore button is disabled because their completeness cannot be verified. Manual portable copies already contain hashes and remain supported.

If an addon file cannot be read or recovery metadata is damaged, installed addons remain visible for inspection. File-changing operations stop and the error identifies the affected path. Correct the file access or damaged recovery data, then check again. Finder Locked files are rejected before replacement starts. Library rollback and portable restore cannot introduce a missing dependency in an addon that stays installed. Pending recovery waits until ESO and Minion are closed.

- Addon installation and update replace only the affected folders inside the selected **AddOns** directory.
- Installing, updating and removing addons preserves **SavedVariables** and game settings. Only explicit **Reset addon settings** or portable restore changes those files. Minion's configuration is never modified.
- Existing TTC `PriceTable*.lua` and `ItemLookUpTable*.lua` files are preserved when updating Tamriel Trade Centre. This app does not synchronize TTC prices itself; the separate TTC client continues to handle that.
- Downloads use HTTPS, restrict redirects to ESOUI/MMOUI hosts and verify the server-provided archive MD5. MD5 detects corruption; it is not a publisher signature.
- ZIP paths, duplicate names, link entries, expanded sizes and CRC are checked. Decompression has fixed output bounds. Archives are extracted into a temporary directory before existing addons are changed.
- Before installation, updates or restoration, affected folders and source metadata are backed up under `~/Library/Application Support/ESOAddonsMac/`. Interrupted operations are restored on the next launch with the same folder selected.
- **Backup retention** in Settings → General → Backups offers **Keep all / Latest 5 / 10 / 20**. Keep all is the default. A selected limit removes older completed backups only after successful install, update or restore operations in the selected folder. Pending recovery backups are preserved. Removed addons are restored from macOS Trash. Game settings and SavedVariables are not included in these copies.
- Read-only addon directories owned by your account receive the owner-write bit before replacement or removal of transaction copies. Permissions for other users are preserved. Backup contents remain unchanged. If startup recovery fails, installed addons and the cached catalog still load for viewing; file-changing actions remain blocked until recovery succeeds.
- Settings use the preferences domain `local.denstash.ESOAddonsMac`. The AddOns directory contains a hidden `.eso-addons.lock` file used to prevent concurrent operations by this app.

## Build and tests

Requires the Xcode Command Line Tools; no external Swift packages or Java runtime.

Local builds use ad hoc signing by default. Replacing a build changes its signing identity and can make macOS ask for Documents access again. A normal restart of the same build does not replace its signature. If you have a code-signing certificate, set `ESO_SIGNING_IDENTITY` when building to use that stable identity. No certificate is created or imported by the build script.

```sh
./build.sh /tmp/ESOAddons.app
```

The build runs local safety and dependency checks. To also test a real ESOUI download, install, backup, rollback and interrupted-install recovery **in a temporary fixture folder**:

```sh
ESO_LIVE_TESTS=1 ./build.sh /tmp/ESOAddons.app
```

The app has been built and exercised locally on an Apple Silicon Mac. A clean installation on another Mac, Intel Macs and every archive in the ESOUI catalog have not been verified. The macOS build and test workflow is included in `.github/workflows/build.yml`.

Independent, unofficial application. Not affiliated with ESOUI, MMOUI, Minion, ZeniMax or Bethesda. Addons remain the work of their respective authors and are downloaded from ESOUI when requested.

## Addon screenshots

Only the selected addon’s screenshot thumbnails are loaded, using validated HTTPS preview addresses from the ESOUI CDN. Images embedded inside arbitrary description markup are not fetched. Switching addons cancels pending view requests. The viewer loads the selected original on demand and decodes bounded-size previews; enlarging allows scrolling through the image. Screenshots are cached locally for seven days, with a limit of 64 files and 96 MB. API descriptions and screenshot metadata share one request per selected addon.

## App updates

The app makes a fresh GitHub request at every launch, then checks hourly while running. **Check app version** in Settings → Updates forces a fresh check and is also available in the application menu and menu bar. A ready app ZIP must be attached before a newer release is offered. Drafts and prereleases are ignored, versions are compared numerically and older versions are never offered.

The update window shows the new version and release notes. **Later** closes it; a prominent **Version available** banner stays in the sidebar. Hourly checks do not reopen a dismissed notice for the same version, but a newer release is announced. **Download update** opens the verified GitHub release page. Download the ZIP, quit the app and replace it in Applications. Updates are installed manually. Network failures do not interrupt normal app operation; manual checks show their result. GitHub is queried anonymously; no ESO files or account credentials are sent to it.

For this first public release, install 0.5.6 manually once if you used a local development build. Versions through 0.5.5 point at the previous repository address and will not discover this release. Existing builds without the update-check feature also need one manual upgrade. The addon manager uses `TheMoldex/minion-alternative-eso-macos`; it reports no ready build until a stable release with the expected ZIP exists.

For a new public version, bump both version fields in `build.sh`, build and test, then publish a stable GitHub release named `vX.Y.Z` matching the app version. Attach `ESO-Addons-for-Mac.zip` and its SHA256 checksum before publishing. Release notes are shown in the update window.

## Need help?

Check the selected ESO folder and reset filters if an addon seems missing. **Version could not be checked** means the manager cannot prove it is current. If file access or recovery fails, the installed list remains available for viewing and the error identifies the affected path; fix the reported problem before retrying changes. Check **Operation history → Errors only** for details.

Open a [GitHub issue](https://github.com/TheMoldex/minion-alternative-eso-macos/issues) with the app version, macOS version, Apple chip model, steps and the relevant error. Remove account names, private paths and SavedVariables contents before sharing logs.
