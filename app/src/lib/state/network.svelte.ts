/**
 * Shared selected-network state.
 *
 * The header's network selector reads/writes here, but the value is intended
 * to be the single source of truth for any future code that needs to know
 * which Base chain the UI is operating on (RPC provider, contract addresses,
 * Coinbase Smart Account configuration, etc.). Kept deliberately tiny so it
 * can be imported anywhere without pulling in viem/wagmi.
 *
 * `id` mirrors the canonical viem chain key (`base`, `baseSepolia` becomes
 * `base-sepolia` here only because we use it as a CSS-friendly slug). When
 * the selector is wired up to a real chain client, map `id` → viem chain at
 * the boundary rather than changing this enum.
 */

export type NetworkId = 'base' | 'base-sepolia';

export type Network = {
	id: NetworkId;
	name: string;
	iconSrc: string;
	iconAlt: string;
};

export const NETWORKS: readonly Network[] = [
	{
		id: 'base',
		name: 'Base',
		iconSrc: '/brand/base-square-blue.svg',
		iconAlt: 'Base mainnet'
	},
	{
		id: 'base-sepolia',
		name: 'Sepolia',
		iconSrc: '/brand/base-square-white.svg',
		iconAlt: 'Base Sepolia testnet'
	}
] as const;

let _id = $state<NetworkId>('base');

export const network = {
	get id() {
		return _id;
	},
	get current(): Network {
		return NETWORKS.find((n) => n.id === _id) ?? NETWORKS[0];
	},
	get networks() {
		return NETWORKS;
	},
	select(id: NetworkId) {
		_id = id;
	}
};
