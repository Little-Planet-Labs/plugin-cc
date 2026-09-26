---
name: web-design
description: How Little Planet Factory agents build web pages and sites on any framework (plain HTML, Next.js, Astro, Vite SPAs, and similar). Firm defaults unless the user asks otherwise - no em-dashes in tab titles, and every site gets a favicon, a unique descriptive title per page, a meta description, and an Open Graph social card. Covers SEO and crawlability (titles, descriptions, canonicals, robots, sitemaps, lang and hreflang, structured data, mobile-first indexing, Core Web Vitals), the icon set and manifest, social cards and unfurlers, theming meta, accessibility, and compositor-friendly animation. Use when building or reviewing any website or web page. Framework implementations live elsewhere - load nextjs for how to do this in Next.js, and vercel for Vercel Analytics and Speed Insights.
user-invocable: false
---

# Web design

This skill states what every web page and site needs, independent of framework. It doesn't say how to wire it up in a given stack. The `nextjs` skill implements these rules in Next.js (the Metadata API, `opengraph-image`, `next/image`, `app/sitemap.ts`, and `app/robots.ts`). The `vercel` skill covers Vercel Web Analytics and Speed Insights.

## Firm defaults

Apply these unless the user asks otherwise.

- **No em-dashes in tab titles.** Separate page and site name with a spaced hyphen (` - `) by default. Google also accepts a colon or a pipe.
- **Every site gets the baseline set:** a favicon, a descriptive and unique title on every page, a meta description, and a social card (an Open Graph image). On Next.js the OG image is generated dynamically, per `nextjs`.
- **On Vercel, Web Analytics and Speed Insights are always on.** See `vercel`.

## SEO and crawlability

- **Titles** are unique and descriptive on every page. Avoid a vague "Home", boilerplate repeated across pages, and keyword stuffing. Put the brand at the start or end, after a hyphen, colon, or pipe. Google documents no length limit and truncates to fit the device width, so don't enforce a character count.
- **Meta descriptions** are unique and accurate per page, written as a summary, not a keyword list. There's no length limit. Google uses the description only sometimes and may build the snippet from page text instead.
- **Canonical** is `<link rel="canonical">` with an absolute URL, self-referential on the canonical page itself. It's a strong signal, not a directive. Never try to canonicalize with robots.txt.
- **robots.txt doesn't keep a page out of the index.** A disallowed URL can still be indexed if it's linked from elsewhere. To keep a page out, use `<meta name="robots" content="noindex">`, or an `X-Robots-Tag` header for non-HTML resources, and make sure robots.txt does NOT block that page. A blocked page is never crawled, so Google never sees its `noindex`.
- **Sitemaps** hold at most 50MB uncompressed or 50,000 URLs per file, all absolute. Google ignores `<priority>` and `<changefreq>`, and uses `<lastmod>` only when it's consistently accurate. Derive `lastmod` from real content changes, never from the build time or the clock.
- **`lang` on `<html>` is required** (WCAG 3.1.1, Level A). Google doesn't use `lang` or `hreflang` to detect a page's language, so `lang` is an accessibility requirement, not an SEO lever.
- **hreflang:** each language version lists itself and every other version, with absolute URLs, plus an `x-default`.
- **Structured data** uses JSON-LD. It must describe content visible on the page. Never mark up what users can't see. Validate with the Rich Results Test (https://search.google.com/test/rich-results).
- **Escape JSON-LD correctly.** Serialize with `JSON.stringify`, then replace every `<` with `\u003c` (in JS: `.replace(/</g, '\\u003c')`). Never HTML-entity-encode it: `<script>` content is raw text, so `&lt;` stays literal and corrupts the JSON.
- **Mobile-first indexing.** Google indexes the mobile version. Keep content, structured data, titles, and descriptions identical across mobile and desktop, and prefer responsive design over separate mobile markup.
- **Viewport** is `<meta name="viewport" content="width=device-width">`. Never disable zoom (`user-scalable=no`, `maximum-scale=1`): WCAG requires text to scale to 200%. On notched devices, add `viewport-fit=cover` and pad with the safe-area insets.
- **Core Web Vitals** are measured at the 75th percentile, for mobile and desktop separately: LCP at most 2.5s, INP at most 200ms, CLS at most 0.1.
- **Alt text** is descriptive and fits its context, with no keyword stuffing. Decorative images get `alt=""`, never a missing `alt`. Content images are real image elements (`next/image` in Next.js), not CSS backgrounds, because Google doesn't index CSS background images.

## Icons

- **Declare every icon explicitly.** A browser may fetch `/favicon.ico` only when the page has no `<link rel="icon">`, and that fallback is optional. iOS probes `/apple-touch-icon*.png` at the root only when no apple-touch-icon link exists. Everything else, including the web manifest and the icons it lists, is fetched only through `<link>` and `<link rel="manifest">`. An unlinked manifest does nothing. A tab icon that shows up proves nothing about the rest of the set.
- **Google Search favicon:** square (1:1), at least 8x8 and ideally larger than 48x48, in BMP, GIF, ICO, PNG, JPEG, PPM, or TIFF. SVG isn't on Google's list, so ship a raster favicon alongside any SVG one. One favicon per hostname, declared on the home page, at a stable URL that Googlebot and Googlebot-Image can crawl.
- **apple-touch-icon:** a square, fully opaque 180x180 PNG. iOS rounds the corners itself. What iOS puts behind transparent pixels is undocumented and varies, and there's no supported way to ship dark or tinted variants for web clips. On iOS and iPadOS 26, manifest icons are used when present.
- **Manifest icons get exactly one `purpose` per entry.** The spec allows `"any maskable"`, but maskable art used as `any` looks padded, and `any` art used as maskable gets cropped. Ship separate entries, and keep maskable key art inside the W3C safe zone, a centered circle 80% of the icon's diameter.

## Social cards

- **Open Graph required properties:** `og:title`, `og:type`, `og:image`, and `og:url`, with absolute URLs. Add `og:description` and `og:image:alt`.
- **The image** is at least 1200x630 (about 1.91:1) and at most 8MB.
- **Add `twitter:card` set to `summary_large_image`.** X falls back to the OG tags for `twitter:title`, `twitter:description`, and `twitter:image`, per its historical docs.
- **Treat unfurlers as stateless.** None document cookie handling, so assume they send none. A cookieless `GET` of the page must reach a 200 HTML response carrying the OG tags, with no cookie-dependent redirects in the way. Check with `curl -sL` and no cookie jar.
- **Verify before shipping.** Unfurlers cache what they fetch, so a broken card can outlive its fix.
- **A server-rendered social image or feed route is a pure function of its URL** when a CDN caches it. See `nextjs` and `vercel` for the details.

## Theming meta

- **`<meta name="theme-color">`** accepts `media="(prefers-color-scheme: light)"` and `(prefers-color-scheme: dark)` variants. It works in Chrome on Android and in Safari, not in desktop Firefox, and isn't Baseline, so treat it as an enhancement.
- **Declare color schemes** with `<meta name="color-scheme" content="light dark">` (the first value is preferred) plus the CSS `color-scheme` property. `only light` is valid. `only dark` is not.
- **The light/dark policy is a per-project product decision.** Decide it and document it in the project.

## Accessibility and motion

- **Native `disabled` removes a control from the tab order** and blocks click, mousedown, and mouseup, so keyboard users can't focus it or reach its tooltip. When a control must stay focusable or explain why it's unavailable, use `aria-disabled="true"` with a handler that guards against activation.
- **Check contrast numerically, not by eye.** WCAG 1.4.3 (AA) requires 4.5:1 for body text and 3:1 for large text (at least 18pt, or 14pt bold). Measure text over photos and gradients at its worst point.
- **Gate every custom animation behind `prefers-reduced-motion`.**
- **Animate `transform` and `opacity`**, never `width`, `height`, or other layout properties. For a growing bar, use `transform: scaleX()` with `transform-origin`. Lighthouse flags the rest as non-composited animations.

## Splitting web work across agents

These page-level files are shared by every route. Each has exactly one owner:

- the root HTML template, document, or root layout (head tags, `lang`, theme meta);
- the icon set and the web manifest;
- robots and the sitemap;
- global CSS and the token or theme files;
- the site-wide social card.

Route-level titles, descriptions, and social cards go with their route's unit. A unit that needs a change to a shared file reports the exact addition to its owner.

## Review focus

Inspecting web page changes, weight these: a missing or duplicated title, or one containing an em-dash; a missing meta description or canonical; `noindex` pages that robots.txt blocks; an undeclared icon set, or a manifest icon with combined `any maskable` purposes; a missing or broken OG card, or a page that fails a cookieless GET; JSON-LD that isn't escaped with `\u003c`, or that doesn't match visible content; disabled zoom; a missing `lang`; a missing `alt`, or non-empty alt text on decorative images; native `disabled` where the control needs focus; animations not gated by reduced motion; and animations of layout properties.
