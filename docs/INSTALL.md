# Installing ordino

ordino is free and isn't notarized by Apple (that needs a paid developer account), so macOS asks you to confirm the first launch. This happens **once**: updates install without it.

1. Download `ordino-<version>.zip` from the latest release and double-click it.
2. Drag **ordino.app** into **Applications**.
3. Open it. macOS says it can't verify the developer. Click **Done** (not "Move to Trash").
4. Open **System Settings > Privacy & Security**, scroll down to the message about ordino and click **Open Anyway**, then confirm.
5. ordino shows its welcome window. Click **Open System Settings** and turn on **ordino** under **Accessibility**. ordino notices by itself and continues.

That's it. Press **⌥⌘A** to arrange the display under the mouse.

## Updates

ordino checks for updates once a day and installs them when you quit it, or right away from **Check for updates…** in its menu. Every update is signed; ordino refuses one that isn't.

The Accessibility permission stays on across updates. One exception: updating from **0.1.0-beta.2** (the first beta, signed differently) asks for it once more.

## Uninstalling

1. Quit ordino from its menu and delete `/Applications/ordino.app`.
2. Remove it from **System Settings > Privacy & Security > Accessibility** (select it, click **–**).
3. Optional: `defaults delete io.github.xsugra.ordino` removes its settings.
