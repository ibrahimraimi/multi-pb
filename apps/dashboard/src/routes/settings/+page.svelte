<script lang="ts">
	import { onMount } from 'svelte';
	import { apiFetch } from '$lib/api';

	let dnsDomain = '';
	let saving = false;
	let error: string | null = null;
	let success = false;

	async function loadDns() {
		try {
			const res = await apiFetch('/dns/config');
			if (res.ok) {
				const data = await res.json();
				dnsDomain = data.domain || '';
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load DNS settings';
		}
	}

	let warning: string | null = null;

	async function saveDns() {
		saving = true;
		error = null;
		success = false;
		warning = null;
		try {
			const res = await apiFetch('/dns/config', {
				method: 'PATCH',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ domain: dnsDomain })
			});
			const data = await res.json();
			if (res.status === 400) throw new Error(data.error || 'Invalid domain');
			if (res.status === 207) {
				dnsDomain = data.domain || '';
				warning = data.warning + (data.reloadError ? `: ${data.reloadError}` : '');
				return;
			}
			if (!res.ok) throw new Error(data.error || 'Failed to save');
			dnsDomain = data.domain || '';
			success = true;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save DNS settings';
		} finally {
			saving = false;
		}
	}

	onMount(() => loadDns());
</script>

<div class="flex min-h-screen bg-[#0a0a0a] text-gray-100 font-sans">
	<!-- Sidebar (match main dashboard) -->
	<aside class="w-64 bg-[#111] border-r border-gray-800/50 flex flex-col p-5">
		<div class="flex items-center gap-3 mb-10 px-2">
			<div class="w-9 h-9 bg-emerald-500 rounded-lg flex items-center justify-center">
				<svg class="w-5 h-5 text-black" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
					<path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
				</svg>
			</div>
			<span class="text-lg font-bold tracking-tight">Multi-PB</span>
		</div>

		<nav class="flex-1 space-y-1">
			<a
				href=".."
				class="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-gray-500 hover:bg-gray-800/50 hover:text-gray-300 font-medium text-sm transition-all"
			>
				<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<rect x="3" y="3" width="7" height="7" /><rect x="14" y="3" width="7" height="7" />
					<rect x="14" y="14" width="7" height="7" /><rect x="3" y="14" width="7" height="7" />
				</svg>
				Dashboard
			</a>
			<div
				class="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg bg-emerald-500/10 text-emerald-400 font-medium text-sm border border-emerald-500/20"
			>
				<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06a1.65 1.65 0 001.82.33H9a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06a1.65 1.65 0 00-.33 1.82V9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z" />
				</svg>
				Settings
			</div>
			<a
				href="https://pocketbase.io/docs"
				target="_blank"
				rel="noopener"
				class="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-gray-500 hover:bg-gray-800/50 hover:text-gray-300 font-medium text-sm transition-all"
			>
				<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" /><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8" />
				</svg>
				PocketBase Docs
			</a>
		</nav>

		<div class="mt-auto pt-4 border-t border-gray-800/50 space-y-1">
			<div class="flex items-center gap-3 px-2">
				<div class="w-8 h-8 rounded-full bg-gray-800 flex items-center justify-center text-xs font-bold text-emerald-400">A</div>
				<div>
					<p class="text-sm font-medium text-gray-300">Admin</p>
					<p class="text-xs text-gray-600">Super User</p>
				</div>
			</div>
		</div>
	</aside>

	<!-- Main Content -->
	<main class="flex-1 p-6 overflow-y-auto">
		<header class="mb-8">
			<h1 class="text-2xl font-bold text-white mb-1">Settings</h1>
			<p class="text-gray-500 text-sm">DNS and system configuration</p>
		</header>

		{#if error}
			<div class="bg-red-500/10 border border-red-500/20 text-red-400 px-4 py-3 rounded-lg mb-6 text-sm">
				{error}
				<button on:click={() => (error = null)} class="float-right text-red-400 hover:text-red-300">&times;</button>
			</div>
		{/if}
		{#if warning}
			<div class="bg-yellow-500/10 border border-yellow-500/20 text-yellow-400 px-4 py-3 rounded-lg mb-6 text-sm">
				{warning}
				<button on:click={() => (warning = null)} class="float-right text-yellow-400 hover:text-yellow-300">&times;</button>
			</div>
		{/if}
		{#if success}
			<div class="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 px-4 py-3 rounded-lg mb-6 text-sm">
				DNS settings saved. Caddy has been reloaded.
			</div>
		{/if}

		<!-- DNS Settings -->
		<div class="bg-[#111] rounded-xl border border-gray-800/50 p-6 max-w-xl">
			<h2 class="text-lg font-semibold text-white mb-1">DNS / Domain</h2>
			<p class="text-gray-500 text-sm mb-4">
				Set a domain to serve over HTTPS. Caddy will obtain and renew TLS certificates. Leave empty to use HTTP on the configured port.
			</p>
			<div class="flex gap-3 items-end">
				<div class="flex-1">
					<label for="dns-domain" class="block text-xs font-medium text-gray-500 uppercase mb-2">Domain</label>
					<input
						id="dns-domain"
						type="text"
						bind:value={dnsDomain}
						placeholder="pb.example.com"
						class="w-full bg-[#0a0a0a] border border-gray-800 rounded-lg px-4 py-2.5 focus:outline-none focus:border-emerald-500/50 transition-all text-white placeholder-gray-600 font-mono text-sm"
					/>
				</div>
				<button
					on:click={saveDns}
					disabled={saving}
					class="px-5 py-2.5 bg-emerald-500 hover:bg-emerald-600 disabled:opacity-50 text-black rounded-lg font-semibold text-sm transition-all"
				>
					{saving ? 'Saving...' : 'Save'}
				</button>
			</div>
			<p class="text-xs text-gray-600 mt-2">
				Ensure DNS for this domain points to this server. Ports 80 and 443 must be exposed (e.g. in docker-compose).
			</p>
		</div>
	</main>
</div>
