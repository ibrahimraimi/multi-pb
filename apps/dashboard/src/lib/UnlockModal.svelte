<script lang="ts">
	import { setToken, needsAuthModal, API_BASE, checkAuthRequired } from './api';

	let token = '';
	let validating = false;
	let error = '';

	async function handleUnlock() {
		const t = token.trim();
		if (!t) {
			error = 'Enter the admin token from your Multi-PB config or MULTIPB_ADMIN_TOKEN.';
			return;
		}
		validating = true;
		error = '';
		try {
			const res = await fetch(API_BASE + '/stats', {
				headers: { Authorization: `Bearer ${t}` },
			});
			if (res.ok || res.status === 200) {
				setToken(t);
				needsAuthModal.set(false);
				token = '';
				// Re-check auth requirement to update UI state
				await checkAuthRequired();
			} else {
				const data = await res.json().catch(() => ({}));
				error = data.error || 'Invalid token';
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Request failed';
		} finally {
			validating = false;
		}
	}

	function handleClose() {
		// Only close if we're not in "required after 401" state – for now always allow close
		needsAuthModal.set(false);
		token = '';
		error = '';
	}
</script>

<!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
<div
	class="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-[100] p-4"
	on:click|self={handleClose}
	role="dialog"
	aria-modal="true"
	aria-labelledby="unlock-title"
>
	<div
		class="bg-[#111] rounded-2xl p-6 w-full max-w-md border border-gray-800 shadow-xl"
		on:click|stopPropagation
	>
		<h2 id="unlock-title" class="text-lg font-bold text-white mb-1">Admin token required</h2>
		<p class="text-sm text-gray-500 mb-4">
			This Multi-PB instance has API authorization enabled. Enter the admin token from
			<code class="text-gray-400 bg-gray-800 px-1 rounded">config.json</code> or
			<code class="text-gray-400 bg-gray-800 px-1 rounded">MULTIPB_ADMIN_TOKEN</code>.
		</p>
		<input
			type="password"
			bind:value={token}
			placeholder="Admin token"
			class="w-full bg-[#0a0a0a] border border-gray-800 rounded-lg px-4 py-3 text-white placeholder-gray-600 focus:outline-none focus:border-emerald-500/50 mb-4"
			on:keydown={(e) => e.key === 'Enter' && handleUnlock()}
			autocomplete="current-password"
		/>
		{#if error}
			<p class="text-sm text-red-400 mb-4">{error}</p>
		{/if}
		<div class="flex gap-3">
			<button
				type="button"
				on:click={handleClose}
				class="flex-1 px-4 py-2.5 border border-gray-700 rounded-lg font-medium text-gray-400 hover:bg-gray-800/50 transition-all text-sm"
			>
				Cancel
			</button>
			<button
				type="button"
				on:click={handleUnlock}
				disabled={validating || !token.trim()}
				class="flex-1 px-4 py-2.5 bg-emerald-500 hover:bg-emerald-600 disabled:opacity-50 disabled:cursor-not-allowed text-black rounded-lg font-semibold transition-all text-sm"
			>
				{validating ? 'Checking…' : 'Unlock'}
			</button>
		</div>
	</div>
</div>
