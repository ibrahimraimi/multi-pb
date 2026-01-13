import { writable } from 'svelte/store';

export const isSetupDone = writable(false);
export const isAuthenticated = writable(false);
export const domainName = writable('localhost.direct');
