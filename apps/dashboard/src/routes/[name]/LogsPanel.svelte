<script lang="ts">
	import { onMount } from 'svelte';
	import { apiFetch } from '$lib/api';

	export let instanceName: string;

	let logs = '';
	let errLogs = '';
	let loading = true;
	let activeTab: 'stdout' | 'stderr' = 'stdout';
	let autoRefresh = true;

	async function fetchLogs() {
		try {
			const res = await apiFetch(`/instances/${instanceName}/logs`);
			if (!res.ok) throw new Error('Failed to fetch logs');
			const data = await res.json();
			logs = data.logs || '';
			errLogs = data.errLogs || '';
		} catch (e) {
			errLogs = `Error: ${e.message}`;
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		fetchLogs();
		const interval = setInterval(() => {
			if (autoRefresh) fetchLogs();
		}, 3000);
		return () => clearInterval(interval);
	});

	$: currentLogs = activeTab === 'stdout' ? logs : errLogs;
</script>

<div class="bg-[#111] rounded-xl border border-gray-800/50 overflow-hidden">
	<div class="flex items-center justify-between p-4 border-b border-gray-800/50">
		<div class="flex gap-1 bg-[#0a0a0a] p-1 rounded-lg">
			<button 
				on:click={() => activeTab = 'stdout'} 
				class="px-4 py-1.5 rounded-md text-sm font-medium transition-all {activeTab === 'stdout' ? 'bg-gray-800 text-white' : 'text-gray-500 hover:text-gray-300'}"
			>
				stdout
			</button>
			<button 
				on:click={() => activeTab = 'stderr'} 
				class="px-4 py-1.5 rounded-md text-sm font-medium transition-all {activeTab === 'stderr' ? 'bg-gray-800 text-white' : 'text-gray-500 hover:text-gray-300'}"
			>
				stderr
			</button>
		</div>
		<div class="flex items-center gap-4">
			<label class="flex items-center gap-2 text-sm text-gray-400 cursor-pointer">
				<input type="checkbox" bind:checked={autoRefresh} class="w-4 h-4 rounded border-gray-700 bg-gray-800" />
				Auto-refresh
			</label>
			<button on:click={fetchLogs} class="px-4 py-1.5 bg-gray-800 hover:bg-gray-700 rounded-lg text-sm font-medium transition-all">
				Refresh
			</button>
		</div>
	</div>
	
	{#if loading && !currentLogs}
		<div class="p-8 text-center text-gray-500">Loading logs...</div>
	{:else if !currentLogs}
		<div class="p-8 text-center text-gray-600">No logs available</div>
	{:else}
		<pre class="p-4 text-sm font-mono text-gray-300 overflow-auto max-h-[60vh] whitespace-pre-wrap leading-relaxed">{currentLogs}</pre>
	{/if}
</div>
