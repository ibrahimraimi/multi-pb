<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { api } from '$lib/api';

	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			const res = await api.getStatus();
			if (res.success && res.data) {
				if (!res.data.setup_done) {
					goto('/setup');
				} else {
					goto('/dashboard');
				}
			} else {
				error = res.error || 'Failed to connect to server';
			}
		} catch (e) {
			error = String(e);
		} finally {
			loading = false;
		}
	});
</script>

<div class="flex min-h-screen items-center justify-center">
	{#if loading}
		<div class="text-center">
			<div
				class="mb-4 inline-block h-12 w-12 animate-spin rounded-full border-4 border-blue-500 border-t-transparent"
			></div>
			<p class="text-gray-400">Loading...</p>
		</div>
	{:else if error}
		<div class="max-w-md rounded-lg bg-red-900/50 p-6 text-center">
			<h2 class="mb-2 text-xl font-bold text-red-400">Connection Error</h2>
			<p class="text-gray-300">{error}</p>
			<button
				onclick={() => window.location.reload()}
				class="mt-4 rounded bg-red-600 px-4 py-2 hover:bg-red-700"
			>
				Retry
			</button>
		</div>
	{/if}
</div>
