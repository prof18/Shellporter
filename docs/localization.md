# Localization

Shellporter uses SwiftPM resources + `.strings` files, without Xcode string catalogs.

## Structure

- String access in code: `Sources/Shellporter/Localization/AppStrings.swift`
- English source strings: `Sources/Shellporter/Resources/Localization/en.lproj/Localizable.strings`
- SwiftPM setup: `Package.swift` with:
  - `defaultLocalization: "en"`
  - target resources processing `Sources/Shellporter/Resources`

## Add or update a string

1. Add a new `static let` in `AppStrings.swift` in the relevant namespace.
2. Use a lowercase kebab-case key (for example, `menu-open-with`).
3. Add the same key in `en.lproj/Localizable.strings` with the English text as value.
4. Use `AppStrings.*` in UI/app code instead of inline text.

## Add a new language

1. Create `Sources/Shellporter/Resources/Localization/<lang>.lproj/Localizable.strings`.
2. Copy keys from `en.lproj/Localizable.strings`.
3. Translate values.

Example for Italian:

- `Sources/Shellporter/Resources/Localization/it.lproj/Localizable.strings`

## Notes

- Keep keys stable and only change values when possible.
- Use lowercase kebab-case keys only (no spaces, no capitals).
