<script lang="ts">
	import { goto } from '$app/navigation';
	import { api } from '$lib/api';

	let step = $state(1);
	let email = $state('');
	let password = $state('');
	let confirmPassword = $state('');
	let loading = $state(false);
	let error = $state('');

	async function handleSetup() {
		error = '';

		if (!email || !password) {
			error = 'Email and password are required';
			return;
		}

		if (password !== confirmPassword) {
			error = 'Passwords do not match';
			return;
		}

		if (password.length < 8) {
			error = 'Password must be at least 8 characters';
			return;
		}

		loading = true;
		try {
			const res = await api.setup(email, password);
			if (res.success) {
				step = 2;
				setTimeout(() => goto('/dashboard'), 2000);
			} else {
				error = res.error || 'Setup failed';
			}
		} catch (e) {
			error = String(e);
		} finally {
			loading = false;
		}
	}
</script>

<div class="flex min-h-screen items-center justify-center p-4">
	<div class="w-full max-w-md">
		<!-- Logo/Header -->
		<div class="mb-8 text-center">
			<div class="mb-4 inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-blue-600">
				<svg class="h-8 w-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
					<path
						stroke-linecap="round"
						stroke-linejoin="round"
						stroke-width="2"
						d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2"
					></path>
				</svg>
			</div>
			<h1 class="text-2xl font-bold">Multi-PB</h1>
			<p class="text-gray-400">Multi-tenant PocketBase Platform</p>
		</div>

		{#if step === 1}
			<!-- Setup Form -->
			<div class="rounded-xl bg-gray-800 p-6 shadow-xl">
				<h2 class="mb-6 text-xl font-semibold">Create Admin Account</h2>

				<form onsubmit={(e) => { e.preventDefault(); handleSetup(); }}>
					<div class="mb-4">
						<label for="email" class="mb-1 block text-sm text-gray-400">Email</label>
						<input
							id="email"
							type="email"
							bind:value={email}
							class="w-full rounded-lg border border-gray-700 bg-gray-900 px-4 py-2 focus:border-blue-500 focus:outline-none"
							placeholder="admin@example.com"
							required
						/>
					</div>

					<div class="mb-4">
						<label for="password" class="mb-1 block text-sm text-gray-400">Password</label>
						<input
							id="password"
							type="password"
							bind:value={password}
							class="w-full rounded-lg border border-gray-700 bg-gray-900 px-4 py-2 focus:border-blue-500 focus:outline-none"
							placeholder="Minimum 8 characters"
							required
						/>
					</div>

					<div class="mb-6">
						<label for="confirmPassword" class="mb-1 block text-sm text-gray-400"
							>Confirm Password</label
						>
						<input
							id="confirmPassword"
							type="password"
							bind:value={confirmPassword}
							class="w-full rounded-lg border border-gray-700 bg-gray-900 px-4 py-2 focus:border-blue-500 focus:outline-none"
							placeholder="Confirm your password"
							required
						/>
					</div>

					{#if error}
						<div class="mb-4 rounded-lg bg-red-900/50 p-3 text-sm text-red-400">
							{error}
						</div>
					{/if}

					<button
						type="submit"
						disabled={loading}
						class="w-full rounded-lg bg-blue-600 py-3 font-medium transition hover:bg-blue-700 disabled:opacity-50"
					>
						{loading ? 'Setting up...' : 'Complete Setup'}
					</button>
				</form>
			</div>
		{:else}
			<!-- Success -->
			<div class="rounded-xl bg-gray-800 p-6 text-center shadow-xl">
				<div
					class="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-green-600"
				>
					<svg class="h-8 w-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"
						></path>
					</svg>
				</div>
				<h2 class="mb-2 text-xl font-semibold">Setup Complete!</h2>
				<p class="text-gray-400">Redirecting to dashboard...</p>
			</div>
		{/if}
	</div>
</div>
