<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type Tenant, type TenantStatus } from '$lib/api';

	let tenants = $state<Tenant[]>([]);
	let statuses = $state<Map<string, TenantStatus>>(new Map());
	let loading = $state(true);
	let error = $state('');

	// Create tenant modal
	let showCreateModal = $state(false);
	let newName = $state('');
	let newSubdomain = $state('');
	let creating = $state(false);
	let createError = $state('');

	// Delete confirmation
	let deleteId = $state<string | null>(null);
	let deleteData = $state(false);
	let deleting = $state(false);

	async function loadTenants() {
		try {
			const res = await api.getTenants();
			if (res.success && res.data) {
				tenants = res.data.tenants || [];
				statuses = new Map(res.data.statuses?.map((s) => [s.id, s]) || []);
			}
		} catch (e) {
			error = String(e);
		} finally {
			loading = false;
		}
	}

	async function createTenant() {
		createError = '';
		if (!newSubdomain) {
			createError = 'Subdomain is required';
			return;
		}

		creating = true;
		try {
			const res = await api.createTenant(newName || newSubdomain, newSubdomain);
			if (res.success) {
				showCreateModal = false;
				newName = '';
				newSubdomain = '';
				await loadTenants();
			} else {
				createError = res.error || 'Failed to create tenant';
			}
		} catch (e) {
			createError = String(e);
		} finally {
			creating = false;
		}
	}

	async function deleteTenant() {
		if (!deleteId) return;

		deleting = true;
		try {
			const res = await api.deleteTenant(deleteId, deleteData);
			if (res.success) {
				deleteId = null;
				deleteData = false;
				await loadTenants();
			} else {
				error = res.error || 'Failed to delete tenant';
			}
		} catch (e) {
			error = String(e);
		} finally {
			deleting = false;
		}
	}

	async function restartTenant(id: string) {
		const res = await api.restartTenant(id);
		if (res.success) {
			await loadTenants();
		}
	}

	function formatUptime(seconds?: number): string {
		if (!seconds) return '-';
		if (seconds < 60) return `${seconds}s`;
		if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
		if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
		return `${Math.floor(seconds / 86400)}d`;
	}

	onMount(() => {
		loadTenants();
		// Refresh every 10 seconds
		const interval = setInterval(loadTenants, 10000);
		return () => clearInterval(interval);
	});
</script>

<div class="min-h-screen">
	<!-- Header -->
	<header class="border-b border-gray-800 bg-gray-900/50 backdrop-blur">
		<div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
			<div class="flex items-center gap-3">
				<div class="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-600">
					<svg class="h-5 w-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2"
						></path>
					</svg>
				</div>
				<div>
					<h1 class="font-semibold">Multi-PB</h1>
					<p class="text-xs text-gray-400">{tenants.length} instance{tenants.length !== 1 ? 's' : ''}</p>
				</div>
			</div>

			<button
				onclick={() => (showCreateModal = true)}
				class="flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 font-medium transition hover:bg-blue-700"
			>
				<svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"
					></path>
				</svg>
				New Instance
			</button>
		</div>
	</header>

	<!-- Main Content -->
	<main class="mx-auto max-w-6xl p-4">
		{#if loading}
			<div class="py-20 text-center">
				<div
					class="inline-block h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent"
				></div>
			</div>
		{:else if tenants.length === 0}
			<!-- Empty State -->
			<div class="py-20 text-center">
				<div
					class="mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-full bg-gray-800"
				>
					<svg class="h-10 w-10 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"
						></path>
					</svg>
				</div>
				<h2 class="mb-2 text-xl font-semibold">No instances yet</h2>
				<p class="mb-6 text-gray-400">Create your first PocketBase instance to get started</p>
				<button
					onclick={() => (showCreateModal = true)}
					class="rounded-lg bg-blue-600 px-6 py-3 font-medium transition hover:bg-blue-700"
				>
					Create Instance
				</button>
			</div>
		{:else}
			<!-- Tenant Grid -->
			<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
				{#each tenants as tenant (tenant.id)}
					{@const status = statuses.get(tenant.id)}
					<div class="rounded-xl border border-gray-800 bg-gray-800/50 p-4">
						<div class="mb-3 flex items-start justify-between">
							<div>
								<h3 class="font-semibold">{tenant.name}</h3>
								<p class="text-sm text-gray-400">{tenant.subdomain}</p>
							</div>
							<span
								class="rounded-full px-2 py-1 text-xs font-medium {tenant.status === 'running'
									? 'bg-green-900/50 text-green-400'
									: tenant.status === 'error'
										? 'bg-red-900/50 text-red-400'
										: 'bg-gray-700 text-gray-400'}"
							>
								{tenant.status}
							</span>
						</div>

						<div class="mb-4 text-sm text-gray-400">
							<div class="flex justify-between">
								<span>Uptime</span>
								<span>{formatUptime(status?.uptime_seconds)}</span>
							</div>
							<div class="flex justify-between">
								<span>Port</span>
								<span>{tenant.port}</span>
							</div>
						</div>

						<div class="flex gap-2">
							<a
								href={status?.admin_url || '#'}
								target="_blank"
								rel="noopener noreferrer"
								class="flex-1 rounded-lg bg-gray-700 py-2 text-center text-sm transition hover:bg-gray-600"
							>
								Open Admin
							</a>
							<button
								onclick={() => restartTenant(tenant.id)}
								class="rounded-lg bg-gray-700 px-3 py-2 transition hover:bg-gray-600"
								title="Restart"
							>
								<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
									<path
										stroke-linecap="round"
										stroke-linejoin="round"
										stroke-width="2"
										d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
									></path>
								</svg>
							</button>
							<button
								onclick={() => (deleteId = tenant.id)}
								class="rounded-lg bg-red-900/30 px-3 py-2 text-red-400 transition hover:bg-red-900/50"
								title="Delete"
							>
								<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
									<path
										stroke-linecap="round"
										stroke-linejoin="round"
										stroke-width="2"
										d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
									></path>
								</svg>
							</button>
						</div>
					</div>
				{/each}
			</div>
		{/if}
	</main>
</div>

<!-- Create Modal -->
{#if showCreateModal}
	<div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
		<div class="w-full max-w-md rounded-xl bg-gray-800 p-6">
			<h2 class="mb-4 text-xl font-semibold">Create Instance</h2>

			<form onsubmit={(e) => { e.preventDefault(); createTenant(); }}>
				<div class="mb-4">
					<label for="subdomain" class="mb-1 block text-sm text-gray-400">Subdomain</label>
					<input
						id="subdomain"
						type="text"
						bind:value={newSubdomain}
						class="w-full rounded-lg border border-gray-700 bg-gray-900 px-4 py-2 focus:border-blue-500 focus:outline-none"
						placeholder="my-app"
						pattern="[a-z0-9-]+"
						required
					/>
					<p class="mt-1 text-xs text-gray-500">Lowercase letters, numbers, and dashes only</p>
				</div>

				<div class="mb-6">
					<label for="name" class="mb-1 block text-sm text-gray-400">Display Name (optional)</label>
					<input
						id="name"
						type="text"
						bind:value={newName}
						class="w-full rounded-lg border border-gray-700 bg-gray-900 px-4 py-2 focus:border-blue-500 focus:outline-none"
						placeholder="My App"
					/>
				</div>

				{#if createError}
					<div class="mb-4 rounded-lg bg-red-900/50 p-3 text-sm text-red-400">
						{createError}
					</div>
				{/if}

				<div class="flex gap-3">
					<button
						type="button"
						onclick={() => (showCreateModal = false)}
						class="flex-1 rounded-lg bg-gray-700 py-2 transition hover:bg-gray-600"
					>
						Cancel
					</button>
					<button
						type="submit"
						disabled={creating}
						class="flex-1 rounded-lg bg-blue-600 py-2 transition hover:bg-blue-700 disabled:opacity-50"
					>
						{creating ? 'Creating...' : 'Create'}
					</button>
				</div>
			</form>
		</div>
	</div>
{/if}

<!-- Delete Confirmation Modal -->
{#if deleteId}
	<div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
		<div class="w-full max-w-md rounded-xl bg-gray-800 p-6">
			<h2 class="mb-2 text-xl font-semibold text-red-400">Delete Instance</h2>
			<p class="mb-4 text-gray-400">Are you sure you want to delete this instance?</p>

			<label class="mb-6 flex items-center gap-2">
				<input type="checkbox" bind:checked={deleteData} class="h-4 w-4 rounded" />
				<span class="text-sm">Also delete all data</span>
			</label>

			<div class="flex gap-3">
				<button
					onclick={() => (deleteId = null)}
					class="flex-1 rounded-lg bg-gray-700 py-2 transition hover:bg-gray-600"
				>
					Cancel
				</button>
				<button
					onclick={deleteTenant}
					disabled={deleting}
					class="flex-1 rounded-lg bg-red-600 py-2 transition hover:bg-red-700 disabled:opacity-50"
				>
					{deleting ? 'Deleting...' : 'Delete'}
				</button>
			</div>
		</div>
	</div>
{/if}
