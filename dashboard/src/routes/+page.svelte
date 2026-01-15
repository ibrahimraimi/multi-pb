<script>
	import { onMount } from 'svelte';
	
	let instances = [];
	let loading = true;
	let error = null;
	let showAddModal = false;
	let newInstanceName = '';
	let creating = false;

	const API_BASE = '/api';

	async function fetchInstances() {
		try {
			loading = true;
			const res = await fetch(`${API_BASE}/instances`);
			if (!res.ok) throw new Error('Failed to fetch instances');
			const data = await res.json();
			instances = data.instances || [];
			error = null;
		} catch (e) {
			error = e.message;
			console.error('Error fetching instances:', e);
		} finally {
			loading = false;
		}
	}

	async function addInstance() {
		if (!newInstanceName.trim()) return;
		
		creating = true;
		try {
			const res = await fetch(`${API_BASE}/instances`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ name: newInstanceName.trim() })
			});
			
			if (!res.ok) {
				const err = await res.json();
				throw new Error(err.error || 'Failed to create instance');
			}
			
			showAddModal = false;
			newInstanceName = '';
			await fetchInstances();
		} catch (e) {
			error = e.message;
		} finally {
			creating = false;
		}
	}

	async function removeInstance(name) {
		if (!confirm(`Delete instance "${name}"?`)) return;
		
		try {
			const res = await fetch(`${API_BASE}/instances/${name}`, {
				method: 'DELETE'
			});
			
			if (!res.ok) throw new Error('Failed to delete instance');
			await fetchInstances();
		} catch (e) {
			error = e.message;
		}
	}

	async function toggleInstance(name, action) {
		try {
			const res = await fetch(`${API_BASE}/instances/${name}/${action}`, {
				method: 'POST'
			});
			
			if (!res.ok) throw new Error(`Failed to ${action} instance`);
			await fetchInstances();
		} catch (e) {
			error = e.message;
		}
	}

	onMount(() => {
		fetchInstances();
		const interval = setInterval(fetchInstances, 5000);
		return () => clearInterval(interval);
	});
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-3xl font-bold text-gray-900">Multi-PB Dashboard</h1>
			<p class="text-gray-600 mt-1">Manage your PocketBase instances</p>
		</div>
		<button
			on:click={() => showAddModal = true}
			class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition"
		>
			+ Add Instance
		</button>
	</div>

	{#if error}
		<div class="bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded-lg mb-4">
			{error}
		</div>
	{/if}

	{#if loading && instances.length === 0}
		<div class="text-center py-12">
			<div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
			<p class="mt-4 text-gray-600">Loading instances...</p>
		</div>
	{:else if instances.length === 0}
		<div class="bg-white rounded-lg shadow p-12 text-center">
			<p class="text-gray-600 mb-4">No instances yet. Create your first one!</p>
			<button
				on:click={() => showAddModal = true}
				class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium"
			>
				Create Instance
			</button>
		</div>
	{:else}
		<div class="grid gap-4">
			{#each instances as instance}
				<div class="bg-white rounded-lg shadow p-6">
					<div class="flex items-center justify-between">
						<div class="flex-1">
							<div class="flex items-center gap-3 mb-2">
								<h2 class="text-xl font-semibold">{instance.name}</h2>
								<span class="px-2 py-1 text-xs rounded-full {instance.status === 'running' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'}">
									{instance.status}
								</span>
							</div>
							<div class="text-sm text-gray-600 space-y-1">
								<p>Port: {instance.port}</p>
								<p>Created: {new Date(instance.created).toLocaleString()}</p>
								<a
									href="/{instance.name}/_/"
									target="_blank"
									class="text-blue-600 hover:underline inline-block mt-2"
									rel="noopener noreferrer"
								>
									Open PocketBase →
								</a>
							</div>
						</div>
						<div class="flex gap-2">
							{#if instance.status === 'running'}
								<button
									on:click={() => toggleInstance(instance.name, 'stop')}
									class="px-4 py-2 bg-yellow-600 hover:bg-yellow-700 text-white rounded-lg text-sm font-medium"
								>
									Stop
								</button>
							{:else}
								<button
									on:click={() => toggleInstance(instance.name, 'start')}
									class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-medium"
								>
									Start
								</button>
							{/if}
							<a
								href="/dashboard/{instance.name}/logs"
								class="px-4 py-2 bg-gray-600 hover:bg-gray-700 text-white rounded-lg text-sm font-medium inline-block"
							>
								Logs
							</a>
							<button
								on:click={() => removeInstance(instance.name)}
								class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-medium"
							>
								Delete
							</button>
						</div>
					</div>
				</div>
			{/each}
		</div>
	{/if}
</div>

{#if showAddModal}
	<div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
		<div class="bg-white rounded-lg p-6 w-full max-w-md">
			<h2 class="text-xl font-semibold mb-4">Create New Instance</h2>
			<input
				type="text"
				bind:value={newInstanceName}
				placeholder="Instance name"
				class="w-full px-4 py-2 border border-gray-300 rounded-lg mb-4"
				on:keydown={(e) => e.key === 'Enter' && addInstance()}
			/>
			<div class="flex gap-2 justify-end">
				<button
					on:click={() => { showAddModal = false; newInstanceName = ''; }}
					class="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
					disabled={creating}
				>
					Cancel
				</button>
				<button
					on:click={addInstance}
					class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg"
					disabled={creating || !newInstanceName.trim()}
				>
					{creating ? 'Creating...' : 'Create'}
				</button>
			</div>
		</div>
	</div>
{/if}
