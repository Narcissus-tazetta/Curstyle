<script lang="ts">
    import { asset, resolve } from "$app/paths";
    import CopyButton from "./CopyButton.svelte";
    import CursorStage from "./CursorStage.svelte";
    import Icon from "./Icon.svelte";
    import { brewCommand, dictionaries, repo, siteUrl, type Lang } from "./i18n";

    let { lang, release }: { lang: Lang; release: { version: string; date: string } } = $props();

    const t = $derived(dictionaries[lang]);
    const other = $derived(lang === "ja" ? "en" : "ja");
    const pageUrl = { en: `${siteUrl}/`, ja: `${siteUrl}/ja/` } as const;

    let scrolled = $state(false);
</script>

<svelte:window onscroll={() => (scrolled = window.scrollY > 8)} />

<svelte:head>
    <title>{t.title}</title>
    <meta name="description" content={t.description} />
    <link rel="canonical" href={pageUrl[lang]} />
    <link rel="alternate" hreflang="en" href={pageUrl.en} />
    <link rel="alternate" hreflang="ja" href={pageUrl.ja} />
    <link rel="alternate" hreflang="x-default" href={pageUrl.en} />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Curstyle" />
    <meta property="og:locale" content={t.locale} />
    <meta property="og:title" content={t.title} />
    <meta property="og:description" content={t.description} />
    <meta property="og:url" content={pageUrl[lang]} />
    <meta name="twitter:card" content="summary" />
</svelte:head>

<header class:scrolled>
    <div class="bar">
        <a class="brand" href={lang === "ja" ? resolve("/ja") : resolve("/")}>
            <img src={asset("icon.svg")} alt="" width="26" height="26" />
            Curstyle
        </a>
        <nav>
            <a href="#features">{t.nav.features}</a>
            <a href="#install">{t.nav.install}</a>
            <a href="#faq">{t.nav.faq}</a>
            <a href={repo}>{t.nav.github}</a>
            <a
                class="lang"
                href={other === "ja" ? resolve("/ja") : resolve("/")}
                hreflang={other}
                onclick={() => localStorage.setItem("lang", other)}>{t.switchLabel}</a
            >
        </nav>
    </div>
</header>

<main>
    <section class="hero">
        <div class="glow" aria-hidden="true"></div>
        <h1>{t.hero.title}</h1>
        <p class="lead">{t.hero.lead}</p>
        <div class="cta">
            <a class="primary" href="#install">{t.hero.primary}</a>
            <a class="secondary" href={repo}>{t.hero.secondary}</a>
        </div>
        <p class="meta">{t.hero.meta}</p>
        <div class="stage-slot"><CursorStage t={t.stage} /></div>
    </section>

    <section id="features" class="section">
        <div class="inner">
            <h2>{t.features.title}</h2>
            <div class="grid">
                {#each t.features.items as item (item.id)}
                    <article class="card">
                        <span class="icon"><Icon name={item.id} /></span>
                        <h3>{item.title}</h3>
                        <p>{item.body}</p>
                    </article>
                {/each}
            </div>
        </div>
    </section>

    <section class="section showcase">
        <div class="inner">
            <div class="shot wide">
                <div class="copy">
                    <h2>{t.showcase.compareTitle}</h2>
                    <p>{t.showcase.compareBody}</p>
                </div>
                <img src={asset("screens/comparison.webp")} alt={t.showcase.compareAlt} width="1600" height="999" loading="lazy" />
            </div>
            <div class="shot split">
                <img src={asset("screens/replace.webp")} alt={t.showcase.replaceAlt} width="1000" height="891" loading="lazy" />
                <div class="copy">
                    <h2>{t.showcase.replaceTitle}</h2>
                    <p>{t.showcase.replaceBody}</p>
                    <p class="credit"><a href={t.showcase.creditUrl}>{t.showcase.credit}</a></p>
                </div>
            </div>
        </div>
    </section>

    <section id="install" class="section">
        <div class="inner narrow">
            <h2>{t.install.title}</h2>
            <p class="sub">{t.install.lead} <span class="ver">{t.install.latest(release.version, release.date)}</span></p>

            <h3>{t.install.brew}</h3>
            <div class="code">
                <code>{brewCommand}</code>
                <CopyButton text={brewCommand} label={t.install.copy} done={t.install.copied} />
            </div>

            <h3>{t.install.manual}</h3>
            <ol>
                {#each t.install.steps as step (step)}
                    <li>{step}</li>
                {/each}
            </ol>
            <a class="primary small" href="{repo}/releases/latest">{t.install.releases}</a>

            <div class="warn">
                <h3>{t.install.warningTitle}</h3>
                <p>{t.install.warning}</p>
            </div>
        </div>
    </section>

    <section id="faq" class="section">
        <div class="inner narrow">
            <h2>{t.faq.title}</h2>
            <div class="faq">
                {#each t.faq.items as item (item.q)}
                    <details>
                        <summary>{item.q}</summary>
                        <p>{item.a}</p>
                    </details>
                {/each}
            </div>
        </div>
    </section>
</main>

<footer>
    <div class="foot">
        <div class="links">
            <a href={repo}>{t.footer.github}</a>
            <a href="{repo}/releases">{t.footer.releases}</a>
            <span>{t.footer.license}</span>
        </div>
        <p>{t.footer.note}</p>
    </div>
</footer>

<style>
    header {
        position: sticky;
        top: 0;
        z-index: 10;
        border-bottom: 1px solid transparent;
        transition:
            background 0.2s,
            border-color 0.2s;
    }

    header.scrolled {
        border-color: var(--line);
        background: rgb(7 8 12 / 0.8);
        backdrop-filter: blur(14px);
    }

    .bar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        max-width: var(--max);
        height: 60px;
        margin: 0 auto;
        padding: 0 24px;
    }

    .brand {
        display: flex;
        align-items: center;
        gap: 10px;
        font-weight: 700;
        letter-spacing: -0.01em;
        text-decoration: none;
    }

    .brand img {
        border-radius: 7px;
    }

    nav {
        display: flex;
        align-items: center;
        gap: 22px;
        color: var(--muted);
        font-size: 14px;
    }

    nav a {
        text-decoration: none;
    }

    nav a:hover {
        color: var(--fg);
    }

    nav .lang {
        padding: 3px 10px;
        border: 1px solid var(--line-strong);
        border-radius: 8px;
    }

    .hero {
        position: relative;
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 72px 24px 88px;
        overflow: hidden;
        text-align: center;
    }

    .glow {
        position: absolute;
        top: -160px;
        left: 50%;
        width: 900px;
        height: 560px;
        transform: translateX(-50%);
        background: radial-gradient(closest-side, rgb(0 252 255 / 0.16), rgb(47 91 255 / 0.12) 55%, transparent);
        pointer-events: none;
    }

    h1 {
        position: relative;
        max-width: 14em;
        text-wrap: balance;
        font-size: clamp(36px, 6.4vw, 66px);
        line-height: 1.1;
        letter-spacing: -0.035em;
        background: linear-gradient(180deg, #fff 30%, #9fb4ff);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
    }

    .lead {
        position: relative;
        max-width: 38em;
        margin-top: 22px;
        color: var(--muted);
        font-size: clamp(16px, 2vw, 18px);
    }

    .cta {
        position: relative;
        display: flex;
        gap: 12px;
        margin-top: 30px;
    }

    .primary,
    .secondary {
        padding: 11px 24px;
        border-radius: 12px;
        font-weight: 600;
        text-decoration: none;
    }

    .primary {
        background: var(--grad);
        color: #021024;
    }

    .primary.small {
        display: inline-block;
        margin-top: 8px;
        padding: 8px 18px;
        font-size: 14px;
    }

    .secondary {
        border: 1px solid var(--line-strong);
        background: rgb(255 255 255 / 0.04);
    }

    .meta {
        position: relative;
        margin-top: 16px;
        color: var(--muted);
        font-size: 13px;
    }

    .stage-slot {
        position: relative;
        width: 100%;
        margin-top: 52px;
    }

    .section {
        padding: 88px 24px;
        border-top: 1px solid var(--line);
    }

    .inner {
        max-width: var(--max);
        margin: 0 auto;
    }

    .inner.narrow {
        max-width: 760px;
    }

    h2 {
        font-size: clamp(24px, 3.4vw, 34px);
        line-height: 1.25;
        letter-spacing: -0.02em;
    }

    h3 {
        font-size: 16px;
    }

    .grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 16px;
        margin-top: 36px;
    }

    .card {
        padding: 24px;
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--bg-raised);
    }

    .icon {
        display: inline-grid;
        place-items: center;
        width: 40px;
        height: 40px;
        margin-bottom: 14px;
        border-radius: 11px;
        background: rgb(0 252 255 / 0.08);
        color: var(--cyan);
    }

    .card p {
        margin-top: 6px;
        color: var(--muted);
        font-size: 14px;
        line-height: 1.75;
    }

    .showcase .inner {
        display: flex;
        flex-direction: column;
        gap: 72px;
    }

    .shot {
        display: flex;
        flex-direction: column;
        gap: 28px;
    }

    .shot.split {
        flex-direction: row;
        align-items: center;
        gap: 48px;
    }

    .shot.split img {
        width: min(46%, 440px);
    }

    .shot.split .copy {
        flex: 1;
    }

    .shot img {
        height: auto;
        border: 1px solid var(--line-strong);
        border-radius: 14px;
        box-shadow: 0 40px 80px -30px rgb(0 0 0 / 0.8);
    }

    .shot.wide img {
        width: 100%;
    }

    .copy p {
        max-width: 34em;
        margin-top: 12px;
        color: var(--muted);
    }

    .copy .credit {
        font-size: 12px;
    }

    .copy .credit a {
        text-underline-offset: 3px;
    }

    .sub {
        margin-top: 8px;
        color: var(--muted);
    }

    .ver {
        margin-left: 8px;
        padding: 2px 10px;
        border: 1px solid var(--line-strong);
        border-radius: 999px;
        font-size: 12px;
    }

    #install h3 {
        margin-top: 32px;
        margin-bottom: 10px;
    }

    .code {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 12px 14px;
        border: 1px solid var(--line-strong);
        border-radius: 12px;
        background: var(--bg-raised);
    }

    code {
        overflow-x: auto;
        font-family: var(--mono);
        font-size: 13px;
        white-space: nowrap;
    }

    ol {
        margin: 0 0 14px;
        padding-left: 1.3em;
        color: var(--muted);
    }

    .warn {
        margin-top: 36px;
        padding: 18px 20px;
        border: 1px solid rgb(255 190 80 / 0.28);
        border-radius: 12px;
        background: rgb(255 190 80 / 0.05);
    }

    .warn h3 {
        margin: 0 0 6px !important;
    }

    .warn p {
        color: var(--muted);
        font-size: 14px;
    }

    .faq {
        margin-top: 24px;
        border-top: 1px solid var(--line);
    }

    details {
        border-bottom: 1px solid var(--line);
    }

    summary {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        padding: 18px 2px;
        font-size: 15px;
        font-weight: 600;
        list-style: none;
        cursor: pointer;
    }

    summary::-webkit-details-marker {
        display: none;
    }

    summary::after {
        content: "";
        flex: none;
        width: 8px;
        height: 8px;
        margin-right: 4px;
        border-right: 1.5px solid var(--muted);
        border-bottom: 1.5px solid var(--muted);
        transform: translateY(-2px) rotate(45deg);
        transition: transform 0.2s;
    }

    details[open] summary::after {
        transform: translateY(2px) rotate(-135deg);
    }

    details p {
        max-width: 64ch;
        padding: 0 2px 20px;
        color: var(--muted);
        font-size: 14px;
        line-height: 1.75;
    }

    footer {
        padding: 40px 24px 56px;
        border-top: 1px solid var(--line);
        color: var(--muted);
        font-size: 13px;
    }

    .foot {
        display: flex;
        flex-direction: column;
        gap: 10px;
        max-width: var(--max);
        margin: 0 auto;
    }

    .links {
        display: flex;
        gap: 20px;
    }

    @media (max-width: 860px) {
        .grid {
            grid-template-columns: repeat(2, 1fr);
        }

        .shot.split {
            flex-direction: column;
            align-items: flex-start;
        }

        .shot.split img {
            width: 100%;
        }
    }

    @media (max-width: 560px) {
        .bar {
            padding: 0 16px;
        }

        nav {
            gap: 14px;
        }

        nav a:nth-child(-n + 3) {
            display: none;
        }

        .grid {
            grid-template-columns: 1fr;
        }

        .section {
            padding: 64px 16px;
        }

        .hero {
            padding: 48px 16px 64px;
        }
    }
</style>
