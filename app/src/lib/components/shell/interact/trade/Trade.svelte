<script lang="ts">
	let swapIconTurns = $state(0);

	function handleSwapTokens() {
		swapIconTurns += 1;
		// TODO: swap tokenIn / tokenOut (and amounts) when selectors are wired
	}
</script>

<div class="trade">
	<div class="trade-header">
		<div class="trade-header-left">
			<div class="trade-header-left-item one">
				<p class="trade-header-label">Market</p>
			</div>
			<div class="trade-header-left-item two">
				<p class="trade-header-label">Advanced</p>
			</div>
		</div>
		<div class="trade-header-right">
			<div class="trade-header-right-item">
				<p class="trade-header-label"></p>
			</div>
		</div>
	</div>

	<div class="trade-body">
		<div class="input-output input"></div>
		<div class="input-output-separator">
			<button
				type="button"
				class="swap-icon"
				aria-label="Swap input and output tokens"
				onclick={handleSwapTokens}
			>
				<i
					class="fa-solid fa-arrow-down swap-icon-button"
					aria-hidden="true"
					style="transform: rotate({swapIconTurns * 180}deg)"
				></i>
			</button>
		</div>
		<div class="input-output output"></div>
	</div>

	<div class="trade-footer">
		<button type="button" class="swap-button">
			Swap
		</button>
		<div class="swap-info">
			<p class="swap-info-label"></p>
		</div>
	</div>
</div>

<style>
	.trade {
		height: 616px;
		width: 100%;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	.trade-header {
		width: 100%;
		height: 60px;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: space-between;
	}

	.trade-header-left {
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-start;
		padding: 0 10px;
		gap: 10px;
	}

	.trade-header-left-item {
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: center;
		gap: 10px;
		padding: 0 20px 0 10px;
	}

	.trade-header-left-item.one {
		border-right: 1px solid var(--color-border);
	}

	.trade-header-right {
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-end;
		padding: 0 20px;
		gap: 10px;
	}

	.trade-body {
		width: 100%;
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
		min-height: 0;
	}

	.input-output {
		width: 100%;
		flex: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	.input-output-separator {
		flex-shrink: 0;
		position: relative;
		width: 100%;
		height: 1px;
		background-color: var(--color-border);
	}

	.swap-icon {
		all: unset;
		position: absolute;
		left: 50%;
		top: 50%;
		z-index: 1;
		transform: translate(-50%, -50%);
		min-width: 40px;
		height: 30px;
		padding: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		box-sizing: border-box;
		border: 1px solid var(--color-border);
		border-radius: 2px;
		background-color: var(--color-surface-muted);
		color: var(--color-text-muted);
		cursor: pointer;
		transition:
			background-color 0.15s ease,
			color 0.15s ease;
	}

	.swap-icon:hover {
		background-color: var(--color-surface-elevated);
		color: var(--color-text);
	}

	.swap-icon:active {
		background-color: var(--color-border);
	}

	.swap-icon-button {
		font-size: 8px;
		line-height: 1;
		transition: transform 0.2s ease;
	}

	.trade-footer {
		width: 100%;
		height: 100px;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 10px;
		padding: 0 20px;
	}

	.swap-button {
		all: unset;
		background: linear-gradient(to right, var(--color-primary-light) -20%, var(--color-primary) 100%);
		width: 100%;
		height: 40px;
		border-radius: 5px;
		box-sizing: border-box;
		padding: 0 20px;
		color: var(--color-text-inverse);
		font-size: var(--text-sm);
		font-weight: 400;
		letter-spacing: 1px;
		cursor: pointer;
		transition: all var(--transition-base);
		display: flex;
		align-items: center;
		justify-content: center;
		opacity: 0.5;
		cursor: default;
	}

	.swap-info {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		box-sizing: border-box;
		padding: 0 20px;
		width: 100%;
		height: 30px;
		background-color: #202020;
		border-radius: 5px;
		margin-bottom: 10px;
	}
</style>
