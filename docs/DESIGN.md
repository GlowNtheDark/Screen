# TV design and interaction

The [Screen roadmap](../Documentation/Screen-UI-Roadmap.md) establishes fixed dark
surfaces, square geometry, and a media-first layout. Current TV code follows these
conventions through [Color.swift](../Shared/Extensions/Color.swift),
[BasicHoverButtonStyle.swift](../Shared/Extensions/ButtonStyle/BasicHoverButtonStyle.swift),
and [MainTabView.swift](../Shared/Coordinators/Tabs/MainTabView.swift).

- Use the existing `screenDeepNavy` background and Ice Blue (`#2EA8FF`) accent.
  The background should not change with the focused title.
- Prefer square geometry for Screen-owned controls/artwork. Reuse existing styles;
  do not impose a new design system on unrelated screens.
- General buttons communicate focus with an outline, restrained glow, and small scale.
  Focus treatment is surface-specific: Search uses compact outline controls and
  Play Next currently uses neutral dark actions. Preserve those distinctions.
- Home poster artwork stays at a fixed scale during focus movement; its outline,
  restrained accent halo, and press feedback remain active. Home uses a 10% opacity
  focus halo and no completed-progress glow; the focused outline and completed bar
  remain unchanged.
- Unfocused Home posters use 85% title opacity and an 8% black artwork overlay;
  focused posters restore full title and artwork emphasis with a 0.1-second ease-out.
  Secondary metadata, badges, progress indicators, and shelf headings are unaffected.
- Use the collapsible sidebar and direct entry into media rows. Section headings
  are labels, not extra navigation destinations. Keep routine profile information
  out of the main menu/content screens.
- Keep metadata readable at television distance and artwork prominent. Retain
  existing safe-area, clipping, and long-title handling when making local changes.
- Search has an app-owned field/character-strip focus flow in
  [SearchView.swift](../Shared/Views/SearchView.swift); its TV entry differs from iOS `.searchable`.

Navigation and focus mechanics are mapped in [navigation-stack](design-docs/navigation-stack.md)
and [focus-system](design-docs/focus-system.md). Validate actual remote movement and
layout using [QUALITY.md](QUALITY.md); static styles alone do not establish usability.

The upstream [contribution guide](../Documentation/contributing.md) says there are
no UI guidelines and describes a Jellyfin theme. That is retained upstream context;
the Screen conventions above reflect the local roadmap and implementation.
