# Apple: step-by-step guide

This guide is for the owner of the developer account. It lists each step at Apple and on the devices, in order.

- The identifiers are in `01-names.md` §1. If a decision in `README.md` §3 changes, the identifiers here change too.
- **Permanent** marks a step that cannot be undone.
- **Not verified** marks a statement that was not found in Apple's documentation on 2026-11-20. Sources are at the end.
- Private data (team ID, request ID, account details) stays in `private/`. Do not write it into this file.

You need the role Account Holder or Admin in the developer account.

## Summary

| Part | When | Content |
|---|---|---|
| A | phase 1, before code changes | register identifiers, the notes entitlement |
| B | phase 4, after the rename in the code | signing in Xcode, first build |
| C | phases 5 and 6 | devices, permissions, iCloud |
| D | phase 8, one week later | clean up |
| E | later, not part of this change | App Store Connect, universal links |

## Part A — identifiers and entitlement

Open <https://developer.apple.com/account>, then **Certificates, Identifiers & Profiles**, then **Identifiers**.

### A1. Decide the bundle ID — permanent

The bundle ID is `me.cardxchange.app` (decision D1, confirmed 2026-11-20). After the registration, the string cannot be changed; a different name needs a new App ID.

### A2. Register the iCloud container — permanent

1. Select the add button (+), **iCloud Containers**, **Continue**.
2. Description: `cardXchange`. Identifier: `iCloud.me.cardxchange.app`.
3. **Continue**, **Register**.

Apple documents no way to delete a container (**not verified** that it is impossible). Plan for this: the old container `iCloud.com.tillg.pplz` stays in the account.

### A3. Register the App Group

1. Add button (+), **App Groups**, **Continue**.
2. Description: `cardXchange`. Identifier: `group.me.cardxchange.app`.
3. **Continue**, **Register**.

This group is for the iOS app and the iOS share extension.
The Mac app and the Mac share extension use `<TeamID>.me.cardxchange.app`. A group of this form is not registered at Apple and needs no provisioning. See the note at the end of this part.

### A4. Register the App ID of the app

1. Add button (+), **App IDs**, **Continue**. Select the type for an app, **Continue**.
2. Description: `cardXchange`. Select **Explicit App ID**. Bundle ID: `me.cardxchange.app`.
3. Select the capabilities:
   - **App Groups**
   - **iCloud**, with **Include CloudKit support**
   - **Push Notifications** (CloudKit uses it to announce changes; a push certificate is not necessary for this — **not verified**)
4. **Continue**, **Register**.
5. Open the new App ID, **Edit**:
   - App Groups: **Configure**, select `group.me.cardxchange.app`, **Continue**, **Assign**.
   - iCloud: **Edit**, select `iCloud.me.cardxchange.app`, **Continue**, **Save**.
6. **Save**. Confirm if a warning shows.

The Mac app and the iOS app share this one App ID, as today.

### A5. Register the App IDs of the share extensions

Do A4 two times more, with fewer capabilities:

| Bundle ID | Description | Capabilities |
|---|---|---|
| `me.cardxchange.app.share` | `cardXchange Share` | App Groups, with `group.me.cardxchange.app` |
| `me.cardxchange.app.sharemac` | `cardXchange Share Mac` | none (the Mac group has the team-ID form) |

`me.cardxchange.app.uitests` needs no manual step. Xcode handles it for the simulator.

### A6. Notes entitlement (`com.apple.developer.contacts.notes`) — D11

The request that is pending names the old bundle ID `com.tillg.pplz`.

- **Not verified:** whether Apple grants this entitlement for one App ID or for the team. Assume that it is for one App ID.
- Apple has no documented procedure to change a pending request.

Do this:

1. Send a new request with the form at <https://developer.apple.com/contact/request/contact-note-field>. Give the bundle ID `me.cardxchange.app` and the app name cardXchange.
2. In the text, say that this request replaces the earlier request for `com.tillg.pplz`, and give the ID of the earlier request (from your private notes).
3. If the form asks for a website, give `https://cardxchange.me` or the new repository address.
4. Give the text of the Contacts prompt with the new name (`App/project.yml`, `NSContactsUsageDescription`).
5. Write the new request ID and the date into `private/`, and tell Claude to update the reminder in its memory.
6. After Apple grants it: open the App ID, look at the **Capabilities** tab (and **Capability Requests**), and enable the entitlement there if it is listed. **Not verified** that this entitlement is listed there; Apple possibly answers by email with instructions.

Do A6 immediately after A4. The answer from Apple takes the most time.

### Note: the form of the Mac App Group

- Today the Mac uses the team-ID form. This guide keeps it, so that the rename changes names only.
- With the team-ID form, macOS 15 shows no "access data from other apps" prompt.
- Apple now recommends the `group.` form on the Mac too. That form needs a provisioning profile that contains the group; without it, macOS 15 shows the prompt.
- A change to one `group.` identifier for all four targets is a possible later change. It is not part of this rename.

## Part B — signing and first build

Do this after phase 3 (the rename in the code) is complete.

### B1. Generate the project

1. Check that `App/Local.xcconfig` exists and holds the team ID.
2. `cd App && xcodegen generate`. The project is `App/cardxchange.xcodeproj`.

### B2. Let Xcode create the profiles — one time

`xcodebuild` cannot create profiles for new identifiers from the command line session. The same was necessary for the first setup (see `docs/DECISIONS.md`, "bundle ID `com.tillg.pplz.share`").

1. Open `App/cardxchange.xcodeproj` in Xcode. Check **Settings**, **Accounts**: your Apple account is signed in.
2. For each target `cardxchangeMac`, `cardxchangeiOS`, `cardxchangeShare`, `cardxchangeShareMac`: open **Signing & Capabilities**.
3. Check that **Automatically manage signing** is on and the team is correct.
4. Wait until the signing section shows no error. If Xcode shows **Register Device** or **Try Again**, select it.
5. Check that iCloud shows the container `iCloud.me.cardxchange.app` with a check mark, and App Groups shows the new group.
6. Do not change values in the Xcode window. The values come from `App/project.yml`. If a value is wrong, correct `project.yml` and generate again.

### B3. Build

1. Connect the iPhone and unlock it.
2. `scripts/build-app.sh mac`
3. `scripts/build-app.sh simulator`
4. `scripts/build-app.sh iphone "<device name>"`. This checks the profiles. Do not start the app on the device before phase 6; delete it from the device again if you prefer.
5. `swift build -c release`, then `ln -s "$(swift build -c release --show-bin-path)/cx" ~/.local/bin/cx`.
6. Remove `PPLZ_STORE` and `PPLZ_NO_CONTACTS` from the shell profile. `cx` refuses to start while one of them is set.

### B4. Check the signature of the Mac app

```sh
codesign -d --entitlements - /Applications/cardXchange.app
```

The output names `iCloud.me.cardxchange.app` and `<TeamID>.me.cardxchange.app`.

### B5. CloudKit Console

1. Open <https://icloud.developer.apple.com>, **CloudKit Database**, and select `iCloud.me.cardxchange.app`.
2. The container is empty. No manual step is necessary: in the Development environment, the record types are created when the app saves the first records.
3. Do not select **Deploy Schema Changes**. A deployment to Production is **permanent**: record types and fields in Production cannot be deleted. This rename stays in Development.

## Part C — devices

The order is in `02-data-migration.md` §10. Follow that list; the steps here are the Apple side of it. Until phase 5, pplz and cardXchange are both installed and both register the URL scheme `pplz`; that is harmless for this short time.

### C1. Mac (phase 5, at step 7 of that list)

1. The old app is deleted and the store is migrated (steps 1 to 6 of that list).
2. Start `/Applications/cardXchange.app`.
3. macOS asks again for the permissions, because the app has a new identity:
   - Contacts
   - Calendar
   - Automation: control of the Contacts app (asked at the first write to a contact)
4. Allow each one. Check them in **System Settings**, **Privacy & Security**: Contacts, Calendars, Automation.
5. The command `cx` possibly asks again for Contacts and Calendar in the terminal app (**not verified**). Allow it.
6. The share extension: open **System Settings**, **General**, **Login Items & Extensions**, **Sharing**, and switch on cardXchange. Switch off pplz.

### C2. iPhone and iPad

1. Phase 5, step 1 of that list: open the old pplz app one time, so that the share inbox is empty and the last changes are synced to the Mac.
2. Phase 5, step 3: delete the pplz app. Its local data goes with it; the Mac store is the source.
3. Phase 6, step 10, after the new link row is visible in the Contacts app on the device: install cardXchange (B3). If iOS does not trust the developer: **Settings**, **General**, **VPN & Device Management**.
4. Start the app. Allow Contacts (full access), Calendar and Camera when the app asks.
5. Check that iCloud is on for the app: **Settings**, your name, **iCloud**, **Saved to iCloud** (or **Apps Using iCloud**), cardXchange.
6. Wait for the sync. Check three persons with events and photos.
7. Share a screenshot to cardXchange from the Photos app. If cardXchange is not in the share sheet: **More**, **Edit**, and add it.

### C3. Check the result in Contacts

Open one linked contact in the Contacts app on the Mac and on the iPhone:

- one URL row with the label `cardxchange`
- no row with the label `pplz`
- one history block in the note, with the new markers

## Part D — clean up

Do this one week after part C, when all checks passed.

### D1. Mac

1. `/Applications/pplz.app` is already deleted (phase 5).
2. Remove the old permissions. Check the syntax with `man tccutil` first (**not verified** here):
   ```sh
   tccutil reset AddressBook com.tillg.pplz
   tccutil reset Calendar com.tillg.pplz
   tccutil reset AppleEvents com.tillg.pplz
   ```
3. Delete the old group container: `~/Library/Group Containers/<TeamID>.com.tillg.pplz/`.
4. Delete the old store folder `~/Library/Application Support/pplz.migrated-<date>/`. It is the only backup of the old store, so do it only when all checks passed.
5. `defaults delete com.tillg.pplz` removes the old window settings.
6. Delete the old simulator app or rename the simulator (`04-repository-and-folder.md` §2.3).

### D2. Developer account

In **Identifiers**:

| Identifier | Action | Remark |
|---|---|---|
| App IDs `com.tillg.pplz`, `com.tillg.pplz.share`, `com.tillg.pplz.sharemac`, and `…uitests` if listed | open, **Remove**, confirm | Apple refuses the removal only for an App ID with an uploaded build; none was uploaded. **Not verified** that the pending entitlement request does not block it. Do it only after Apple confirmed the new entitlement request (A6); the old request names this App ID. |
| App Group `group.com.tillg.pplz` | remove if the page offers it | **Not verified** that a group can be removed |
| iCloud container `iCloud.com.tillg.pplz` | none | no documented way to delete it; in CloudKit Console you can reset its Development environment (**Reset Environment**) to delete the data, and hide the container |

In **Profiles**: profiles for the old App IDs become invalid. Delete them, or let Xcode do it.

### D3. Old data in iCloud

The old container holds a copy of the data in the Development environment. To delete it: CloudKit Console, select `iCloud.com.tillg.pplz`, **Reset Environment**, confirm.
Do this only after the data is checked on all devices with the new app.

## Part E — later, not part of this change

### E1. App Store Connect

No app record exists today, so the rename needs no step here. For the first release:

- One app record can hold the iOS and the macOS app with the same bundle ID.
- The app name has 2 to 30 characters. Check the name `cardXchange` for trademarks before you rely on it. Apple makes no check for you.
- **Permanent:** the SKU, at once. The bundle ID, after the first build is uploaded. After that upload, the App ID also cannot be removed.

### E2. Universal links for `cardxchange.me`

Apple recommends universal links over custom URL schemes. A custom scheme has no registry, and a different app can register the same scheme. This is more probable for a short scheme such as `cx`.

Needed for it:

- the capability **Associated Domains** on the App ID, with `applinks:cardxchange.me`
- the file `https://cardxchange.me/.well-known/apple-app-site-association` (HTTPS, valid certificate, no redirect) that names `<TeamID>.me.cardxchange.app`
- a decision whether the link in a contact becomes `https://cardxchange.me/person/<uuid>`. That is a third link form and needs its own migration, so decide it before phase 2 if you want it now.

## Sources

Checked on 2026-11-20.

- Register an App ID: <https://developer.apple.com/help/account/identifiers/register-an-app-id/>
- Delete an App ID: <https://developer.apple.com/help/account/identifiers/delete-an-app-id>
- Enable app capabilities: <https://developer.apple.com/help/account/identifiers/enable-app-capabilities/>
- Register an App Group: <https://developer.apple.com/help/account/manage-identifiers/register-an-app-group>
- Create an iCloud container: <https://developer.apple.com/help/account/manage-identifiers/create-an-icloud-container>
- Configuring iCloud services: <https://developer.apple.com/documentation/xcode/configuring-icloud-services>
- Configuring app groups: <https://developer.apple.com/documentation/xcode/configuring-app-groups>
- Accessing app group containers (Mac rules): <https://developer.apple.com/documentation/xcode/accessing-app-group-containers>
- Notes entitlement: <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.contacts.notes>
- Capability requests: <https://developer.apple.com/help/account/capabilities/capability-requests>
- CloudKit schema and deployment: <https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema>
- Code signing requirements (permissions follow the app identity): <https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements>
- Add a new app (App Store Connect): <https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/>
- Custom URL schemes: <https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app>
- Associated domains: <https://developer.apple.com/documentation/xcode/supporting-associated-domains>

Not verified from Apple's documentation:

- that the string of a registered bundle ID cannot be edited (the documentation offers no way to edit it)
- that an App Group can be removed
- whether the notes entitlement is granted for an App ID or for a team, and how a pending request is changed
- that a container cannot be deleted, and that CloudKit needs no push certificate
- which permissions macOS asks again for the command `cx`
- that Xcode registers identifiers that are only written in an entitlements file from XcodeGen; thus part A registers them by hand
- the `tccutil` syntax with a bundle ID
- the exact labels in the Settings apps of the current macOS and iOS versions
