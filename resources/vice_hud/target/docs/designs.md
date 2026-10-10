# Interface Designs

**osm-target** ships with the **Context Rail** design. The interface is packaged as a modular pack in the `designs/` directory, and further packs can be authored against the Design SDK — see [Design Packs](./design-packs.md) for installation, management and authoring details.

The `/targetadmin` panel automatically enumerates currently installed designs. Tunable configurations are stored independently per design, preserving custom settings across design switches and pack reinstalls.

---

## Context Rail (`rail`)

<table>
<tr>
<td width="50%"><img width="100%" alt="Context Rail — vehicle options" src="media/rail-1.png" /></td>
<td width="50%"><img width="100%" alt="Context Rail — badges and position counter" src="media/rail-2.png" /></td>
</tr>
<tr>
<td width="50%"><img width="100%" alt="Context Rail — gated rows explain themselves" src="media/rail-3.png" /></td>
<td width="50%"><img width="100%" alt="Context Rail — opened to the left" src="media/rail-4.png" /></td>
</tr>
</table>

**Concept**: A vertical rail pinned to the entity, drawn straight onto the world with no panel behind it. Options hang off the rail as nodes; scrolling walks them past the focus node, which sits exactly on the world point the player is aimed at.

- **Focus Mechanics**: The focused node opens into a ring carrying the confirm glyph and its label grows to the emphasis size. Neighbouring rows stay legible but recede with distance from the focus, and rows outside the window fade out rather than pop.
- **Gated Rows Explain Themselves**: An ineligible row swaps its node for a padlock and prints its requirement underneath *without* the player having to scroll onto it, so a list reads as gated at a glance.
- **Key Tunables**:
  - `listSide`: Opening direction (`right`, `left`). The world anchor offset follows automatically.
  - `listWidth`: Width of the label column before text truncates (320px–820px).
  - `visible`: Number of rows in view simultaneously (3–8). Longer lists scroll through the window.
  - `anchorMode`: `slot` parks the focused row on the entity and slides the list past it; `list` holds the rows still and walks the focus down them, scrolling only at the window edges.
  - `focusEmphasis`: Size of the focused label against the rest of the list (100%–145%).
  - `confirmGlyph`: Mark inside the focused node (`cross`, `mouse`, `dot`, `none`).
  - `railStyle`: Hairline through the nodes, bare nodes, or nothing at all.
  - `rowIcon`: Whether a registered option icon is drawn beside its label (`none`, `focus`, `all`).
  - `submenuGlyph`, `counter`: Nested-menu mark, and a `3 / 7` position readout for long lists.
  - `scrim` & `textOutline`: Soft background darkening and the contrast shadow under every glyph — the two controls that keep white type readable against a white fridge door.
  - `fontFamily`: Condensed typeface (Barlow Semi Condensed, Oswald, Saira Condensed, Archivo Narrow, Plus Jakarta Sans).

> The condensed faces are fetched from Google Fonts on first use. A server with no outbound font access still renders the design correctly, falling back to a system face.

---

## Text Fitting & Label Management

Because option labels originate from external scripts with varying lengths, text handling is fully configurable across all designs:

1. **Label Wrapping (`labelLines`)**: Under the **Typography** settings group, configure whether option text is restricted to a single line or allowed to wrap to 2 or 3 lines before applying truncation.
2. **Width Controls**: Each design provides a dedicated width control (`listWidth` here) to accommodate server-specific label conventions.
3. **Texture Boundary Clipping**: Dimensions are automatically constrained within DUI canvas limits to prevent visual clipping.
