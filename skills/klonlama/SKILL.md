---
name: klonlama
description: >
  Use when the user wants to clone, copy, replicate, or rebuild a website,
  recreate a landing page, reverse-engineer a site's design, migrate a site's frontend,
  or create a high-fidelity reproduction of any web page. Also triggers when users say
  "make it look exactly like this site", "copy this design", "I want the same layout as X",
  "rebuild this page", or share a URL asking to replicate it.
---

# Klonlama Skill

Clone any website at 90-95% visual fidelity using a section-by-section extraction and
rebuild approach. No external paid APIs needed — uses only Claude Code's built-in
browser automation (Playwright MCP or computer use) and standard CLI tools.

## Why Section-by-Section?

Cloning an entire page in one shot produces ~60-70% accuracy because:
- The context window gets polluted with too much information
- CSS values get "guessed" instead of extracted
- Spacing and layout drift accumulates across the page
- Errors in one section cascade into others

Section-by-section solves all of these. Each section is a small, focused task with its
own extraction → build → verify cycle.

---

## Prerequisites

Before starting, verify these tools are available:

```bash
# Check Node.js (needed for Playwright and dev server)
node --version  # Should be 18+

# Check if Playwright is available via MCP
# If not, install it:
npx -y playwright install chromium

# Check wget (for asset downloading)
which wget || which curl
```

If Playwright MCP is configured, use it directly. If not, write and execute Playwright
scripts via bash. Both approaches work — the key is browser access for screenshots and
DOM inspection.

---

## Workflow Overview

```
PHASE 1: Reconnaissance
  1.1 Screenshot (desktop/tablet/mobile)
  1.2 Section map
  1.3 Global design tokens + @font-face (resolved URLs)
  1.4 Smooth scroll library detection (Lenis/Locomotive)
  1.5 Mandatory Interaction Sweep → BEHAVIORS.md
  1.6 Responsive sweep comparison

PHASE 2: Asset Collection
  2.1-2.4 (images, SVGs, bg-images, binding map)

PHASE 3: Section-by-Section Cloning
  3.1 Section screenshots (3 viewport)
  3.2 Deep CSS extract
  3.2b Component tree extraction
  3.3 HTML structure
  3.3b Hover state extraction
  3.4a Write spec file → docs/research/components/<name>.spec.md
  3.4b Dispatch PARALLEL builder agents (each writes its own component file)
  3.5 Visual comparison loop
  3.6 Orchestrator review → pixel-perfect verification + fix dispatch

PHASE 4: Assembly & Final QA
```

---

## PHASE 1: Reconnaissance

### Step 1.1 — Open and Screenshot the Target (3 viewport ZORUNLU)

Sayfayi UC farkli viewport'ta screenshot'la. Bu adim responsive davranisi tespit
etmek icin sart — section extract edilirken her 3 viewport'ta karsilastirma yapilir.

```javascript
// Use Playwright to navigate and capture at 3 viewports
const { chromium } = require('playwright');
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(TARGET_URL, { waitUntil: 'networkidle' });

// 1. Desktop
await page.screenshot({ path: 'reference/full-page-desktop.png', fullPage: true });

// 2. Tablet
await page.setViewportSize({ width: 768, height: 1024 });
await page.waitForTimeout(500);
await page.screenshot({ path: 'reference/full-page-tablet.png', fullPage: true });

// 3. Mobile
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(500);
await page.screenshot({ path: 'reference/full-page-mobile.png', fullPage: true });

// Geri desktop'a don (diger extraction adimlari icin)
await page.setViewportSize({ width: 1440, height: 900 });
```

**Chrome MCP kullaniyorsan:**
```
1. mcp__claude-in-chrome__resize_window({ width: 1440, height: 900 }) → screenshot
2. resize_window({ width: 768, height: 1024 }) → screenshot  
3. resize_window({ width: 390, height: 844 }) → screenshot
4. resize_window({ width: 1440, height: 900 }) → geri dondur
```

Kaydedilecek dosyalar:
- `reference/full-page-desktop.png` — 1440px (ana referans)
- `reference/full-page-tablet.png` — 768px
- `reference/full-page-mobile.png` — 390px

### Step 1.2 — Map the Page Sections

Extract the top-level structure of the page. Run this in the browser context:

```javascript
// Identify major page sections
const sections = await page.evaluate(() => {
  const body = document.body;
  const candidates = [
    ...document.querySelectorAll('header, nav, main, footer, section, [role="banner"], [role="main"], [role="contentinfo"]'),
    ...body.children
  ];

  // Deduplicate and filter to meaningful top-level blocks
  const seen = new Set();
  const results = [];
  for (const el of candidates) {
    if (seen.has(el) || el.offsetHeight < 20) continue;
    seen.add(el);
    const rect = el.getBoundingClientRect();
    results.push({
      tag: el.tagName.toLowerCase(),
      id: el.id || null,
      classes: [...el.classList].join(' '),
      role: el.getAttribute('role'),
      top: rect.top + window.scrollY,
      height: rect.height,
      childCount: el.children.length,
      textPreview: el.textContent?.trim().slice(0, 80)
    });
  }
  return results.sort((a, b) => a.top - b.top);
});
```

This gives you an ordered list of sections from top to bottom. Save as `reference/section-map.json`.

#### Step 1.2b — Visual Wrapper Scan (ZORUNLU — sadece tag-based section map yetmez)

`<header>`, `<section>`, `<main>` tag'leri HTML semantics verir ama GÖRSEL wrapper'i
vermez. WordPress/Elementor/Salient gibi tema sistemlerinde `<header>` tagi genelde
TRANSPARENT bir container'dir; asil renkli/padded olive bar bir `<div id="header-outer">`
veya benzer wrapper div'dir. Bu wrapper'i kacirirsan border-radius, background color,
padding, shadow gibi kritik bilgiler kaybolur ve klon header/section tam genislikte
ve kosesiz renderlanir.

**Zorunlu ikinci pass:** Sayfadaki renkli arka plani, border-radius'u, shadow'u olan
TUM buyuk wrapper div'leri de yakala. Bunlari `visual-wrappers.json` olarak kaydet.

```javascript
const visualWrappers = await page.evaluate(() => {
  const results = [];
  document.querySelectorAll('div, section, header, footer, aside, nav, article').forEach((el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    // Filter: anlamli boyut
    if (r.width < 200 || r.height < 40) return;
    // Filter: gorsel anlami olan wrapper'lar
    const hasColor = s.backgroundColor && s.backgroundColor !== 'rgba(0, 0, 0, 0)' && s.backgroundColor !== 'transparent';
    const hasRadius = s.borderRadius && s.borderRadius !== '0px';
    const hasShadow = s.boxShadow && s.boxShadow !== 'none';
    const hasBgImage = s.backgroundImage && s.backgroundImage !== 'none';
    if (!hasColor && !hasRadius && !hasShadow && !hasBgImage) return;
    results.push({
      tag: el.tagName,
      id: el.id || null,
      class: typeof el.className === 'string' ? el.className.split(' ').slice(0, 4).join(' ') : '',
      rect: {
        x: Math.round(r.left),
        y: Math.round(r.top + window.scrollY),
        w: Math.round(r.width),
        h: Math.round(r.height)
      },
      bg: s.backgroundColor,
      borderRadius: s.borderRadius,
      padding: s.padding,
      margin: s.margin,
      boxShadow: s.boxShadow,
      bgImagePresent: hasBgImage
    });
  });
  // Sort by y position, then by size desc (outer wrappers first)
  results.sort((a, b) => a.rect.y - b.rect.y || (b.rect.w * b.rect.h) - (a.rect.w * a.rect.h));
  return results;
});
```

Save as `reference/visual-wrappers.json`.

**Header icin ozel kontrol — HER ZAMAN calistir:**

```javascript
// Header'in gorsel wrapper'ini bul: sayfanin ust 200px'inde renkli, genis bir div
const headerWrapper = await page.evaluate(() => {
  const candidates = [...document.querySelectorAll('div, header, nav, section')].filter((el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const hasColor = s.backgroundColor && s.backgroundColor !== 'rgba(0, 0, 0, 0)';
    return hasColor && r.top < 200 && r.width > 500 && r.height > 40 && r.height < 200;
  });
  // En dis (buyuk) wrapper'i sec
  candidates.sort((a, b) => {
    const ra = a.getBoundingClientRect();
    const rb = b.getBoundingClientRect();
    return (rb.width * rb.height) - (ra.width * ra.height);
  });
  const el = candidates[0];
  if (!el) return null;
  const s = getComputedStyle(el);
  const r = el.getBoundingClientRect();
  return {
    tag: el.tagName,
    id: el.id,
    class: typeof el.className === 'string' ? el.className : '',
    rect: { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) },
    bg: s.backgroundColor,
    borderRadius: s.borderRadius,
    padding: s.padding,
    margin: s.margin,
    boxShadow: s.boxShadow,
    position: s.position
  };
});
```

Save as `reference/header-wrapper.json`.

**Component yazarken kural:** Eger `header-wrapper.json`'daki wrapper'in rect'i
`<header>` tag'inin rect'inden FARKLIysa (border-radius > 0, y > 0, width < viewport),
bu wrapper'in ozelliklerini (border-radius, bg, padding, margin/y-offset) `<Header>`
component'inin ust dis katmanina UYGULA. `<header>` tag'inin kendisi nested bir
iceride kalsin. Ayni kural hero/footer/her section icin gecerli.

**Ozellikle dikkat:**
- `rect.y > 10` → header'in ustunde body bg gorunur (margin-top / pt-[Ypx])
- `rect.width < viewport` → header yanlarda padding var (body bg gorunur)
- `borderRadius !== "0px"` → header'in kendi arka plani ayri bir wrapper'da, rounded
- `padding: "0px 20px"` → inner horizontal padding'i da ayni ayarla

### Step 1.3 — Extract Global Design Tokens

Before cloning individual sections, extract the page-wide design system:

```javascript
const designTokens = await page.evaluate(() => {
  const body = document.body;
  const computed = getComputedStyle(body);
  const html = document.documentElement;

  // Extract all unique colors used on the page
  const colors = new Set();
  const fonts = new Set();
  document.querySelectorAll('*').forEach(el => {
    const s = getComputedStyle(el);
    colors.add(s.color);
    colors.add(s.backgroundColor);
    if (s.fontFamily) fonts.add(s.fontFamily);
  });

  return {
    bodyBg: computed.backgroundColor,
    bodyColor: computed.color,
    bodyFont: computed.fontFamily,
    bodyFontSize: computed.fontSize,
    bodyLineHeight: computed.lineHeight,
    colors: [...colors].filter(c => c !== 'rgba(0, 0, 0, 0)'),
    fonts: [...fonts],
    viewportWidth: window.innerWidth,
    charset: document.characterSet,
    lang: html.lang || 'en'
  };
});
```

Save as `reference/design-tokens.json`.

Also extract custom font URLs. **KRITIK: @font-face URL'lerini RESOLVE et.**
Relative URL'ler stylesheet'in base URL'sine gore cozulmelidir. Yanlis path font
dosyasi yerine HTML hata sayfasi indirir — bu en sik yapilan hatadir.

```javascript
// DOGRU YONTEM: @font-face URL'lerini stylesheet base URL'sine gore resolve et
const fontFaces = await page.evaluate(() => {
  return [...document.styleSheets].flatMap(ss => {
    try {
      const base = ss.href || window.location.href;
      return [...ss.cssRules].filter(r => r.type === 5).map(r => {
        const urlMatch = r.cssText.match(/url\\("?([^")\\s]+)"?\\)/);
        const relUrl = urlMatch?.[1] || '';
        let absUrl = '';
        try { absUrl = new URL(relUrl, base).href; } catch(e) { absUrl = relUrl; }
        return {
          family: r.style.fontFamily,
          weight: r.style.fontWeight || 'normal',
          resolvedUrl: absUrl  // ← TAM URL, relative degil
        };
      });
    } catch(e) { return []; }
  }).filter(f => f.family && !f.family.includes('FontAwesome') && !f.family.includes('icomoon'));
});
```

**Font indirdikten sonra MUTLAKA dogrula:**
```bash
file public/fonts/*.woff2 public/fonts/*.woff
# "Web Open Font Format" gormalisin
# "HTML document" goruyorsan URL YANLIS — resolve edilen URL'yi kontrol et
```

### Step 1.4 — Smooth Scroll Library Detection (YENI)

Modern sitelerde native scroll yerine Lenis, Locomotive Scroll gibi smooth-scroll
kutuphaneleri kullanilabilir. Varsa tespit et ve klonda ayni library'i kurulur —
yoksa scroll hissi gozle gorulur derecede farkli olur, kullanici fark eder.

```javascript
const scrollLib = await page.evaluate(() => {
  // DOM uzerinde library class'lari
  const hasLenis = !!document.querySelector('.lenis, [class*="lenis"]') || !!window.Lenis;
  const hasLocomotive = !!document.querySelector('.locomotive-scroll, [data-scroll-container]') || !!window.LocomotiveScroll;
  const hasGsap = !!window.gsap || !!window.ScrollTrigger;

  // CSS scroll-snap
  const htmlSnap = getComputedStyle(document.documentElement).scrollSnapType;
  const bodySnap = getComputedStyle(document.body).scrollSnapType;

  // Script tag'lerinde library ara
  const scripts = [...document.querySelectorAll('script[src]')].map(s => s.src);
  const libScripts = scripts.filter(s => /lenis|locomotive|smoothscroll|gsap|scrolltrigger/i.test(s));

  return {
    hasLenis, hasLocomotive, hasGsap,
    scrollSnap: { html: htmlSnap, body: bodySnap },
    libScripts: libScripts.slice(0, 5),
    // Onerilen aksiyon
    recommendation: hasLenis ? 'npm install lenis + setup in layout' :
                    hasLocomotive ? 'npm install locomotive-scroll + setup' :
                    hasGsap ? 'npm install gsap + ScrollTrigger' :
                    'native scroll yeterli'
  };
});
```

Ciktiyi `reference/design-tokens.json`'a ekle. Eger library bulunursa:
- `package.json`'a kur
- `src/app/layout.tsx` veya ana layout'ta baslat
- Klonda ayni scroll hissini olustur

### Step 1.5 — Mandatory Interaction Sweep → BEHAVIORS.md (YENI — ZORUNLU)

Section extraction'dan ONCE sayfadaki TUM davranislari sistematik olarak kesfet.
Bu sayfadan sayfaya degisiyor ve screenshot'larda gorunmuyor — kullanici
klonu actiginda "yasamiyor gibi" hissederse bu adim atlanmis demektir.

**Scroll sweep:** Tarayici MCP ile sayfayi yavasca scroll et, her section'da dur:
- Header gorunumu degisiyor mu? (pozisyon, renk, boyut, shadow) → tam scroll pozisyonu
- Elemanlar viewport'a girerken animate oluyor mu? (fade, slide, scale)
- Parallax katmanlari var mi? (farkli hizda hareket)
- Scroll-snap noktalari var mi? (hangi container'lar)
- Sticky sidebar / nav / tab var mi? (hangi section'da)
- Aktif smooth scroll kutuphanesi fark ediliyor mu?

**Click sweep:** Interaktif gorunen HER elemana tikla:
- Butonlar, tab'lar, pill'ler, kart'lar, link'ler
- Icerik degisiyor mu? (tab content switching)
- Modal, dropdown, accordion aciliyor mu?
- Tab'li section varsa HER TAB'A tikla ve her state'in icerigini kaydet
- Dropdown/menu varsa aciksin screenshot al

**Hover sweep:** Hover state'i olabilecek her elemana hover et:
- Butonlar, kartlar, linkler, gorseller, nav ogeleri
- Degisenleri kaydet: renk, scale, shadow, underline, opacity, rotate
- Transition suresi ve easing

**Responsive sweep:** 3 viewport'ta test:
- Desktop (1440px), Tablet (768px), Mobile (390px)
- Her viewport'ta hangi section'in layout'u degisiyor
- Sutun sayisi, font boyutu, gorunurluk
- Yaklasik breakpoint degerleri

**Ciktiyi `reference/BEHAVIORS.md` dosyasina yaz.** Ornek format:

```markdown
# BEHAVIORS — isautier-ipp.com

## Global Scroll
- Library: none (native)
- Scroll-snap: yok
- Header sticky: yok (header position:fixed, scroll'da degismez)

## Animations on viewport entry
- Intro section heading: fade-in-up (IntersectionObserver, threshold:0.2)
- Metiers cards: stagger fade-in (250ms apart)
- Activites cards: fade-in-scale

## Interactive states
- Metiers cards HOVER:
  - box-shadow: 0 10px 30px rgba(0,0,0,0.15)
  - transform: translateY(-2px)
  - transition: all 0.3s ease
- Arrow ikonu hover: rotate(10deg)
- Buton "Nos métiers" HOVER: bg:#003a73 (darker blue)
- Realisations carousel buttons: drag + snap
- Footer social icons HOVER: border-color:#004C93, color:#004C93

## Tab/state-driven content
- YOK (bu sayfada tab system yok)

## Scroll-triggered behaviors
- Hero'dan asagi scroll'da scroll-down button gorunurlugu azalir
- Intro section elemanlari viewport'a girince animate olur

## Responsive breakpoints
- 1440 → 768: Metiers 3-col → 2-col (≈1000px), sonra 1-col (≈768px)
- 1440 → 390: Intro 2-col → 1-col (stack), fontSize 60px → 40px
- Hero video: her viewport'ta fullscreen
- Realisations carousel: card width 550 → 400 (tablet) → 320 (mobile)
```

**KURAL:** Component yazarken her zaman BEHAVIORS.md'ye bak. Spec dosyasinda
"States & Behaviors" bolumu BEHAVIORS.md'den cekilmelidir.

### Step 1.6 — Responsive Sweep Comparison

Step 1.1'de aldigin 3 viewport screenshot'i yan yana koy ve notlari cikar:

1. Hangi section'lar layout degistiriyor (column → stack)?
2. Hangi breakpoint'te? (yaklasik px)
3. Hangi elemanlar mobilde gizleniyor/gorunuyor?
4. Font boyutlari nasil degisiyor? (h2: 60px → 40px → 30px?)
5. Padding/gap degisiyor mu?

Ciktilari BEHAVIORS.md'nin "Responsive breakpoints" bolumune ekle.

---

## PHASE 2: Asset Collection

### Step 2.1 — Download Images

```javascript
const images = await page.evaluate(() => {
  return [...document.querySelectorAll('img')].map(img => ({
    src: img.src,
    alt: img.alt,
    width: img.naturalWidth,
    height: img.naturalHeight
  }));
});
```

Download each image using wget or curl:
```bash
mkdir -p public/images
# For each image URL:
wget -q -O public/images/image-001.webp "IMAGE_URL"
```

### Step 2.2 — Download SVGs and Icons

```javascript
const svgs = await page.evaluate(() => {
  // Inline SVGs
  const inline = [...document.querySelectorAll('svg')].map((svg, i) => ({
    type: 'inline',
    html: svg.outerHTML,
    index: i
  }));

  // Favicon and icons
  const icons = [...document.querySelectorAll('link[rel*="icon"]')].map(l => l.href);

  return { inline, icons };
});
```

Save inline SVGs to `src/components/icons.tsx` as React components.
Download external icons to `public/`.

### Step 2.3 — Extract Background Images from CSS

```javascript
const bgImages = await page.evaluate(() => {
  const results = [];
  document.querySelectorAll('*').forEach(el => {
    const bg = getComputedStyle(el).backgroundImage;
    if (bg && bg !== 'none') {
      results.push({ selector: el.tagName + (el.className ? '.' + el.className.split(' ')[0] : ''), value: bg });
    }
  });
  return results;
});
```

### Step 2.4 — Image-to-Element Binding Map (ZORUNLU — sayfa sonuna dogru yanlis eslesmeleri onler)

Duz resim listesi YETMEZ. Her gorselin HANGI elemana ait oldugunu, yanindaki metni,
kategori etiketini, ve varsa baska kimlik bilgilerini kaydet. Bu olmadan RealisationsSection,
CTASection, carousel gibi cok resimli yerlerde yanlis eslesme olur.

**Neden gerekli:** Realisations carousel'de 9 proje var, her birinin kendi gorseli var.
Sen "listeden ilk 9 resmi al" dersen, 3. proje (Isoplast) yerine Campuséo'nun resmi gelebilir.
Binding map her project.name → exact image eslesmesini zorunlu kilar.

```javascript
// Her gorselin ait oldugu elemanin METNINI ve YAPISAL KONTEKSTINI yakala
const bindingMap = await page.evaluate(() => {
  // Her img elemanini yakin metin + ancestor struct ile eslesir
  const bindings = [...document.querySelectorAll('img')].map(img => {
    // En yakin card/item container'ini bul
    const container = img.closest('article, .portfolio-item, .nectar-post-grid-item, .card, [class*="item"], li, .wpb_column') || img.parentElement;

    // Container icindeki metinleri topla
    const texts = container ? [...container.querySelectorAll('h1,h2,h3,h4,h5,p,span,a')]
      .map(t => t.textContent?.trim())
      .filter(t => t && t.length > 0 && t.length < 80) : [];

    // Yakin kategori/etiket
    const category = container?.querySelector('.category, .post-cat, [class*="meta"], [class*="tag"]')?.textContent?.trim() || '';

    // Section hangisi? (metiers, activites, realisations, cta, footer...)
    const sectionRow = img.closest('.wpb_row[id^="fws_"]');
    const sectionHeading = sectionRow?.querySelector('h1,h2,h3')?.textContent?.trim().slice(0,30);

    return {
      src: img.src.split('/').pop(),        // Indirilecek dosya adi
      fullUrl: img.src,                      // Orijinal URL
      alt: img.alt,
      renderedW: img.offsetWidth,
      renderedH: img.offsetHeight,
      // BINDING bilgisi — hangi elemana ait
      section: sectionHeading,
      containerTag: container?.tagName,
      containerClass: container?.className?.split(' ').slice(0,2).join(' '),
      // METIN imzasi — hangi kart/item
      nearestTexts: texts.slice(0, 5),
      category,
      // Benzersiz tanimlayici
      identifier: texts[0] || category || `${sectionHeading}-img`
    };
  });

  // Ayrica background-image'lari da yakala
  const bgBindings = [...document.querySelectorAll('*')].filter(el => {
    const bg = getComputedStyle(el).backgroundImage;
    return bg && bg !== 'none' && bg.includes('url(');
  }).map(el => {
    const container = el.closest('article, .portfolio-item, .nectar-post-grid-item, .card, [class*="item"]') || el;
    const texts = [...container.querySelectorAll('h1,h2,h3,h4,p')]
      .map(t => t.textContent?.trim())
      .filter(t => t && t.length > 0 && t.length < 80);
    const bgUrl = getComputedStyle(el).backgroundImage.match(/url\\("?([^"]+)"?\\)/)?.[1] || '';
    return {
      src: bgUrl.split('/').pop(),
      fullUrl: bgUrl,
      type: 'background',
      containerTag: container.tagName,
      containerClass: container.className?.split(' ').slice(0,2).join(' '),
      nearestTexts: texts.slice(0, 5),
      identifier: texts[0] || 'bg-image'
    };
  });

  return { imgBindings: bindings, bgBindings };
});
```

**Save as `reference/image-binding-map.json`.**

**KURAL: Component yazarken binding map'i SOZLUK olarak kullan.**

Ornek — realisations carousel veri yapisi:

```typescript
// YANLIS — listeden tahmin et
const projects = [
  { name: "AURAR", img: "/images/IPP-Immo-02074.jpg" },  // ← hangi gorsel oldugunu bilmiyorsun
  { name: "Bambous", img: "/images/003-1024x560.jpg" },  // ← yanlis olabilir
  ...
];

// DOGRU — binding map'ten birebir eslesir
// binding map goruntusu:
// { identifier: "AURAR", nearestTexts: ["AURAR", "Se soigner", "Architecte : Henry Techer"], src: "IPP-Immo-02074.jpg" }
// { identifier: "Bambous", nearestTexts: ["Bambous", "Se divertir", "Architecte : LAB REUNION"], src: "IPP-Immo-1-1-1024x683.jpg" }
const projects = [
  { name: "AURAR", img: "/images/IPP-Immo-02074.jpg" },          // ← binding[0].src
  { name: "Bambous", img: "/images/IPP-Immo-1-1-1024x683.jpg" }, // ← binding[1].src
  ...
];
```

**Kontrol kurali:** Bir component'te kullandigin her `/images/X.jpg` yolu, o elemanin
binding map kaydindaki `src` degeriyle AYNI olmali. Farkli ise YANLIS gorseli kullaniyorsun.

---

## PHASE 3: Section-by-Section Cloning

This is the core of the skill. For EACH section identified in Phase 1:

### Step 3.1 — Crop Section Screenshot

```javascript
// For the current section (e.g., the header):
const sectionEl = await page.$('header'); // or whatever selector
const box = await sectionEl.boundingBox();
await page.screenshot({
  path: `reference/section-header.png`,
  clip: { x: box.x, y: box.y, width: box.width, height: box.height }
});
```

### Step 3.2 — Deep Extract Section CSS

This is what makes 90%+ fidelity possible. Don't guess — READ the actual values:

```javascript
const sectionCSS = await page.evaluate((selector) => {
  const section = document.querySelector(selector);
  if (!section) return null;

  function extractStyles(el) {
    const s = getComputedStyle(el);
    return {
      tag: el.tagName.toLowerCase(),
      text: el.childNodes.length === 1 && el.childNodes[0].nodeType === 3
            ? el.textContent.trim() : null,
      href: el.href || null,
      src: el.src || null,
      styles: {
        display: s.display,
        position: s.position,
        width: s.width,
        height: s.height,
        padding: s.padding,
        margin: s.margin,
        backgroundColor: s.backgroundColor,
        color: s.color,
        fontSize: s.fontSize,
        fontWeight: s.fontWeight,
        fontFamily: s.fontFamily,
        lineHeight: s.lineHeight,
        letterSpacing: s.letterSpacing,
        textAlign: s.textAlign,
        textTransform: s.textTransform,
        textDecoration: s.textDecoration,
        borderRadius: s.borderRadius,
        border: s.border,
        boxShadow: s.boxShadow,
        gap: s.gap,
        flexDirection: s.flexDirection,
        justifyContent: s.justifyContent,
        alignItems: s.alignItems,
        gridTemplateColumns: s.gridTemplateColumns,
        backgroundImage: s.backgroundImage,
        opacity: s.opacity,
        transform: s.transform,
        transition: s.transition,
        overflow: s.overflow,
        maxWidth: s.maxWidth,
        // Icon/image positioning — CRITICAL for SVG and img elements
        top: s.top,
        right: s.right,
        bottom: s.bottom,
        left: s.left,
        zIndex: s.zIndex,
        objectFit: s.objectFit,
        objectPosition: s.objectPosition
      },
      // For img/svg elements, also capture natural dimensions
      naturalSize: (el.tagName === 'IMG') ? { w: el.naturalWidth, h: el.naturalHeight } : null,
      svgViewBox: (el.tagName === 'SVG') ? el.getAttribute('viewBox') : null,
      children: [...el.children].map(child => extractStyles(child))
    };
  }

  return extractStyles(section);
}, sectionSelector);
```

Save as `reference/section-header-css.json`.

### Step 3.2b — Component Tree Extraction (ZORUNLU)

Step 3.2'deki genel CSS extraction YETMEZ. Parcali component'lerde (kart gruplari,
ikon + metin kombinasyonlari, nested layout'lar) elemanlar arasi iliskiler kayboluyor.

Bu adimda section icindeki HER TEKRARLANAN ELEMAN GRUBUNU (kart, liste ogesi, nav item)
AYRI AYRI cikararak ic layout'u tam olarak belgeliyorsun.

**Neden gerekli:** Bir kart component'inde ikon sag ustte, baslik ortada, aciklama altta
olabilir. Step 3.2 bunu "flat liste" olarak cikarir — hangi elemanin hangi container'in
icinde oldugu, aralarindaki gap, padding, position iliskisi KAYBOLUR.

```javascript
// TEKRARLANAN ELEMAN GRUPLARI ICIN — ornegin kart listesi
// 1. Once section icindeki TUM tekrarlanan container'lari bul
// 2. ILKINI detayli cikar (diger kartlar ayni yapidadir)
// 3. Container'in IC YAPISINI agac olarak belgele

const componentTree = await page.evaluate((containerSelector) => {
  // Tek bir kart/container secici ver — ornegin ilk karti
  const container = document.querySelector(containerSelector);
  if (!container) return null;
  const cs = getComputedStyle(container);

  function extractNode(el, depth) {
    if (depth > 5) return null;
    const s = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    const parentRect = el.parentElement?.getBoundingClientRect();

    return {
      tag: el.tagName,
      // Icerik
      text: (el.childNodes.length === 1 && el.childNodes[0].nodeType === 3)
            ? el.textContent.trim().slice(0, 50) : null,
      src: el.src?.split('/').pop() || null,

      // BOYUT — px cinsinden gercek renderlanmis degerler
      w: Math.round(rect.width),
      h: Math.round(rect.height),

      // KONUM — parent'a gore offset
      offset: parentRect ? {
        t: Math.round(rect.top - parentRect.top),
        r: Math.round(parentRect.right - rect.right),
        b: Math.round(parentRect.bottom - rect.bottom),
        l: Math.round(rect.left - parentRect.left)
      } : null,

      // LAYOUT ozellikleri
      display: s.display,
      position: s.position,
      flexDir: s.flexDirection !== 'row' ? s.flexDirection : null,
      justifyContent: s.justifyContent !== 'normal' ? s.justifyContent : null,
      alignItems: s.alignItems !== 'normal' ? s.alignItems : null,
      gap: s.gap !== 'normal' ? s.gap : null,

      // GORUNUM
      padding: s.padding !== '0px' ? s.padding : null,
      margin: s.margin !== '0px' ? s.margin : null,
      bg: (s.backgroundColor !== 'rgba(0, 0, 0, 0)') ? s.backgroundColor : null,
      color: s.color,
      borderRadius: s.borderRadius !== '0px' ? s.borderRadius : null,

      // FONT — her metin elemani icin
      fontFamily: s.fontFamily.split(',')[0].replace(/"/g,'').trim(),
      fontSize: s.fontSize,
      fontWeight: s.fontWeight,
      lineHeight: s.lineHeight,

      // IKON/GORSEL — img ve svg icin
      filter: (s.filter !== 'none') ? s.filter : null,
      objectFit: (el.tagName === 'IMG') ? s.objectFit : null,

      // COCUKLAR — recursive
      children: [...el.children].map(c => extractNode(c, depth + 1)).filter(Boolean)
    };
  }

  return {
    // Container'in kendisi
    container: {
      w: Math.round(container.offsetWidth),
      h: Math.round(container.offsetHeight),
      padding: cs.padding,
      bg: cs.backgroundColor,
      borderRadius: cs.borderRadius,
      display: cs.display,
      flexDir: cs.flexDirection,
      gap: cs.gap,
      position: cs.position
    },
    // IC AGAC — her cocuk elemanin pozisyonu, boyutu, fontu, rengi
    tree: [...container.children].map(c => extractNode(c, 0))
  };
}, sectionSelector);
```

**Bu scripti HER FARKLI COMPONENT TIPI icin bir kez calistir:**
- Kart grubunda → ilk karti sec, agacini cikar
- Header'da → header container'i sec
- Footer'da → her sutunu sec
- Carousel'de → tek bir carousel item'i sec

**CIKARILAN AGACI COMPONENT'E NASIL CEVIRIRSIN:**

Agac ciktisi soyle gorunur:
```
container: { w:350, h:280, padding:"30px", bg:"#54626B", borderRadius:"12px", display:"flex", flexDir:"column", gap:"0px" }
  └─ div: { w:24, h:24, offset:{t:0, r:0}, position:"absolute" }  → ikon, sag ust
  └─ img: { w:50, h:50, src:"Frame-17.svg", filter:"invert(1)" }  → ikon, filtreli
  └─ h4:  { w:290, fontSize:"24px", fontWeight:"700", color:"white", fontFamily:"Avenir" }
  └─ p:   { w:290, fontSize:"15px", fontWeight:"400", color:"rgba(255,255,255,0.8)" }
  └─ span: { w:80, fontSize:"14px", color:"white", offset:{b:0} }  → "En savoir +"
```

Bunu BIREBIR Tailwind'e cevir:
```jsx
<div className="w-[350px] min-h-[280px] p-[30px] bg-[#54626B] rounded-[12px] flex flex-col relative">
  <div className="absolute top-0 right-0 w-[24px] h-[24px]">...</div>
  <img src="/images/Frame-17.svg" className="w-[50px] h-[50px] brightness-0 invert" />
  <h4 className="text-[24px] font-bold text-white">...</h4>
  <p className="text-[15px] font-normal text-white/80">...</p>
  <span className="text-[14px] text-white mt-auto">En savoir +</span>
</div>
```

**KURALLAR:**
- Agactaki `w`, `h` → `w-[Xpx]`, `h-[Xpx]` veya `min-h-[Xpx]` (esnek container'lar icin)
- `offset.t:0, offset.r:0` + `position:absolute` → `absolute top-0 right-0`
- `padding:"30px"` → `p-[30px]`
- `gap:"15px"` → `gap-[15px]`
- `fontSize:"24px"` → `text-[24px]`
- `fontWeight:"700"` → `font-bold`
- `fontFamily:"AvantGarde"` → `font-heading` (theme variable, ASLA `font-[AvantGarde]`)
- `fontFamily:"Avenir"` → yazma (body zaten Avenir, gereksiz)
- `filter:"invert(1)"` → `brightness-0 invert`
- `bg:"rgba(0,0,0,0)"` → yazma (transparan, gereksiz)
- `color` → rgb'den hex'e cevir: `rgb(114,101,102)` → `text-[#726566]`

### Step 3.3 — Extract Section HTML Structure

```javascript
const sectionHTML = await page.evaluate((selector) => {
  const el = document.querySelector(selector);
  return el ? el.outerHTML : null;
}, sectionSelector);
```

Save as `reference/section-header.html` for reference. Don't copy it verbatim —
use it to understand the structure, then write clean code.

### Step 3.3b — Hover State Extraction (HER INTERAKTIF ELEMAN ICIN)

Kartlar, butonlar, linkler icin hover durumunu AYRI cikar. Hover'da neyin
degistigini bilmeden component yazilamaz.

```javascript
// Hover state extraction — her interaktif eleman icin
// Tarayici MCP ile elemana hover et, SONRA ayni elemani tekrar extract et
// Ornek: kart hover
const hoverData = await page.evaluate((selector) => {
  const el = document.querySelector(selector);
  if (!el) return null;
  // Normal state zaten Step 3.2b'de cikarildi
  // Simdi :hover pseudo-class varsa onu da al
  // Not: getComputedStyle hover state'i dogrudan veremez,
  // tarayici MCP ile hover edip tekrar extractNode calistirmalisin
  const s = getComputedStyle(el);
  return {
    transition: s.transition,
    cursor: s.cursor,
    // Kart hover'da genelde degisen ozellikler:
    boxShadow: s.boxShadow,
    transform: s.transform,
    backgroundColor: s.backgroundColor,
    borderColor: s.borderColor,
    opacity: s.opacity
  };
}, cardSelector);
```

Tarayici MCP ile hover edip ONCE/SONRA state'lerini karsilastir.
Fark olan her ozelligi component'e transition + hover class olarak ekle.

### Step 3.4a — Write Spec File → `docs/research/components/<Name>.spec.md` (ZORUNLU)

ULTRATHINK protokolu, component dosyasi icinde yorum bloguna degil, AYRI bir spec
markdown dosyasina yazilir. Her section icin bir spec dosyasi, builder agent'a
inline prompt olarak verilecek auditable bir sozlesmedir.

**Dosya yolu:** `docs/research/components/<ComponentName>.spec.md`

**Neden ayri dosya?** 
- Component dosyasi temiz kalir (sadece kod, yorum bloglari yok)
- Spec dosyasi denetlenebilir — kullanici gozden gecirebilir, duzeltme yapabilir
- Paralel builder agent'larina inline prompt olarak verilebilir
- Orchestrator agent duzeltme istediginde spec'i referans alir

**Spec dosyasi sablonu:**

```markdown
# <ComponentName> Specification

## Target
- **File:** `src/components/<ComponentName>.tsx`
- **Screenshot (desktop):** `docs/design-references/<name>-desktop.png`
- **Screenshot (tablet):** `docs/design-references/<name>-tablet.png`
- **Screenshot (mobile):** `docs/design-references/<name>-mobile.png`

## Interaction Model
- **Type:** <static | click-driven | scroll-driven | time-driven>
- **Details:** <ornegin: card hover → shadow + translate-y>
- **Source:** `reference/BEHAVIORS.md` (ilgili bolum)

## Container Layout
- Section: <py:60px, bg:white>
- Inner: <max-w:1200px, flex flex-row, gap:15px>

## Elements (EXTRACTION OZETI)

### <Element adi / label>
- tag: <H2 | DIV | A>
- text: "<gercek metin>"
- ff: <heading | sans | script> (Tailwind class'i: font-heading)
- fs: <Xpx>  → text-[Xpx]
- fw: <400|600|700>  → font-normal|semibold|bold
- c: <#xxxxxx>  → text-[#xxxxxx]
- bg: <#xxxxxx veya transparent>
- w/h: <px>
- pos: <static|absolute|relative>
- offset: <top:X, right:Y, bottom:Z, left:W>
- padding: <full value>
- margin: <full value>
- borderRadius: <Xpx>
- (HER eleman icin her satir dolu olacak — bosluk yok)

### Hover States (varsa)
- <eleman>: before→<shadow:none>, after→<shadow:0 10px 30px ...>
- transition: <all 0.3s ease>

## Per-Element Assets (binding map'ten)
- <eleman/kart>: <file.svg/jpg>  (source: reference/image-binding-map.json)

## Text Content (verbatim)
<Butun metinler, siteden birebir kopyalama>

## Responsive Notes
- **1440px:** <layout>
- **768px:** <ne degisir>
- **390px:** <ne degisir>
- **Breakpoint:** <~XXXpx'de sutun degisir>

## Verification Checklist
- [ ] Tum elemanlar listelendi (eksik buton, link, ikon yok)
- [ ] Tum kart/tekrarlanan elemanlarin bg rengi AYRI belirlendi
- [ ] Icon+text layout yonu belirlendi (flex-row/flex-col)
- [ ] Hover state'leri cikarildi
- [ ] Responsive davranis kaydedildi
- [ ] Asset binding'leri dogrulandi
```

**Ornek — MetiersSection.spec.md:**

```markdown
# MetiersSection Specification

## Target
- **File:** `src/components/MetiersSection.tsx`
- **Screenshot (desktop):** `docs/design-references/metiers-desktop.png`

## Interaction Model
- **Type:** static + hover on cards

## Container Layout
- Section: py:60px, bg:white
- Inner: max-w:1200px, flex flex-row, gap:15px

## Elements

### Heading Column (w:328)
- H3 "Métiers & Expertises": ff→heading, fs→40px, fw→400, c→#726566, lh→44px
- P "complémentaires": ff→sans, fs→17px, fw→400, c→#726566, italic
- Button "Nos métiers →":
  - ff→sans, fs→18px, fw→700, c→white
  - bg→#004C93, br→10px
  - w→188, h→56
  - padding: 14px 24px
  - display: inline-flex, items:center, gap:8px
  - Icon (arrow-right inline SVG): w→18, h→18, stroke:white

### Card-1 (Aménagement) — bg:#726566, w:325, h:320, br:10px
- Arrow SVG (top-right):
  - pos:absolute, top:20, right:20
  - w:36, h:36
  - c:white/50
  - hover: rotate(15deg), transition:0.3s
- H4 "Aménagement":
  - ff→heading, fs→30px, fw→400, c:white, lh:33px
  - offset from card top: 135px
- Icon+Desc ROW (flex-row, gap:12px, items:center):
  - IMG icon: src→Frame-13.svg, w:31, h:31, filter→brightness(0)invert(1)
  - P desc: "De programmes sur mesure", fs:17px, fw:400, c:white
- Link "En savoir +":
  - fs:15px, fw:700, c:white
  - border-bottom: 1px solid white/50
  - offset from card bottom: 40px
- Card hover:
  - box-shadow: 0 10px 30px rgba(0,0,0,0.15)
  - transform: translateY(-2px)
  - transition: all 0.3s ease

### Card-2 (Promotion immobilière) — bg:#F2EFF0 (AÇIK!), w:325, h:320, br:10px
- SAME structure as Card-1, FARKLAR:
  - Card bg: #F2EFF0
  - Arrow SVG c: #726566 (not white)
  - H4 c: #726566
  - Icon: src→Frame-17.svg, filter:YOK (koyu ikon acik bg'de)
  - P desc c: #726566
  - Link c: #726566
  - border-bottom c: #726566/50

### Card-3 (Foncière) — bg:#004C93, w:325, h:320, br:10px
- SAME structure as Card-1 (beyaz text)
- Icon: src→esper-titre.svg, filter→brightness(0)invert(1)

## Assets (binding map'ten)
- Card-1 icon: `/images/Frame-13.svg`
- Card-2 icon: `/images/Frame-17.svg`
- Card-3 icon: `/images/esper-titre.svg`

## Text Content (verbatim)
- Heading: "Métiers & Expertises"
- Subtitle: "complémentaires"
- Button: "Nos métiers"
- Card 1 title: "Aménagement"
- Card 1 desc: "De programmes sur mesure"
- Card 2 title: "Promotion immobilière"
- Card 2 desc: "En propre ou pour le compte de tiers"
- Card 3 title: "Foncière"
- Card 3 desc: "Gestion de patrimoine immobilier"
- Link (all cards): "En savoir +"

## Responsive Notes
- **1440px:** Heading left (22%) + 3 cards row (78%)
- **768px:** Heading top full-width + cards 2-column grid
- **390px:** Everything stacks 1-column
- **Breakpoint:** heading/cards → stack at ~1024px, cards 3→2 col at ~900px, 2→1 col at ~640px

## Verification Checklist
- [x] Tum elemanlar listelendi
- [x] 3 kartin bg rengi AYRI (#726566, #F2EFF0, #004C93)
- [x] Icon+desc flex-row (stacked degil)
- [x] Hover state'leri yazildi
- [x] Responsive davranis kaydedildi
- [x] Assets binding dogrulandi
```

**Bu spec dosyasi tamamlanmadan builder dispatch EDILMEZ.**

### Step 3.4b — Component-by-Component Build & Verify (YENI — VARSAYILAN)

**Yeni kural:** Builder'lari TOPLU paralel dispatch ETME. Yerine **component
component** (bolum bolum) ilerle. Her component:
1. Tek basina build edilir (tek Agent cagrisi)
2. Hemen ardindan dev server'da RENDERLANIR ve screenshot alinir
3. Screenshot orijinal section-XX.png ile yan yana karsilastirilir
4. Farklar yakalanir → ayni builder'a spesifik duzeltme gonderilir
5. Ikinci karsilastirma → olur ya da 3. iterasyon
6. YESIL olunca SIRADAKI component'e gecilir

**Neden toplu paralel dispatch DEGIL:**
- Paralel builder'lar ayni ulu hatalari tekrar tekrar yapiyor (ornegin tum
  pill button'larda text rengini yanlis okumak, hero gibi video olan yerleri
  static image yapmak). Tum agent'lar ayni anda calistigi icin ilk hatayi
  yakalayip diger builder'lari duzeltme sansi olmuyor.
- Tek component bir kez renderlandiginda orijinalle karsilastirma YAPIN, buldugun
  sistematik sorunu (ornegin "pseudo element renkleri span ile wrap'lenmis")
  sonraki component'lere ders olarak aktarabilirsin.
- Token kullanimi dagilmiyor — bir hatayi 8 kez tekrarlamak yerine 1 kez
  yapiyorsun.

**Dispatch akisi (sirasiyla — asla paralel degil):**
1. `docs/research/components/` altindaki spec dosyalarini ONEM SIRASINA koy:
   Header → Hero → icerik bolumleri → Footer. (Header ve Hero en kritik cunku
   diger component'ler bunlarin vertical alignment'ina oturur.)
2. Her spec icin:
   - **Build:** `Agent` tool (genel-purpose, `run_in_background: false` — ONAY
     bekle), spec icerigi inline prompt.
   - **Render:** Dev server zaten calisiyorsa hot reload, degilse baslat.
   - **Screenshot:** Playwright ile `viewport: {1440, 900}`, `clip` ile
     component'in olduğu Y araligi → `qa/clone-sec-XX.png`.
   - **Karsilastir:** `reference/section-XX-*.png` ile YAN YANA bak. Farklari
     listele (renk, font, boyut, konum, eksik eleman).
   - **Iterate:** Varsa duzeltme icin ayni spec + "SU FARKLILIKLARI DUZELT"
     listesi ile YENI Agent cagrisi.
   - **Max 3 iterasyon.** 3 sonra hala farkliysa TODO olarak not et ve siradaki
     component'e gec.
3. Tum component'ler yesil olduktan sonra Phase 4 final QA.

**Cross-component learning:**
Her component'ta bulundugun `GENEL` dersi (ornegin "salient tema nav link'leri
A > SPAN ile yapiliyor, renk asil SPAN'da" ya da "hero'da `<video class=nectar-video-bg>`
var, static image DEGIL") bir sonraki component'in spec'inde notlara ekle. Bu
dersi SKILL.md'nin "Common Pitfalls" bolumune de yaz (skill evolve etsin).

**Paralel dispatch sadece su durumda izinli:** Cok basit, tamamen bagimsiz ve
diger component'lerle hizalamasi olmayan "yaprak" component'ler varsa (ornegin
SocialIcons, LoaderSpinner gibi). Onlar bile tercihen seri yapilmali.

**Builder Agent prompt sablonu:**

```
Sen bir component builder'sin. Asagidaki spec dosyasini BIREBIR takip ederek
React component dosyasini yaz.

## SPEC DOSYASI ICERIGI
<SPEC_FILE_CONTENTS_HERE — docs/research/components/<Name>.spec.md'nin tam metni>

## GOREVIN
1. `src/components/<ComponentName>.tsx` dosyasini olustur
2. Spec'teki HER DEGERI mekanik olarak Tailwind'e cevir (tahmin yok)
3. Image binding'leri spec'ten al, listeden RASTGELE secme
4. Bitirmeden once `npx tsc --noEmit` calistir, hata varsa duzelt
5. Bitince raporla: dosya yolu, eksikler varsa

## MEKANIK CEVIRI TABLOSU

| Spec satiri | Tailwind |
|------------|----------|
| `fs: Xpx` | `text-[Xpx]` |
| `fw: 400` | `font-normal` |
| `fw: 600` | `font-semibold` |
| `fw: 700` | `font-bold` |
| `ff: heading` | `font-heading` |
| `ff: sans` | (yazma, body zaten Avenir) |
| `c: #XXX` | `text-[#XXX]` |
| `c: white` | `text-white` |
| `c: white/50` | `text-white/50` |
| `bg: #XXX` | `bg-[#XXX]` |
| `br: Xpx` | `rounded-[Xpx]` |
| `w: X` | `w-[Xpx]` |
| `h: X` | `min-h-[Xpx]` (esnek) veya `h-[Xpx]` (sabit) |
| `gap: X` | `gap-[Xpx]` |
| `padding: X` | `p-[Xpx]` (veya px-/py-/pt-) |
| `pos: absolute, top:X, right:Y` | `absolute top-[Xpx] right-[Ypx]` |
| `display: flex, dir: ROW` | `flex flex-row` |
| `display: flex, dir: column` | `flex flex-col` |
| `filter: brightness(0) invert(1)` | `brightness-0 invert` |
| `HOVER: shadow: X` | `hover:shadow-xl` veya `hover:shadow-[Xpx]` |
| `HOVER: transition: all 0.3s` | `transition-all duration-300` |
| `HOVER: translateY(-2px)` | `hover:-translate-y-[2px]` |
| `HOVER: bg: #darker` | `hover:bg-[#darker]` |

## KURALLAR
- `font-[AvantGarde]` YAZMA — Tailwind v4'te font-WEIGHT olarak yorumlanir
- Spec'te olmayan bir deger TAHMIN ETME — spec'teki degeri kullan
- Placeholder ikon veya "sonradan eklenecek" koyma — spec'teki gercek asset'i kullan
- Spec'te `Text Content` bolumundeki metinleri birebir kullan (cevirme)
- Responsive: spec'teki breakpoint davranislarini md:/sm:/lg: ile uygula
- Component dosyasi icinde YORUM BLOGU YAZMA — spec dosyasi zaten ayri

## DOGRULAMA
- Bitirmeden once her spec satirini JSX karsiligiyla karsilastir
- fontSize, fontWeight, color, ikon boyutu eslesiyor mu?
- Tum interaktif elemanlar var mi (buton, link, ikon)?
- Hover efektleri eklendi mi?
- `npx tsc --noEmit` temiz mi?
```

**Orchestrator (ana konusma) akisi:**

```javascript
// Tum section'lar icin paralel dispatch
const sections = ['Header', 'HeroSection', 'IntroSection', 'MetiersSection',
                  'ActivitesSection', 'RealisationsSection', 'CTASection', 'Footer'];

for (const name of sections) {
  const spec = readFile(`docs/research/components/${name}.spec.md`);
  // Agent tool call — paralel
  Agent({
    description: `Build ${name}`,
    subagent_type: 'general-purpose',
    run_in_background: true,
    prompt: buildBuilderPrompt(name, spec)  // Yukaridaki sablon
  });
}
// Sonra hepsini bekle (notification sistemi ile)
```

**TAILWIND V4 FONT-FAMILY UYARISI:**
- `font-[AvantGarde]` YAZMA — Tailwind v4'te font-WEIGHT olarak yorumlanir!
- globals.css'te `@theme inline { --font-heading: "AvantGarde"... }` tanimla
- Component'te `font-heading` kullan

### Step 3.4c — Post-Build Verification

Her builder agent bittikten sonra (notification geldiginde):

**3c-1. Stil dogrulama:**
Spec dosyasindaki her satiri component'teki JSX karsiligi ile karsilastir:
- `fs: 30px` → JSX'te `text-[30px]`? ✅
- `fw: 700` → JSX'te `font-bold`? ✅
- `c: white` → JSX'te `text-white`? ✅

Eslesmiyorsa builder agent'i yeniden dispatch et, spesifik talimat ver.

**3c-2. Image binding dogrulama (ZORUNLU — sayfa sonu yanlis eslesmelerini onler):**

Component'te kullandigin HER `/images/X` yolunu `image-binding-map.json` ile karsilastir:

```
JSX: <Image src="/images/IPP-Immo-02074.jpg" alt="AURAR" />
Binding: { identifier: "AURAR", src: "IPP-Immo-02074.jpg" }
ESLESME? ✅

JSX: <Image src="/images/003-1024x560.jpg" alt="CTA bina" />
Binding: { identifier: "CTA-section", src: "building-photo.jpg" }
ESLESME? ❌ — YANLIS gorsel, duzelt
```

**EKSTRA KONTROL — CTA ve single-image section'lar:**
Footer, CTA, hero gibi bolgelerde GENELDE sayfa listesinden rastgele bir gorsel
KULLANMA. Binding map'te o specific section icin kayitli olan gorseli kullan.
Kayitli yoksa placeholder GOSTERME — extraction'a don.

**Output format — ALWAYS component-based:**

Her section ayrı bir component dosyası olarak üretilir. Dil/framework fark etmez:
- **React/Next.js:** `Header.tsx`, `Hero.tsx`, `Features.tsx`, `Footer.tsx`
- **Vue:** `Header.vue`, `Hero.vue`, `Features.vue`, `Footer.vue`
- **Svelte:** `Header.svelte`, `Hero.svelte`, `Features.svelte`, `Footer.svelte`
- **Plain HTML:** `components/header.html`, `components/hero.html` + ana `index.html` include eder
- **Astro:** `Header.astro`, `Hero.astro`, `Features.astro`, `Footer.astro`

Ana sayfa dosyası (index/page) tüm component'leri import ederek birleştirir.
Kullanıcı framework belirtmemişse, projedeki mevcut stack'e bakarak karar ver.
Proje yoksa **React + Tailwind** varsayılan olarak kullanılır.

### Step 3.5 — Visual Comparison (QA Loop)

After writing the section code:

1. Start a local dev server (or open the HTML file)
2. Use Playwright to screenshot the cloned section at the same viewport width
3. Compare with the original section screenshot

```javascript
// Take screenshot of cloned section
const clonePage = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await clonePage.goto('http://localhost:3000'); // or file:// URL
const clonedSection = await clonePage.$('header'); // same selector
const cloneBox = await clonedSection.boundingBox();
await clonePage.screenshot({
  path: `qa/clone-header.png`,
  clip: { x: cloneBox.x, y: cloneBox.y, width: cloneBox.width, height: cloneBox.height }
});
```

Now visually compare `reference/section-header.png` with `qa/clone-header.png`.

**Check for these common issues:**
- Color mismatches (especially subtle grays, semi-transparent backgrounds)
- Font rendering differences (wrong font-family, weight, or size)
- Spacing drift (padding/margin off by a few pixels)
- Missing background gradients or overlays
- Wrong flex/grid alignment
- Missing or misplaced icons
- Incorrect border-radius or box-shadow

If differences found → fix the code → re-screenshot → compare again.
Repeat this loop up to 3 times per section. If still not matching after 3 attempts,
note the remaining differences and move on.

### Step 3.6 — Orkestra Sefi (Orchestrator) Review Loop (YENI — ZORUNLU)

Tum builder agent'lar bittikten sonra bir ORCHESTRATOR rolu devreye girer.
Orchestrator = sen. Klonu orijinalle yan yana karsilastirir, farklari bulur,
ilgili builder agent'i yeniden dispatch ederek spesifik duzeltme talimati verir.

**Neden gerekli:** Paralel builder'lar bazen spec'i yanlis yorumlar ya da ufak
detaylari atlar. Orchestrator loop'u bunu otomatik yakalayip duzeltir.

**Orchestrator akisi:**

1. **Dev server baslat:**
   ```bash
   npm run dev   # veya ilgili komut
   # server baslamazsa port kontrol et, hatalari gider
   ```

2. **Tarayici MCP ile klonu ac:**
   ```
   Chrome MCP: navigate → http://localhost:3000
   ```

3. **Section section karsilastir:**
   Her section icin:
   - Klonun screenshot'ini al (Chrome MCP veya computer-use)
   - `docs/design-references/<name>-desktop.png` ile karsilastir
   - Farklari listele:
     - Renk farki (ornegin: "Card 2 bg beyaz, orijinal #F2EFF0")
     - Font farki ("H4 fs:24px, orijinal 30px")
     - Boyut farki ("Ikon w:24px, orijinal 36px")
     - Konum farki ("Arrow top:8px, orijinal 20px")
     - Eksik eleman ("'Nos métiers' butonu yok")
     - Hover yok ("kart hover'da shadow yok")

4. **Her farklilik icin ilgili builder'i YENIDEN DISPATCH ET:**
   ```
   Agent({
     description: "Fix MetiersSection card 2 bg",
     subagent_type: "general-purpose",
     run_in_background: true,
     prompt: `
     src/components/MetiersSection.tsx dosyasinda sorun var.
     
     Spec: docs/research/components/MetiersSection.spec.md
     Screenshot (orijinal): docs/design-references/metiers-desktop.png
     
     TESPIT EDILEN FARKLILIKLAR:
     1. Card 2 (Promotion immobilière) bg rengi beyaz, orijinalde #F2EFF0 olmali.
        Line 42'yi guncelle: bg: "#F2EFF0"
     2. H4 icin fs:24px kullanilmis, orijinalde 30px olmali (text-[30px])
     3. "En savoir +" linkinde border-bottom yok, eklenmeli
     
     Bu 3 duzeltmeyi yap, npx tsc --noEmit ile dogrula, bitince raporla.
     `
   })
   ```

5. **Builder bitince tekrar verify:**
   - Screenshot al
   - Orijinal ile tekrar karsilastir
   - Hala fark varsa tekrar dispatch (max 3 iterasyon)
   - 3 denemeden sonra da duzelmezse raporla ve kullaniciya sor

6. **Responsive review:**
   - Viewport'i 768px'e ayarla → screenshot → tablet ile karsilastir
   - Viewport'i 390px'e ayarla → screenshot → mobile ile karsilastir
   - Farklari aynen yukaridaki gibi builder'a gonder

7. **Son rapor:**
   Her section icin durum tablosu:
   | Section | Desktop | Tablet | Mobile | Kalan issue |
   |---------|---------|--------|--------|-------------|
   | Header | ✅ | ✅ | ✅ | - |
   | MetiersSection | ✅ | ✅ | ⚠ | Card stack order wrong |
   | ... | ... | ... | ... | ... |

**ORCHESTRATOR ROLU ILE BUILDER ROLU AYRI TUTULMALI:**

- Builder agent: sadece kendi component'ini yazar/duzeltir, orijinali gormez
- Orchestrator (sen): her zaman orijinal referansiyla karsilastirir, builder'a spesifik talimat verir
- Builder'a "guzellestir" deme — "line 42'yi su sekilde degistir" de

Bu sekilde orchestrator butun sayfayi pixel-perfect hale getirme sorumlulugunu tasir,
builder'lar ise kucuk, odakli duzeltmeler yapar.

---

## PHASE 4: Assembly & Final QA

### Step 4.1 — Combine All Sections

Assemble all sections into the final page. Ensure:
- Correct vertical ordering
- No gaps or overlaps between sections
- Global styles (body background, font) are applied
- External fonts are loaded
- Favicon is set

### Step 4.2 — Full Page Comparison

Take a full-page screenshot of the clone and compare with the original:
```javascript
await clonePage.screenshot({ path: 'qa/full-page-clone.png', fullPage: true });
```

Look at both images. Check:
- Overall visual rhythm and spacing
- Section transitions (no unintended gaps or borders)
- Scroll behavior
- Any elements that shifted during assembly

### Step 4.3 — Responsive Check (if requested)

If the user wants responsive fidelity:
1. Resize viewport to 375px → screenshot → compare with mobile reference
2. Resize viewport to 768px → screenshot → compare with tablet reference
3. Fix any breakpoint issues

---

## Output Structure

```
project/
├── index.html          # Main page (or src/ for React/Next.js)
├── styles.css          # Custom CSS (if not using Tailwind)
├── public/
│   ├── images/         # Downloaded images
│   ├── fonts/          # Downloaded fonts (if self-hosted)
│   └── icons/          # Favicons and icon files
├── reference/          # Original site data (for developer reference)
│   ├── full-page.png
│   ├── mobile.png
│   ├── section-map.json
│   ├── design-tokens.json
│   └── section-*.png
└── qa/                 # QA comparison screenshots
    ├── full-page-clone.png
    └── section-*.png
```

---

## Common Pitfalls and Solutions

**"Fontlar yanlis gorunuyor — kalinlik, boyut veya aile farkli"**
→ Bu EN SIK yapilan hata. Sebepleri:
  1. `font-family` cikarilmamis — her baslik ve body icin AYRI font ailesi olabilir
  2. `font-weight: 400` ile `700` karistirilmis — extracted degeri BIREBIR kullan
  3. Tailwind utility class'i yanlis — `text-lg` 18px verir ama gercek deger 17px olabilir
  4. @font-face tanimlanmamis — ozel fontlar (woff2) indirilip globals.css'e eklenmeli
  **Cozum:** Step 3.2b'deki font extraction'i MUTLAKA calistir, sonuclari dosyaya kaydet,
  component yazarken BIREBIR kopyala. Asla tahmin etme.

**"Ikonlar yanlis yerde veya yanlis boyutta"**
→ Sebepleri:
  1. Ikon boyutu cikarilmamis — `w-6` yazilmis ama gercek boyut 50x50px
  2. `position: absolute` + `top/right` degerleri eksik — ikon parent'in icinde suzuyor
  3. SVG'nin `filter: invert` veya `brightness` degeri eksik — ikon gorunmuyor
  **Cozum:** Step 3.2b'deki icon extraction'i calistir, `renderedW/H` ve 
  `offsetFromParent` degerlerini BIREBIR kullan. Tailwind size class'lari KULLANMA.

**"Renkler biraz farkli"**
→ Always use getComputedStyle values, never eyeball from screenshots.
   Watch for rgba() vs hex differences and color profiles.

**"Spacing tutarsiz"**
→ Don't round CSS values. If the original uses 17px padding, use 17px,
   not "1rem" or "p-4". Precision matters for pixel fidelity.

**"Hover/active states missing"**
→ Before building each section, trigger hover on interactive elements
   and capture those states too:
   ```javascript
   await page.hover('nav a:first-child');
   await page.screenshot({ path: 'reference/nav-hover.png', clip: {...} });
   ```

**"Animations don't match"**
→ This is the hardest part. Extract transition/animation CSS properties but
   know that complex JS-driven animations may need manual recreation.
   Focus on CSS transitions first — they cover 80% of common animations.

**"The page uses a framework (React/Vue/Angular)"**
→ You're cloning the visual output, not the framework. Extract the rendered
   HTML and CSS, not the source components. The clone doesn't need to use
   the same framework as the original.

---

## Lessons Learned (real-world clones)

Bu bolum, gerçek klonlama oturumlarindan cikarilan spesifik derslerdir. HER
klonlamada bunlari kontrol et — birer birer kacirilmasi cok kolay.

### Lesson 1 — Nav link text rengi A tag'inde degil IC SPAN'da
WordPress/Salient/Elementor gibi temalarda nav linkleri genelde
`<a><span class="menu-title-text">Contact</span></a>` yapisindadir. Anchor
element computed color cream olabilir, ama icteki span ayri bir color'a
sahiptir ve gorunen renk odur. Sadece A tag'inden color alma — her nav
link ve buton icin icteki span'i da ayri ekstract et:

```javascript
const a = document.querySelector('header a.contact');
const innerSpan = a?.querySelector('span');
console.log('Anchor color:', getComputedStyle(a).color);
console.log('Inner span color:', innerSpan && getComputedStyle(innerSpan).color);
// → Anchor: cream, Span: OLIVE (gorunen renk bu)
```

**Kural:** Builder'a buton/link spec'i yazarken MUTLAKA icteki span'in rengini
ver, yoksa klon ters renk ile cikar.

### Lesson 2 — `<header>` tag asil olive bar DEGIL
WordPress temalarinda `<header>` tag'i genelde transparent ve asil renkli
padded bar `<div id="header-outer">` veya benzer bir wrapper'dadir. Eger
`<header>` rect'ini alirsan (ornegin `x:45, y:25, w:1350`) wrapper'in 
`x:25, w:1390, borderRadius:20px, padding:"0 20px"` degerlerini kacirirsin.

**Kural:** Header extraction'da visual-wrappers.json'a bak ve sayfa ust 200px
icinde en buyuk renkli div'i bul. Onun `borderRadius`, `padding`, `margin-top`,
`width` degerlerini kullan. (Step 1.2b'deki Visual Wrapper Scan bunu yapar.)

### Lesson 3 — Hero'da `<video>` tag'ini ara
Pek cok modern landing sayfasinin hero'su static image DEGIL, autoplay loop
muted `<video>`'dur. Salient theme'de class `.nectar-video-bg`, Divi'de
`.et_pb_section_video_bg`, Elementor'da `.elementor-background-video-container`.
Static image olarak klonlarsan kullanici hemen fark eder.

**Extraction:**
```javascript
const videos = [...document.querySelectorAll('video')].map((v) => ({
  src: v.querySelector('source')?.src || v.src,
  poster: v.poster,
  autoplay: v.autoplay,
  loop: v.loop,
  muted: v.muted,
  class: v.className,
  rect: v.getBoundingClientRect(),
  objectFit: getComputedStyle(v).objectFit
}));
```

Video indir:
```bash
curl -fsSL -o public/videos/hero.mp4 "https://site.com/path/video.mp4"
```

Component'te:
```jsx
<video autoPlay loop muted playsInline preload="auto" poster="/images/hero-poster.webp"
       className="absolute inset-0 h-full w-full object-cover">
  <source src="/videos/hero.mp4" type="video/mp4" />
</video>
```

**Kural:** Her klonlamada asset extraction asamasinda `<video>` ve `<audio>`
elemanlarini da ayri bir sorgu ile yakala ve `assets-raw.json`'a ekle. Sadece
`<img>` ile sinirli kalma.

### Lesson 4 — Hero horizontal alignment header ile AYNI
Eger header'in rect'i `x:25, w:1390` ise, hero'nun da rect'i muhtemelen ayni.
Bu demek ki hero da header gibi 25px sol-sag padding icinde 1440px viewport'a
gore konumlandirilmistir. Hero'yu `max-w-[1300px]` gibi keyfi bir degerle
sarmala — HEADER ile ayni horizontal hizaya otur.

**Kural:** Hero wrapper = `w-full px-[25px]`, icerde `max-w-[1440px] mx-auto`.
Header ile ayni horizontal yapi. Ayni kural tum sayfa genisligi section'lar
icin gecerli (services, footer CTA, newsletter).

### Lesson 5 — `min(78vh, 760px)` gibi hibrit yukseklikler
Hero yuksekligi sabit `h-[551px]` verirsen farkli viewport'larda garip durur.
Kullanici "biraz daha buyut", "biraz daha kis", "ilk girdiğimizde altini
gormek istemiyorum" gibi iteratif ayarlar isteyecek. Tek degerle yonet:

```jsx
style={{ height: "min(80vh, 740px)", minHeight: "620px" }}
```

Bu 3 parametreyi ayri ayri ayarlayabilirsin: vh orani (viewport'a gore), max
(cok buyuk ekranlarda cap), min (kucuk ekranlarda cap). Kullanici "82vh yap"
dediginde kolayca degistirirsin.

### Lesson 6 — Heading wrap zorla `<br/>` ile
H1 gibi display heading'lerde max-width ile wrap tahmin etmeye calisma. Eger
orijinal site'de "Conseil en tourisme & hospitalité à La / Réunion" tarzi
kesin bir line break varsa, manuel `<br/>` kullan. Font kerning farkindan
dolayi ayni max-width'te klon farkli yerde wrap olabilir ve kullanici gorsel
farki fark eder.

```jsx
<h1>
  Conseil en tourisme &amp; hospitalité à La
  <br />
  Réunion
</h1>
```

**Kural:** Orijinal screenshot'ta cok satirli display heading varsa, satir
kirilmalarini gozle tespit et ve spec'e `<br/>` olarak yaz.

### Lesson 7 — Orijinal screenshot'ta visible gorunen icon boyutu rendered boyuttur
LinkedIn icon'unu `<img width="683" height="683">` olarak `naturalSize` alirsan
yanlis olur. `getBoundingClientRect()` ile RENDERED boyutu al (orn `50x50`).
Ayni bigi `section-XX-header.json` tree extraction'da `rect.width/height`
alanindadir.

### Lesson 8 — Border ister-istemez yorumlama
Kullanici "in logosu etrafinda border olmasin" dediginde, aslinda
orijinalde border YOK demek. Sen varsayim olarak bir circle border eklediysen
(ornegin footer social icon'larda da yaptin), bunu gozden gecir. Her zaman
orijinal site'de bir `border` kontrolu yap:

```javascript
const s = getComputedStyle(el);
if (s.borderWidth !== '0px') console.log('HAS BORDER:', s.border);
```

### Lesson 9 — Hero overlay opacity gercek degerini olc
Hero uzerindeki dark overlay cogu zaman `rgba(0,0,0,X)` veya `rgba(r,g,b,X)`
ile tanimlanir. `0.5` varsay etme — gercek degeri extract et. Salient'de
genellikle `.row-bg-overlay` diye ayri bir div vardir, onun computed
`background-color`'u al:

```javascript
const overlay = document.querySelector('.row-bg-overlay, .nectar-parallax-overlay');
const s = getComputedStyle(overlay);
console.log(s.backgroundColor, s.opacity);
```

### Lesson 10 — Text size olcusu aldatici olabilir
Responsive sites'de h1 font-size `64px` olarak computed gozukebilir ama VIZUAL
olarak hero heading daha buyuk durur cunku inline heading fontFamily ve
line-height farkli. Extracted `fontSize: 64px` degerini kullan, ama `clamp()`
formulu ile responsive yap:

```css
font-size: clamp(44px, 5.6vw, 80px);
```

Burada desktop cap'i 80px — extracted 64'ten buyuk olabilir cunku kullanici
genelde "biraz daha buyult" der. Kullanicinin iteratif isteklerine gore
clamp max'ini ayarla.

### Lesson 11 — Component by component, asla toplu paralel dispatch DEGIL
Paralel builder dispatch ayni hatayi 8 kez tekrarlatir. Cunku bir builder'da
olusan bir yanlis okuma (ornegin nav link renginin icteki span yerine anchor'dan
alinmasi), ayni anda calisan diger builder'larin spec'ine de yansimamis olur.

Sirali gitmek:
1. Header build → render → karsilastir → dustur
2. Header'da aldigin dersi Hero spec'ine ekle
3. Hero build → render → karsilastir → dustur
4. Hero'da aldigin dersi sonraki spec'e ekle
5. ...

Bu sekilde her section onceki hatalardan ders alir.

### Lesson 12 — Kullanici iteratif ayar isteyecek, iceri hazirla
Klonlama tamamen pixel-perfect olmaz. Kullanici screenshot'i acip soyle
diyecektir:
- "biraz daha buyut"
- "ekranda ilk girdiğimizde alt section gorunmesin"
- "82vh yap"
- "renk daha koyu olsun"
- "boslugu azalt"

Bu iteratif istekleri hizli karsilamak icin:
- Component'leri tek tek spesifik Edit'lerle hazir tut (Write degil)
- Hot reload calisan bir dev server kullan — her degisim saniyeler icinde
  yansisin
- vh/px hibrit olculer kullan, tek degeri oynatarak gorsel tune et

---

## Quick Reference: Full Workflow Checklist

### PHASE 1: Reconnaissance
- [ ] Step 1.1: 3 viewport screenshot (desktop/tablet/mobile)
- [ ] Step 1.2: Section map → `reference/section-map.json`
- [ ] Step 1.3: Design tokens + @font-face RESOLVED URLs → `reference/design-tokens.json`
- [ ] Step 1.4: Smooth scroll library detection (Lenis/Locomotive)
- [ ] Step 1.5: Mandatory Interaction Sweep → `reference/BEHAVIORS.md` (scroll/click/hover sweeps)
- [ ] Step 1.6: Responsive sweep comparison notes in BEHAVIORS.md

### PHASE 2: Asset Collection
- [ ] Step 2.1-2.3: Images, SVGs, bg-images downloaded
- [ ] Step 2.4: **Image Binding Map** → `reference/image-binding-map.json`
- [ ] Font dosyalari indirildi ve `file` komutuyla dogrulandi (woff2, HTML degil)

### PHASE 3: Section-by-Section (her section icin)

**Per-section extraction:**
- [ ] Step 3.1: 3 viewport section screenshot
- [ ] Step 3.2: Deep CSS extract
- [ ] Step 3.2b: Component tree extraction (her eleman icin w/h/offset/fontSize/fontWeight/ff/color/bg)
- [ ] Step 3.3b: Hover state extraction (Chrome MCP hover + re-extract + diff)

**Spec file:**
- [ ] Step 3.4a: `docs/research/components/<Name>.spec.md` yazildi
- [ ] Spec'te TUM elemanlar listelendi (buton, link, ikon dahil — eksik yok)
- [ ] Spec'te her tekrarlanan eleman (kart) icin bg rengi AYRI belirtildi
- [ ] Spec'te icon+text layout yonu belirtildi (flex-row/flex-col)
- [ ] Spec'te hover state'leri yazildi
- [ ] Spec'te responsive davranis 3 viewport icin belgelendi
- [ ] Spec'te asset binding'leri (image-binding-map'ten) yazildi

**Parallel builder dispatch:**
- [ ] Step 3.4b: Her section icin Agent dispatch (`run_in_background: true`)
- [ ] Her builder prompt'una spec dosyasi icerigi INLINE olarak konuldu
- [ ] Tum builder'larin bitmesi beklendi (notification)

**Post-build verification:**
- [ ] Step 3.4c-1: Stil satirlari spec ile eslesti mi (fs, fw, ff, c, w, h, offset)
- [ ] Step 3.4c-2: Tum image yollari binding map ile dogrulandi
- [ ] `font-heading` kullanildi, `font-[X]` YOK
- [ ] Component dosyalarinda yorum blogu YOK (spec dosyasi ayri)

**Orchestrator review:**
- [ ] Step 3.6: Dev server baslatildi, klonun screenshot'lari alindi
- [ ] Her section orijinal ile karsilastirildi (desktop/tablet/mobile)
- [ ] Farkliliklar tespit edildi, ilgili builder'lara SPESIFIK duzeltme talimati ile yeniden dispatch yapildi
- [ ] Max 3 iterasyon sonra raporlandi

### PHASE 4: Assembly & Final QA
- [ ] page.tsx tum component'leri import ediyor
- [ ] `npm run build` temiz geciyor
- [ ] Full-page screenshot 3 viewport'ta alindi
- [ ] Orijinal ile son karsilastirma yapildi
