<script lang="ts">
	import "../app.css";
	import { onMount, onDestroy } from "svelte";
	import {
		needsAuthModal,
		checkAuthRequired,
		authRequired,
		API_BASE,
		adminToken,
	} from "$lib/api";
	import UnlockModal from "$lib/UnlockModal.svelte";
	import { fade, fly } from "svelte/transition";

	let restoreStatus: any = null;
	let restoreInterval: any = null;

	async function checkRestoreStatus() {
		try {
			const headers: any = {};
			if ($adminToken) headers["Authorization"] = `Bearer ${$adminToken}`;

			// API_BASE is "/api", so we append "/system/status"
			// But wait, API_BASE is "/api". The path is "/system/status".
			// If I use `${API_BASE}/system/status`, it becomes `/api/system/status`.
			const res = await fetch(`${API_BASE}/system/status`, { headers });
			if (res.ok) {
				const status = await res.json();
				if (status.restoring) {
					restoreStatus = status;
				} else {
					restoreStatus = null;
				}
			}
		} catch (e) {
			console.error("Failed to check restore status", e);
		}
	}

	onMount(async () => {
		// Check if server requires auth before allowing access
		await checkAuthRequired();

		// Check restore status every 2 seconds
		checkRestoreStatus();
		restoreInterval = setInterval(checkRestoreStatus, 2000);

		return () => {
			if (restoreInterval) clearInterval(restoreInterval);
		};
	});
</script>

<svelte:head>
	<title>Multi-PB Dashboard</title>
</svelte:head>

{#if $authRequired === null}
	<!-- Checking auth requirement -->
	<div class="min-h-screen bg-[#0a0a0a] flex items-center justify-center">
		<div class="text-center">
			<div
				class="inline-block animate-spin rounded-full h-8 w-8 border-2 border-emerald-500 border-t-transparent mb-4"
			></div>
			<p class="text-gray-500 text-sm">Checking authentication...</p>
		</div>
	</div>
{:else if $authRequired && $needsAuthModal}
	<!-- Auth required but no valid token - show modal, block access -->
	<div class="min-h-screen bg-[#0a0a0a]">
		<UnlockModal />
	</div>
{:else}
	<!-- Restore Status Banner -->
	{#if restoreStatus}
		<div
			in:fly={{ y: -50 }}
			out:fade
			class="fixed top-0 left-0 right-0 z-50 bg-blue-600/90 backdrop-blur text-white px-4 py-3 shadow-lg flex items-center justify-center gap-3"
		>
			<div
				class="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent"
			></div>
			<span class="font-medium">Restoring instances:</span>
			<span class="opacity-90">{restoreStatus.current}</span>
			<span class="text-xs bg-white/20 px-2 py-0.5 rounded ml-2"
				>{restoreStatus.completed}/{restoreStatus.total}</span
			>
		</div>
	{/if}

	<!-- Auth not required, or auth required and token is valid -->
	<main class="min-h-screen">
		<slot />
	</main>
	{#if $needsAuthModal}
		<UnlockModal />
	{/if}
{/if}
