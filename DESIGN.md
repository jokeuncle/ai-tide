---
name: AI 潮汐
description: Native macOS network activity, rendered as jade and copper tides.
colors:
  graphite: "rgb(7.5% 8.4% 8.5%)"
  text: "rgb(94% 93% 90%)"
  muted: "rgb(66% 69% 68%)"
  jade: "rgb(62% 85% 72%)"
  copper: "rgb(94% 67% 49%)"
  control: "rgb(100% 100% 100% / 7%)"
  control-pressed: "rgb(100% 100% 100% / 15%)"
  selected: "rgb(100% 100% 100% / 10%)"
typography:
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "27px"
    fontWeight: 500
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "19px"
    fontWeight: 600
  metric:
    fontFamily: "SFMono-Regular, ui-monospace, monospace"
    fontSize: "17px"
    fontWeight: 400
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12px"
    fontWeight: 500
rounded:
  control: "7px"
  segment: "6px"
  selector: "9px"
spacing:
  inline: "8px"
  control-horizontal: "14px"
  section: "24px"
  inspector: "28px"
components:
  button:
    backgroundColor: "{colors.control}"
    textColor: "{colors.text}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "8px 14px"
  button-pressed:
    backgroundColor: "{colors.control-pressed}"
  segment-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.text}"
    rounded: "{rounded.segment}"
    width: "73px"
    height: "28px"
---

# Design System: AI 潮汐

## Overview

**Creative North Star: "Jade and Copper Tides"**

A quiet native macOS instrument: two luminous material sculptures sit on graphite, with precise measurements and ruled traffic history below. The sculptures supply atmosphere; controls, text and charts stay restrained and legible. This captures the approved graphite/jade/copper direction as implemented in SwiftUI, rather than the earlier concept's approximate color values.

**Key Characteristics:**
- Native window behavior and SF typography.
- Jade for Codex or ChatGPT; copper for Claude Code.
- Spacious primary visualization with compact supporting measurements.
- Visible source, state and coverage information.

Actual implementation reference: `docs/screenshot.png` and `Sources/Tide/TideApp.swift`. `docs/concept.png` is a static design reference, never evidence of live activity. Typography and layout values below represent SwiftUI points; CSS units in the portable tokens describe equivalent documentation previews.

## Colors

### Primary

Jade identifies the selected OpenAI client, its directional arrows, chart and native control tint. Copper identifies Claude Code and signals collection errors. Client colors remain consistent across the main view, timeline, source inspector and menu-bar window.

### Neutral

Graphite is the continuous canvas. Warm off-white text carries readings and names; muted gray-green carries status, explanatory copy and chart labels. Controls use translucent white fills and fine white strokes, with stronger fills for selection or press.

**The Client Color Rule.** Keep client identity separate from traffic direction: both receive and send use the client's color; line style and arrow direction distinguish them. Do not introduce blue controls.

## Typography

Use native SF system typography and native SF Symbols. Client names use the headline role; the application heading uses title. Readings use monospaced digits and the metric role. Most status and chart labels are compact (10–12 points); inspector titles are larger (24 points). Keep these secondary labels subordinate to the sculpture, client name and rate.

## Layout

The main window opens at 1120 × 810 points, with a minimum content size of 980 × 750. The header is 58 points high, with native traffic-light clearance at the leading edge. Two equal-width client columns sit above a full-width, ruled 60-second chart region and a 36-point source footer. Orb artwork scales proportionally within its column and stays clipped to its reserved visualization area.

The timeline view expands the two charts vertically. The source inspector is a 900 × 650-point sheet with aligned PID, identity, origin and rate columns. The menu-bar window is compact (330-point content width), with two client rows, collection status and explicit open/pause/quit actions. These are native window arrangements, not web breakpoints.

## Elevation & Depth

Depth comes from the original translucent jade/copper artwork, a darker chart region and quiet hairline dividers. Avoid decorative card shadows around each client. Particle streams and low elliptical ripples are Canvas overlays whose intensity derives from measured byte rates. Reduced motion, pause and zero activity stop the animation; unavailable data dims the sculpture.

## Shapes

Large unboxed client columns preserve the sculpture silhouettes. Small rounded native controls use the control radius; segmented navigation uses the selector shell and smaller segment radius. Native window corners and traffic lights belong to macOS. Do not recast the view as a grid of dashboard cards.

## Components

**Controls:** restrained translucent white buttons with a fine white border, stronger press fill and native keyboard behavior. The segmented Tide/Timeline control uses a brighter selected fill and semibold label. Source and pause icons expose action-specific accessibility labels. Preserve keyboard access and native focus behavior.

**Sculptures and rates:** original standalone artwork, never a crop of the concept UI. Receive and send sit side by side beneath each name with a thin separator. Missing readings show an em dash; status text remains visible below. The OpenAI selector distinguishes Codex from ChatGPT.

**Traffic charts:** receive is a solid line; send is thinner, dimmer and dashed. Each client has its own labeled vertical scale. Missing samples and gaps break the curve; they must not be interpolated as zero. Keep the 60-second time labels, line-style legend and local history reset.

**Source inspector:** aligned factual rows with selectable diagnostic text, a native completion action and disabled export until a sample exists. Keep scope and coverage notes attached to the data.

**Menu-bar window:** repeat client names, rates and per-client state in a compact form. Its header distinguishes connecting, paused, stale, collection error and measured states; preserve the source/coverage footer.

## Do's and Don'ts

- **Do** preserve the jade/copper identity mapping across all native surfaces.
- **Do** distinguish baseline collection, unavailable data, inactive process, no visible connection, pause and collection errors with text.
- **Do** keep source and coverage limits visible in every live panel.
- **Do** use measured rates for animation and support reduced motion.
- **Don't** imply tokens, model thinking, costs or request counts from network bytes.
- **Don't** draw activity particles for quiet or unavailable sources.
- **Don't** replace native controls with blue accents or surround every reading with a card.

This documentation describes the preview interface. The release remains an ad-hoc signed, unnotarized preview; Intel is untested. Visual approval does not change those distribution facts.
