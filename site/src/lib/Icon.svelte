<script lang="ts">
    let { name, size = 22 }: { name: string; size?: number } = $props();
</script>

<svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    {#if name === "import"}
        <path d="M12 4v11M7.5 10.5 12 15l4.5-4.5" /><path d="M4 16v2.5A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5V16" />
    {:else if name === "compare"}
        <rect x="3" y="4.5" width="18" height="15" rx="2.5" /><path d="M12 4.5v15" /><path d="m6.5 9 3 3-3 .8zM14.5 9l3 3-3 .8z" />
    {:else if name === "mix"}
        <path d="M4 7h10l-3-3M20 17H10l3 3" /><path d="M4 7a3 3 0 0 0 0 0M20 17" />
    {:else if name === "tune"}
        <path d="M4 7h9M17 7h3M4 17h3M11 17h9" /><circle cx="15" cy="7" r="2" /><circle cx="9" cy="17" r="2" />
    {:else if name === "reapply"}
        <path d="M20 12a8 8 0 1 1-2.3-5.7" /><path d="M20 4v4.5h-4.5" />
    {:else}
        <path d="M12 3.5 5 6.5v5c0 4.2 2.8 7.3 7 9 4.2-1.7 7-4.8 7-9v-5z" /><path d="m9 12 2.2 2.2L15.5 10" />
    {/if}
</svg>
