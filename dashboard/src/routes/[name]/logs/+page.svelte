<script>
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	
	let logs = '';
	let loading = true;
	let error = null;
	let autoRefresh = true;

	const instanceName = $page.params.name;
	const API_BASE = '/api';

	async function fetchLogs() {
		try {
			loading = true;
			const res = await fetch(`${API_BASE}/instances/${instanceName}/logs`);
			if (!res.ok) throw new Error('Failed to fetch logs');
			const data = await res.json();
			logs = data.logs || '';
			error = null;
		} catch (e) {
			error = e.message;
			console.error('Error fetching logs:', e);
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		fetchLogs();
		const interval = setInterval(() => {
			if (autoRefresh) fetchLogs();
		}, 2000);
		return () => clearInterval(interval);
	});
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<a href="/dashboard" class="text-blue-600 hover:underline mb-2 inline-block">← Back to instances</a>
			<h1 class="text-3xl font-bold text-gray-900">Logs: {instanceName}</h1>
		</div>
		<label class="flex items-center gap-2">
			<input type="checkbox" bind:checked={autoRefresh} class="rounded" />
			<span class="text-sm text-gray-600">Auto-refresh</span>
		</label>
	</div>

	{#if error}
		<div class="bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded-lg mb-4">
			{error}
		</div>
	{/if}

	<div class="bg-gray-900 text-gray-100 rounded-lg p-4 font-mono text-sm overflow-auto max-h-[80vh]">
		{#if loading && !logs}
			<div class="text-center py-8">Loading logs...</div>
		{:else if !logs}
			<div class="text-gray-500">No logs available</div>
		{:else}
			<pre class="whitespace-pre-wrap">{logs}</pre>
		{/if}
	</div>
</div>
