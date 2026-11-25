# VYBE 2.0.4 — Radial Recovery & Keychain Startup Fix

## Radial actions
- Added a one-time v3 migration that merges any missing built-in radial actions into the user's existing saved list without deleting custom actions.
- Added **Restore All Built-in Actions** to the radial customization menu for manual recovery.
- Existing custom actions and saved action IDs are preserved.

## Login Keychain prompts
- OpenRouter and Gemini API keys are no longer read from the login Keychain while their service singletons are initialized.
- Keychain reads are deferred until the user opens AI Settings or starts using the selected provider.
- Only the currently selected provider is loaded when AI Settings opens; switching providers loads that provider on demand.
- This avoids credential-access dialogs during ordinary VYBE startup. If macOS still prompts when AI settings is opened, verify that the dialog names VYBE and choose **Always Allow** only if the request is expected. A changed/adhoc code signature can cause macOS to treat a rebuilt app as a new Keychain client.
- No Keychain items are deleted, reset, or migrated by this patch.

## Xcode configuration
- `ALWAYS_SEARCH_USER_PATHS = NO` was already present in all four Debug/Release project and target build configurations in the uploaded 2.0.3 project. It remains set in this project; no manual setting change is needed for this build setting.

## Validation
- Swift frontend syntax parse, project-file validation, and ZIP integrity checks performed in this environment.
- Full Xcode compilation and macOS Keychain/permission runtime behavior require testing on the user's Mac.
