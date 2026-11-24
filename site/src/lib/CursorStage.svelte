<script lang="ts">
    import type { Dict } from "./i18n";

    let { t }: { t: Dict["stage"] } = $props();

    type Role = "arrow" | "text" | "link";
    type ThemeId = keyof Dict["stage"]["themes"];

    // Hotspots are in the 24-unit viewBox of the shapes below, so the tip sits exactly on the pointer.
    const hotspot: Record<Role, [number, number]> = { arrow: [4, 2.5], text: [12, 12], link: [8, 2] };
    const shapes: Record<Role, string[]> = {
        arrow: ["M4 2.5V19.5L8.6 15.4L11.6 21.8L14.4 20.5L11.4 14.2L17.6 13.7Z"],
        text: ["M8.5 3.5H15.5M12 3.5V20.5M8.5 20.5H15.5"],
        link: [
            "M10 9.5V4a2 2 0 0 0-4 0v10",
            "M18 11a2 2 0 1 1 4 0v3a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15",
            "M14 10V9a2 2 0 0 0-4 0v1",
            "M18 11v-1a2 2 0 0 0-4 0",
        ],
    };

    const palettes: Record<ThemeId, { fill: string; edge: string; glow: string }> = {
        system: { fill: "#ffffff", edge: "#000000", glow: "transparent" },
        amber: { fill: "#ff9f1c", edge: "#2a1700", glow: "transparent" },
        neon: { fill: "#00fcff", edge: "#04163a", glow: "#00fcff" },
        ink: { fill: "#15171d", edge: "#ffffff", glow: "transparent" },
    };
    const themeIds = Object.keys(palettes) as ThemeId[];
    const roles: Role[] = ["arrow", "text", "link"];
    const base = 30;

    let theme = $state<ThemeId>("amber");
    let scale = $state(1);
    let role = $state<Role>("arrow");
    let x = $state(0);
    let y = $state(0);
    let inside = $state(false);
    let live = $state(false);

    const palette = $derived(palettes[theme]);

    $effect(() => {
        // Hiding the system cursor is only safe once script is running and a real mouse is present.
        live = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
    });

    function move(event: PointerEvent) {
        if (event.pointerType !== "mouse") return;
        const stage = event.currentTarget as HTMLElement;
        const box = stage.getBoundingClientRect();
        x = event.clientX - box.left;
        y = event.clientY - box.top;
        const target = event.target as Element;
        role = (target.closest<HTMLElement>("[data-cursor]")?.dataset.cursor as Role | undefined) ?? "arrow";
        inside = true;
    }
</script>

<div class="wrap">
    <div class="bar">
        <div class="themes" role="group" aria-label={t.label}>
            {#each themeIds as id (id)}
                <button type="button" class:on={theme === id} onclick={() => (theme = id)}>{t.themes[id]}</button>
            {/each}
        </div>
        <label class="size">
            <span>{t.size}</span>
            <input type="range" min="0.7" max="2" step="0.1" bind:value={scale} />
            <output>{scale.toFixed(1)}×</output>
        </label>
    </div>

    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
        class="stage"
        class:live
        onpointermove={move}
        onpointerleave={() => (inside = false)}
        onpointerdown={move}
    >
        <p class="sample" data-cursor="text">{t.text}</p>
        <div class="row">
            <a class="link" href="#install" data-cursor="link">{t.link}</a>
            <button type="button" class="btn" data-cursor="link">{t.button}</button>
        </div>

        {#if live && inside}
            <svg
                class="cursor"
                viewBox="0 0 24 24"
                width={base * scale}
                height={base * scale}
                style:transform="translate({x - hotspot[role][0] * ((base * scale) / 24)}px, {y -
                    hotspot[role][1] * ((base * scale) / 24)}px)"
                style:filter={palette.glow === "transparent"
                    ? "drop-shadow(0 2px 3px rgb(0 0 0 / .45))"
                    : `drop-shadow(0 0 6px ${palette.glow})`}
                aria-hidden="true"
            >
                {#if role === "arrow"}
                    <path d={shapes.arrow[0]} fill={palette.fill} stroke={palette.edge} stroke-width="1.6" stroke-linejoin="round" />
                {:else}
                    {#each shapes[role] as d (d)}
                        <path {d} fill="none" stroke={palette.edge} stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round" />
                    {/each}
                    {#each shapes[role] as d (d)}
                        <path {d} fill="none" stroke={palette.fill} stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                    {/each}
                {/if}
            </svg>
        {/if}
    </div>

    <div class="roles" aria-label={t.label}>
        {#each roles as r (r)}
            <div class="role" class:on={role === r && inside}>
                <svg viewBox="0 0 24 24" width="28" height="28" aria-hidden="true">
                    {#if r === "arrow"}
                        <path d={shapes.arrow[0]} fill={palette.fill} stroke={palette.edge} stroke-width="1.6" stroke-linejoin="round" />
                    {:else}
                        {#each shapes[r] as d (d)}
                            <path {d} fill="none" stroke={palette.edge} stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round" />
                        {/each}
                        {#each shapes[r] as d (d)}
                            <path {d} fill="none" stroke={palette.fill} stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                        {/each}
                    {/if}
                </svg>
                <span>{t.roles[r]}</span>
            </div>
        {/each}
    </div>

    <p class="hint">{live ? t.hint : t.note}</p>
    {#if live}<p class="note">{t.note}</p>{/if}
</div>

<style>
    .wrap {
        width: 100%;
        max-width: 640px;
        margin: 0 auto;
        padding: 14px;
        border: 1px solid var(--line-strong);
        border-radius: 20px;
        background: linear-gradient(180deg, rgb(255 255 255 / 0.05), rgb(255 255 255 / 0.02));
        box-shadow: 0 40px 80px -30px rgb(0 80 255 / 0.35);
    }

    .bar {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        margin-bottom: 12px;
    }

    .themes {
        display: flex;
        gap: 4px;
        padding: 3px;
        border: 1px solid var(--line);
        border-radius: 10px;
        background: rgb(0 0 0 / 0.3);
    }

    .themes button {
        padding: 4px 12px;
        border: 0;
        border-radius: 7px;
        background: transparent;
        color: var(--muted);
        font: inherit;
        font-size: 13px;
        cursor: pointer;
    }

    .themes button.on {
        background: rgb(255 255 255 / 0.12);
        color: var(--fg);
    }

    .size {
        display: flex;
        align-items: center;
        gap: 8px;
        color: var(--muted);
        font-size: 13px;
    }

    .size input {
        width: 110px;
        accent-color: var(--cyan);
    }

    output {
        min-width: 3ch;
        color: var(--fg);
        font-variant-numeric: tabular-nums;
    }

    .stage {
        position: relative;
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 22px;
        min-height: 220px;
        padding: 28px;
        overflow: hidden;
        border: 1px solid var(--line);
        border-radius: 12px;
        background: #0b0d12;
        text-align: left;
        touch-action: pan-y;
    }

    .stage.live {
        cursor: none;
    }

    .stage.live * {
        cursor: none;
    }

    .sample {
        font-size: 17px;
        line-height: 1.6;
    }

    .row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 18px;
    }

    .link {
        color: #6ea2ff;
        text-decoration: underline;
        text-underline-offset: 3px;
    }

    .btn {
        padding: 7px 20px;
        border: 0;
        border-radius: 999px;
        background: #8cb4ff;
        color: #0a1226;
        font: inherit;
        font-weight: 600;
    }

    .cursor {
        position: absolute;
        top: 0;
        left: 0;
        pointer-events: none;
        will-change: transform;
    }

    .roles {
        display: flex;
        justify-content: center;
        gap: 10px;
        margin-top: 12px;
    }

    .role {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 6px 12px;
        border: 1px solid var(--line);
        border-radius: 10px;
        background: #0b0d12;
        color: var(--muted);
        font-size: 12px;
        transition: border-color 0.15s;
    }

    .role.on {
        border-color: var(--cyan);
        color: var(--fg);
    }

    .hint {
        margin-top: 12px;
        color: var(--muted);
        font-size: 13px;
    }

    .note {
        margin-top: 2px;
        color: rgb(152 160 174 / 0.7);
        font-size: 12px;
    }

    @media (max-width: 560px) {
        .stage {
            padding: 20px;
        }
    }
</style>
