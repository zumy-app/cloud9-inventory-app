---
name: Thermal Utility Grid
colors:
  surface: '#f9f9f9'
  surface-dim: '#dadada'
  surface-bright: '#f9f9f9'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f3f4'
  surface-container: '#eeeeee'
  surface-container-high: '#e8e8e8'
  surface-container-highest: '#e2e2e2'
  on-surface: '#1a1c1c'
  on-surface-variant: '#5a4136'
  inverse-surface: '#2f3131'
  inverse-on-surface: '#f0f1f1'
  outline: '#8e7164'
  outline-variant: '#e2bfb0'
  surface-tint: '#a14000'
  primary: '#a14000'
  on-primary: '#ffffff'
  primary-container: '#ff6a00'
  on-primary-container: '#571f00'
  inverse-primary: '#ffb694'
  secondary: '#515e7f'
  on-secondary: '#ffffff'
  secondary-container: '#c9d7fe'
  on-secondary-container: '#505d7e'
  tertiary: '#5e5e5e'
  on-tertiary: '#ffffff'
  tertiary-container: '#989898'
  on-tertiary-container: '#303030'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffdbcc'
  primary-fixed-dim: '#ffb694'
  on-primary-fixed: '#351000'
  on-primary-fixed-variant: '#7b2f00'
  secondary-fixed: '#d9e2ff'
  secondary-fixed-dim: '#b9c6ed'
  on-secondary-fixed: '#0c1a39'
  on-secondary-fixed-variant: '#394666'
  tertiary-fixed: '#e2e2e2'
  tertiary-fixed-dim: '#c6c6c6'
  on-tertiary-fixed: '#1b1b1b'
  on-tertiary-fixed-variant: '#474747'
  background: '#f9f9f9'
  on-background: '#1a1c1c'
  surface-variant: '#e2e2e2'
typography:
  price-hero:
    fontFamily: Barlow Condensed
    fontSize: 34px
    fontWeight: '800'
    lineHeight: 32px
    letterSpacing: -0.03em
  price-cents:
    fontFamily: Barlow Condensed
    fontSize: 18px
    fontWeight: '700'
    lineHeight: 18px
    letterSpacing: -0.01em
  price-unit:
    fontFamily: Space Mono
    fontSize: 8px
    fontWeight: '700'
    lineHeight: 10px
    letterSpacing: 0em
  product-title:
    fontFamily: Barlow Condensed
    fontSize: 12px
    fontWeight: '700'
    lineHeight: 13px
    letterSpacing: 0.01em
  product-subtitle:
    fontFamily: Space Grotesk
    fontSize: 8px
    fontWeight: '500'
    lineHeight: 9px
    letterSpacing: 0.02em
  barcode-numeral:
    fontFamily: Space Mono
    fontSize: 8px
    fontWeight: '400'
    lineHeight: 9px
    letterSpacing: 0.08em
  badge-label:
    fontFamily: Barlow Condensed
    fontSize: 9px
    fontWeight: '800'
    lineHeight: 10px
    letterSpacing: 0.05em
  metadata-micro:
    fontFamily: Space Mono
    fontSize: 6px
    fontWeight: '500'
    lineHeight: 7px
    letterSpacing: 0.02em
spacing:
  gutter: 0.0625rem
  margin: 0.09375rem
  space-xs: 0.03125rem
  space-sm: 0.0625rem
  space-md: 0.125rem
  space-lg: 0.1875rem
  space-xl: 0.25rem
---

## Brand & Style

This design system establishes a high-density, hyper-legible shelf edge signage language engineered specifically for 203 DPI and 300 DPI direct thermal printers, with a mirrored digital preview palette reflecting Cloud 9 Kitchen & Market's identity. 

The aesthetic is functional brutalism combined with precision retail utility: 
- **Physical Output:** Strict 1-bit monochrome bitmap rendering, zero anti-aliasing artifacts, hairline knockout blocks, ink-bleed conscious padding, and maximum contrast ratios.
- **Digital Preview Environment:** Powered by the brand's signature high-energy citrus orange (`#FF6A00`) and deep structural midnight navy (`#081735`), allowing store associates and inventory managers to inspect scan targets, promo flags, and compliance badges with absolute fidelity before sending jobs to thermal print heads.
- **Atmosphere:** Industrial, rapid-glance scanability, robust, and zero-compromise efficiency for convenience store floor operations.

## Colors

The palette operates under a dual-state operational pipeline: **Physical Print Mode (1-bit monochrome)** and **Digital Proof Mode (Multi-channel preview)**.

### Color Tokens & Usage
- **Primary (`#FF6A00` - Cloud 9 Solar Orange):** Reserved in digital previews for special promotional callouts, clearance badges, "Grab & Go" meal flags, and interactive selection states in the label generator software. Prints as 100% black reverse-knockout text or dense hatched thermal patterns.
- **Secondary (`#081735` - Midnight Navy):** Serves as the digital stand-in for deep ink/black text, providing brand personality while maintaining a 16.2:1 contrast ratio against white paper backing. Translates to direct `#000000` on thermal media.
- **Tertiary (`#000000` - Thermal Carbon Black):** The strict target for direct thermal physical transfer. Zero half-toning, zero dithering on critical scannable areas (UPC-A, Code 128, QR).
- **Neutral (`#FFFFFF` - Pure Matte Thermal Stock):** The clean reflective background ensuring 98%+ reflectance for handheld laser and imager barcode readers.

### Functional States
- **Thermal Invert Blocks:** Black backgrounds with knocked-out white typography are strictly budgeted to less than 35% of total tag surface area to avoid thermal print head overheating and curl.

## Typography

Typography is strictly selected to maximize horizontal glyph density and vertical legibility on micro-scale 2-inch by 1-inch (406 × 203 dots at 203 DPI) labels.

- **Primary Display (Barlow Condensed):** Delivers ultra-impactful pricing numerals and product titles. Its condensed proportions allow 18-24 characters across a single line while retaining generous optical counters that resist thermal bleed.
- **Structural Body (Space Grotesk):** Applied to product descriptions, pack sizes, and net weights. The geometric clarity prevents stroke clogging on porous direct thermal label stock.
- **Data & Barcode Annotations (Space Mono):** Fixed-pitch numerals guarantee consistent vertical alignment beneath barcode symbologies (UPC-A, EAN-13, Code 128) and unit pricing metrics ($/oz, $/lb).

### Print Optimization Rules
- All numerals smaller than 9px utilize open counters.
- Currency symbols (`$`) sit superscripted at 55% scale of the integer size to prevent wasting vertical baseline space.

## Layout & Spacing

A 2.00" × 1.00" physical label footprint equates to 406 × 203 pixels at 203 DPI, or 600 × 300 pixels at 300 DPI. Spacing tokens operate on strict dot-multiples (sub-quarter rem equivalents) to prevent optical antialiasing jitter.

### Layout Architecture
- **Outer Margins (`margin` / 1.5mm / ~12px at 203 DPI):** The mandatory quiet zone required along the label perimeter to absorb thermal feeder skew and peeling tolerances.
- **Split Horizontal Architecture:** 
  - **Upper Zone (Height: 38%):** Brand header line, product category, primary 2-line title, and pack volume.
  - **Lower Left Quadrant (Width: 52%):** Strict UPC/Code 128 barcode area with mandatory left/right quiet margins (minimum 10 modules wide).
  - **Lower Right Quadrant (Width: 48%):** Price hero lockup, including unit pricing computation block and promo flags.
- **Dividers:** 1px hairline horizontal or vertical separation tracks (`#000000`) placed at `space-xs` distance from text baselines.

## Elevation & Depth

Thermal labels do not support drop shadows, atmospheric blurs, or gradients. Depth and visual hierarchy are generated purely through structural contrast and tactile line containment:

- **Knockout Blocks (Negative Elevation):** Solid black (or solid orange in digital proofing) fill rectangular chips housing inverted white text. Used exclusively for "SALE", "PROMO", "ORGANIC", or snap-grab callouts.
- **1-Bit Micro Borders:** Solid 1px and 2px enclosing containers that establish section boundaries between machine-scannable inventory data and human-readable price data.
- **No Halftoning:** Shading gradients and grey transparencies are prohibited to ensure 100% scanning pass rate through handheld POS terminals.

## Shapes

The shape system is strictly sharp (`0`), engineered around pixel-exact edge rendering for thermal thermal transfer ribbons and direct burn heads:

- **Perpendicular Sharp Edges (0px radius):** Prevents aliased stairstepping on low-resolution thermal burns. Every barcode border, container outline, badge, and category tag is built on true 90-degree corners.
- **Barcode Windows:** Crisp, uninterrupted rectangular boxes maintaining ISO/IEC 15416 print quality compliance.
- **Digital Preview Tags:** Render with zero corner radius to accurately depict physical die-cut adhesive peel edges.

## Components

### 1. Standard Price Tag (2" x 1")
- **Header Strip:** Micro-metadata including aisle, shelf slot, and last verified date in `metadata-micro`, anchored left. Brand mark abbreviation right-aligned.
- **Product Title:** Two truncated lines of `product-title`, condensed bold, auto-wrapping without hyphenation.
- **Barcode Bay:** Houses a Code 128 or UPC-A barcode with 0.35" bar height, centered with its human-readable digit string below in `barcode-numeral`.
- **Price Block:** 
  - Currency symbol aligned top-left of the dollar numeral.
  - Big integer in `price-hero`.
  - Cents raised in `price-cents`.
  - Unit price bracketed underneath in a crisp bordered micro-cell.

### 2. Promo / "Special Value" Tag
- **Inverted Banner:** Top 0.22" filled in solid thermal black (`#FF6A00` in preview) displaying "CLOUD 9 SPECIAL" or "2 FOR $5.00" in crisp inverted white `badge-label`.
- **Strike-through Matrix:** Regular retail price rendered in strikethrough `metadata-micro` directly above promotional price.

### 3. Kitchen / Grab & Go Prep Label
- Contains an inline square 2D QR Code (0.45" x 0.45") linking to nutritional allergen tables and ingredients, counterbalanced by heating instructions and "Best By" thermal datestamp block.

### 4. Interactive Label Builder Elements (Digital Application)
- **Print Preview Viewport:** Shows 1:1 real-size physical preview next to scaled 300% zoom with DPI grid lines overlay.
- **Action Buttons:** Flat, crisp rectangles bordered with 1.5px `#081735`, filled with vibrant `#FF6A00` for primary "Batch Print", zero border-radius.
- **Status Chips:** Mono-spaced compact tags indicating "Thermal Ready", "Barcode Validated", or "Margin Warning".