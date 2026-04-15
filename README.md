# Klonlama Skill

Bir Claude Code skill'i: herhangi bir web sitesini **%90–95 görsel sadakatle**
section-by-section klonlar. Ücretli API gerekmez — yalnızca Playwright (ya da
Chrome MCP) ve standart CLI araçları kullanır.

> Claude Code, Anthropic'in resmi CLI'ı (`claude.ai/code`). Bu skill o CLI'ın
> yerel `skills/` dizinine kurulur ve `Skill` tool'u ile çağrılır.

## Ne yapar?

Bir URL veriyorsun, skill 4 fazda klonu üretiyor:

1. **Reconnaissance** — 3 viewport screenshot, section map, design tokens,
   @font-face URL resolve, smooth scroll library detection, interaction sweep
   (hover/scroll/responsive), visual wrapper scan.
2. **Asset Collection** — tüm `<img>`, inline SVG, background image, **video**
   ve font dosyalarını indirir; her görsel için "hangi component'e ait" binding
   map'i oluşturur.
3. **Section-by-Section Cloning** — her section için ayrı bir spec dosyası
   yazar ve *component-by-component* (asla toplu paralel değil) build +
   render + karşılaştır + düzelt döngüsü uygular.
4. **Assembly & QA** — tüm component'leri birleştirir, dev server'da
   render eder, 3 viewport'ta orijinalle yan yana karşılaştırır, fark kalırsa
   spesifik düzeltme dispatch eder.

## Kurulum

**Tek satırlık kurulum:**

```bash
git clone https://github.com/<kullanici>/klonlama-skill.git
cd klonlama-skill
./install.sh
```

**Manuel:** `skills/klonlama/SKILL.md` dosyasını `~/.claude/skills/klonlama/`
altına kopyala. Claude Code bir sonraki açılışta skill'i otomatik algılar.

```bash
mkdir -p ~/.claude/skills/klonlama
cp skills/klonlama/SKILL.md ~/.claude/skills/klonlama/SKILL.md
```

## Kullanım

Claude Code oturumunda:

```
/klonlama https://example.com/
```

veya doğal dil ile:

```
https://example.com/ sitesini klonla
```

Claude otomatik olarak klonlama skill'ini yükler, PHASE 1'den başlayarak
workflow'u yürütür. Her fazın sonunda task list'e bakarak ilerlemeyi
takip edebilirsin.

## Nasıl çalışır — workflow özeti

```
PHASE 1: Reconnaissance
  1.1 Screenshot (desktop/tablet/mobile)
  1.2 Section map (tag-based)
  1.2b Visual wrapper scan (renkli/rounded div'ler)   ← kritik
  1.3 Global design tokens + resolved @font-face URLs
  1.4 Smooth scroll library detection
  1.5 Interaction sweep → BEHAVIORS.md
  1.6 Responsive sweep comparison

PHASE 2: Asset Collection
  2.1 Images
  2.2 SVGs & icons
  2.3 Background images
  2.4 Image binding map
  2.5 Video detection                                 ← Lesson 3
  2.6 Fonts (resolved URLs, file-type verified)

PHASE 3: Section-by-Section Cloning
  3.1 3-viewport section screenshots
  3.2 Deep CSS extraction
  3.2b Component tree extraction
  3.3 HTML structure
  3.3b Hover state extraction
  3.4a Spec file → docs/research/components/*.spec.md
  3.4b Component-by-component build (seri — paralel DEĞİL)
  3.5 Visual comparison loop
  3.6 Orchestrator review → iterative fix dispatch

PHASE 4: Assembly & Final QA
```

## Gereksinimler

- **Node.js 18+** (Playwright için)
- **Claude Code CLI** (`https://claude.ai/code`)
- **Playwright** — ilk çalıştırmada `npx playwright install chromium`
- **curl** veya **wget** — asset indirme
- (Opsiyonel) Chrome MCP extension — Playwright yerine tarayıcı kontrolü için

## Öğrenilen dersler

Skill'in sonundaki **"Lessons Learned"** bölümü, gerçek klonlama oturumlarından
çıkarılmış spesifik dersler içerir. Örnekler:

- Nav link text rengi A tag'inde değil iç `<span>`'da (WordPress/Salient)
- `<header>` tag'i asıl olive bar değil — `#header-outer` wrapper'ı
- Hero'da `<video class="nectar-video-bg">` varsa static image kullanma
- Component-by-component sıralı build (toplu paralel dispatch hataları
  tekrarlatır)
- `<br/>` ile zorla heading line break (font kerning farkından dolayı
  max-width tahmin çalışmaz)
- `min(80vh, 740px)` hibrit yükseklikler — kullanıcı iteratif ayar ister

Tam liste: `skills/klonlama/SKILL.md` içinde `## Lessons Learned` bölümü.

## Katkı

Klonlama skill'i sürekli gelişir. Yeni bir edge case bulursan:

1. Skill dosyasını fork et
2. `## Lessons Learned` altına yeni bir `### Lesson N` ekle (gerekçe + örnek kod)
3. PR gönder

## Lisans

MIT — `LICENSE` dosyasına bak.

---

**Yapan:** SEYO Reklam Ajansı · **Katkı ve sorular:** GitHub issue aç ya da
Instagram [@seyoweb](https://instagram.com/seyoweb)
