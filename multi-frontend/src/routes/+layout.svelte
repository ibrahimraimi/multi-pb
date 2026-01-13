<script lang="ts">
	import './layout.css';

	let { children } = $props();
</script>

<svelte:head>
	<title>Multi-PB</title>
	<meta name="description" content="Multi-tenant PocketBase Management Platform" />
</svelte:head>

<div class="min-h-screen bg-gray-900 text-gray-100">
	{@render children()}
</div>
