<script lang="ts">
	import { onDestroy, tick } from 'svelte';
	import { signup } from '$lib/state/signup.svelte';
	import { auth } from '$lib/state/auth.svelte';
	import { account } from '$lib/state/account.svelte';
	import { truncateAddress } from '$lib/utils/address';
	import { scrollLock } from '$lib/utils/scrollLock';

	type Stage = 'email' | 'otp' | 'success';

	const OTP_LENGTH = 6;
	const RESEND_COOLDOWN_SECONDS = 20;

	let dialogEl = $state<HTMLDialogElement | undefined>();
	let stage = $state<Stage>('email');
	let email = $state('');
	/* `otpDigits` is the source of truth. We hold an array (not a joined
	   string) because deletion in the middle creates sparse holes that a
	   left-trimmed string can't represent. `otpString` and `otpComplete`
	   derive what the rest of the flow needs. */
	let otpDigits = $state<string[]>(Array(OTP_LENGTH).fill(''));
	const otpString = $derived(otpDigits.join(''));
	const otpComplete = $derived(otpDigits.every((d) => d !== ''));
	/* Plain `let` (not `$state`) because we only read refs inside event
	   handlers; reactivity here would just cost unnecessary re-renders. */
	let otpInputs: HTMLInputElement[] = [];
	let loading = $state(false);
	let error = $state<string | null>(null);
	let eoaAddress = $state('');
	let smartWalletAddress = $state('');
	/* Set from the /init response — drives whether the account sidebar
	   auto-opens after the user hits "Enter app". Defaults to `true` in
	   the mocked flow because we can't actually distinguish; the real
	   value comes from Turnkey via getSubOrgIds (no existing sub-org
	   for the email = new user). */
	let isNewUser = $state(true);
	/* Seconds remaining before the user can hit Resend again. 0 means
	   "available". Reactive so the button label can re-render every tick. */
	let resendCooldown = $state(0);
	/* Plain `let` — only the script reads/writes it, no template reactivity
	   needed. Holds the setInterval handle so we can clear it. */
	let resendTimer: ReturnType<typeof setInterval> | null = null;

	/* Sync the external `signup` store with the imperative <dialog> API.
	   showModal() / close() must be called as methods; we guard against
	   redundant calls so esc-to-close (which fires `close` -> store.close
	   -> this effect) doesn't re-enter showModal on an already-open dialog.

	   Scroll lock is acquired while the modal is open and released when
	   it closes (or when the component unmounts) via the cleanup return. */
	$effect(() => {
		const el = dialogEl;
		if (!el) return;
		if (signup.isOpen) {
			if (!el.open) {
				reset();
				el.showModal();
			}
			scrollLock.acquire();
			return () => scrollLock.release();
		} else if (el.open) {
			el.close();
		}
	});

	function reset() {
		stage = 'email';
		email = '';
		otpDigits = Array(OTP_LENGTH).fill('');
		loading = false;
		error = null;
		eoaAddress = '';
		smartWalletAddress = '';
		isNewUser = true;
		stopResendCooldown();
	}

	/* Closes the modal and — only for first-time signups — opens the
	   account sidebar so new users land on the surface where their
	   wallet details, balance, and settings live. Returning users go
	   straight back to whatever they were doing. */
	function enterApp() {
		close();
		if (isNewUser) account.open();
	}

	function startResendCooldown() {
		stopResendCooldown();
		resendCooldown = RESEND_COOLDOWN_SECONDS;
		resendTimer = setInterval(() => {
			resendCooldown -= 1;
			if (resendCooldown <= 0) stopResendCooldown();
		}, 1000);
	}

	function stopResendCooldown() {
		if (resendTimer !== null) {
			clearInterval(resendTimer);
			resendTimer = null;
		}
		resendCooldown = 0;
	}

	/* Defensive cleanup. SignupModal lives at the layout root and never
	   actually unmounts in practice, but if it ever did we'd otherwise
	   leak the setInterval handle. */
	onDestroy(stopResendCooldown);

	function close() {
		signup.close();
	}

	function isValidEmail(value: string): boolean {
		return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
	}

	async function submitEmail(e: SubmitEvent) {
		e.preventDefault();
		if (!isValidEmail(email)) {
			error = 'Please enter a valid email address';
			return;
		}
		error = null;
		loading = true;
		try {
			/* TODO(turnkey): POST /api/auth/turnkey/init { email }
			   Server-side, the parent-org client:
			     1. getSubOrgIds({ filterType: 'EMAIL', filterValue: email })
			        – returns existing sub-org id if the user has signed up before,
			          otherwise empty -> createSubOrganization with the email
			          registered and a fresh secp256k1 wallet for the owner EOA.
			     2. initOtp({ otpType: 'OTP_TYPE_EMAIL', contact: email,
			                  appName: 'HighPotential', alphanumeric: false,
			                  otpLength: 6 })
			   Response: { otpId, otpEncryptionTargetBundle, subOrgId, isNewUser }.
			   Keep otpId + targetBundle + subOrgId in component state for /verify. */
			await mockDelay(700);
			stage = 'otp';
			/* Start cooldown immediately — a fresh code was just sent by
			   /init, so the user shouldn't be able to spam Resend straight
			   away. Restarted on every successful resend() too. */
			startResendCooldown();
			/* tick() so the OTP stage has rendered and bind:this populated
			   `otpInputs[0]` before we try to focus it. */
			await tick();
			focusBox(0);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Failed to send code';
		} finally {
			loading = false;
		}
	}

	async function submitOtp(e: SubmitEvent) {
		e.preventDefault();
		if (!otpComplete) {
			error = 'Enter all 6 digits of the code';
			return;
		}
		error = null;
		loading = true;
		try {
			/* TODO(turnkey): POST /api/auth/turnkey/verify
			       { otpId, encryptedOtpBundle, subOrgId, clientPubKey }
			   Server-side:
			     1. verifyOtp({ otpId, encryptedOtpBundle }) -> verificationToken
			     2. otpLogin({ publicKey, verificationToken, clientSignature })
			        against the sub-org -> session credential bundle.
			     3. getWalletAccounts({ walletId }) -> owner EOA address.
			   Response: { session, ownerEoa }.
			   Then the client computes the counterfactual smart wallet address
			   locally via viem + HPSmartWalletFactory.getAddress(owners, salt)
			   once the factory is deployed. */
			await mockDelay(700);
			// Sandbox accepts '000000' when alphanumeric=false, otpLength=6.
			if (otpString !== '000000') throw new Error('Incorrect code, try again');
			eoaAddress = '0xA0Cf798816D4b9b9866b5330EEa46a18382f251e';
			smartWalletAddress = '0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97';
			/* TODO(turnkey): set `isNewUser` from /init response. In the
			   mocked flow it stays at its initialised value (true). */
			auth.signIn({
				email,
				ownerEoa: eoaAddress as `0x${string}`,
				smartWallet: smartWalletAddress as `0x${string}`
			});
			stage = 'success';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Verification failed';
		} finally {
			loading = false;
		}
	}

	async function resend() {
		if (loading || resendCooldown > 0) return;
		loading = true;
		error = null;
		try {
			// TODO(turnkey): re-POST /api/auth/turnkey/init with the same email.
			await mockDelay(400);
			startResendCooldown();
		} finally {
			loading = false;
		}
	}

	function back() {
		stage = 'email';
		otpDigits = Array(OTP_LENGTH).fill('');
		error = null;
	}

	/* Backdrop click closes the modal. Because the <dialog> uses
	   padding: 0, its bounding box IS the content box — clicks outside the
	   visible card hit the ::backdrop pseudo-element which bubbles to the
	   dialog with `target === dialogEl`. Clicks inside hit their own target. */
	function onDialogClick(e: MouseEvent) {
		if (e.target === dialogEl) close();
	}

	function setDigit(index: number, value: string) {
		otpDigits = otpDigits.map((d, i) => (i === index ? value : d));
	}

	function focusBox(index: number) {
		const i = Math.max(0, Math.min(OTP_LENGTH - 1, index));
		const el = otpInputs[i];
		if (!el) return;
		el.focus();
		el.select();
	}

	function onBoxInput(index: number, e: Event) {
		const target = e.target as HTMLInputElement;
		/* Take only the last typed digit so overwriting a filled box
		   (which would briefly contain two chars before maxlength kicks
		   in on some browsers) cleanly replaces rather than appends. */
		const digit = target.value.replace(/\D/g, '').slice(-1);
		setDigit(index, digit);
		target.value = digit;
		if (digit && index < OTP_LENGTH - 1) focusBox(index + 1);
	}

	function onBoxKeydown(index: number, e: KeyboardEvent) {
		if (e.key === 'Backspace') {
			/* On an empty box, backspace hops to and clears the previous
			   box — the canonical 2FA-input behavior. On a filled box,
			   we let the native handler clear the current digit. */
			if (otpDigits[index] === '' && index > 0) {
				e.preventDefault();
				setDigit(index - 1, '');
				focusBox(index - 1);
			}
		} else if (e.key === 'ArrowLeft' && index > 0) {
			e.preventDefault();
			focusBox(index - 1);
		} else if (e.key === 'ArrowRight' && index < OTP_LENGTH - 1) {
			e.preventDefault();
			focusBox(index + 1);
		}
	}

	function onBoxPaste(index: number, e: ClipboardEvent) {
		const text = e.clipboardData?.getData('text') ?? '';
		const digits = text.replace(/\D/g, '');
		if (!digits) return;
		e.preventDefault();
		const next = [...otpDigits];
		const capacity = OTP_LENGTH - index;
		const slice = digits.slice(0, capacity);
		for (let i = 0; i < slice.length; i++) {
			next[index + i] = slice[i];
		}
		otpDigits = next;
		focusBox(Math.min(index + slice.length, OTP_LENGTH - 1));
	}

	function mockDelay(ms: number): Promise<void> {
		return new Promise((r) => setTimeout(r, ms));
	}
</script>

<dialog
	bind:this={dialogEl}
	class="modal"
	aria-labelledby="signup-title"
	onclose={() => signup.close()}
	onclick={onDialogClick}
>
	<div class="content">
		<header class="modalHeader">
			<span class="brand">
				<img src="/brand/icon-dark.svg" alt="" class="brandIcon" />
				<span class="brandName">Signup / Register</span>
			</span>
			<button type="button" class="closeButton" aria-label="Close" onclick={close}>
				<i class="fa-solid fa-xmark" aria-hidden="true"></i>
			</button>
		</header>

		{#if stage === 'email'}
			<p id="signup-title" class="subtitle">Enter your email to receive a one-time code.</p>
			<form class="form" onsubmit={submitEmail} autocomplete="off" novalidate>
				<label class="field">
					<span class="label-eyebrow">Email</span>
					<input
						type="email"
						inputmode="email"
						autocomplete="off"
						spellcheck="false"
						placeholder="you@example.com"
						bind:value={email}
						disabled={loading}
					/>
				</label>
				{#if error}<p class="error">{error}</p>{/if}
				<button type="submit" class="primary" disabled={loading || !email}>
					{loading ? 'Sending…' : 'Continue'}
				</button>
			</form>
		{:else if stage === 'otp'}
			<p class="subtitle">
				We sent a 6-digit code to your email address <span class="emphasis">{email}</span>.
			</p>
			<form class="form" onsubmit={submitOtp} novalidate>
				<div class="field">
					<span class="label-eyebrow">Code</span>
					<div class="otpBoxes" role="group" aria-label="One-time code">
						{#each otpDigits as digit, i (i)}
							<input
								bind:this={otpInputs[i]}
								type="text"
								inputmode="numeric"
								autocomplete={i === 0 ? 'one-time-code' : 'off'}
								maxlength="1"
								value={digit}
								oninput={(e) => onBoxInput(i, e)}
								onkeydown={(e) => onBoxKeydown(i, e)}
								onpaste={(e) => onBoxPaste(i, e)}
								disabled={loading}
								class="otpBox"
								aria-label={`Digit ${i + 1} of ${OTP_LENGTH}`}
							/>
						{/each}
					</div>
				</div>
				{#if error}<p class="error">{error}</p>{/if}
				<button type="submit" class="primary" disabled={loading || !otpComplete}>
					{loading ? 'Verifying…' : 'Verify'}
				</button>
				<div class="links">
					<button type="button" class="backLink" onclick={back} disabled={loading}>
						← Use a different email
					</button>
					<button
						type="button"
						class="resendLink"
						onclick={resend}
						disabled={loading || resendCooldown > 0}
					>
						{resendCooldown > 0 ? `Resend in ${resendCooldown}s` : 'Resend code'}
					</button>
				</div>
			</form>
		{:else}
			<p class="subtitle">Your HP Smart Wallet is ready.</p>
			<div class="walletCard">
				<div class="walletRow">
					<span class="label-eyebrow">Owner EOA</span>
					<code class="addr">{truncateAddress(eoaAddress)}</code>
				</div>
				<div class="walletRow">
					<span class="label-eyebrow">Smart Wallet</span>
					<code class="addr">{truncateAddress(smartWalletAddress)}</code>
				</div>
			</div>
			<button type="button" class="primary" onclick={enterApp}>Enter app</button>
		{/if}
	</div>
</dialog>

<style>
	.modal {
		width: 380px;
		max-width: calc(100vw - 32px);
		padding: 0;
		margin: auto;
		background-color: var(--color-surface-elevated);
		color: var(--color-text);
		border: 1px solid var(--color-border-strong);
		border-radius: var(--radius-md);
		box-shadow: 0 0 40px 0 rgba(0, 0, 0, 0.18);
		overflow: hidden;
	}

	/* Matches the Sidebar overlay treatment: faint white tint over the
	   dark surface plus a small blur, rather than a heavy dim. Keeps the
	   underlying app visible behind the modal. */
	.modal::backdrop {
		background-color: rgba(255, 255, 255, 0.04);
		backdrop-filter: blur(2px);
		-webkit-backdrop-filter: blur(2px);
	}

	.content {
		display: flex;
		flex-direction: column;
		gap: 14px;
		padding: 18px 22px 22px;
	}

	.modalHeader {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: 2px;
	}

	.brand {
		display: inline-flex;
		align-items: center;
		gap: 8px;
	}

	.brandIcon {
		width: 20px;
		height: 20px;
		border-radius: 4px;
		border: 1px solid var(--color-border);
	}

	.brandName {
		font-family: var(--font-display);
		font-size: 11px;
		font-weight: 600;
		letter-spacing: var(--tracking-default);
		color: var(--color-text);
		text-transform: uppercase;
	}

	/* `all: unset` strips the global gradient button rules so the close
	   affordance reads as a quiet icon button rather than a CTA. */
	.closeButton {
		all: unset;
		width: 24px;
		height: 24px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-sm);
		color: var(--color-text-muted);
		font-size: 14px;
		cursor: pointer;
		transition:
			color var(--transition-base),
			background-color var(--transition-fast);
	}

	.closeButton:hover {
		color: var(--color-text);
		background-color: var(--color-surface-muted);
	}

	.subtitle {
		width: auto;
		margin: -6px 0 2px;
		font-size: 12px;
		font-weight: 300;
		line-height: 1.45;
		color: var(--color-text-muted);
	}

	.emphasis {
		color: var(--color-text);
	}

	.form {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}

	.field {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.field input {
		height: 36px;
		width: 100%;
		padding: 0 14px;
		background-color: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-pill);
		transition: border-color var(--transition-base);
	}

	.field input:hover {
		border-color: var(--color-border-strong);
	}

	.field input:focus {
		outline: none;
		border-color: var(--color-border-strong);
	}

	.field input:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	/* Six fixed-width cells laid out in a flex row. `flex: 1 1 0` lets
	   the boxes share the modal's content width equally and shrink
	   together on narrow viewports (the modal's max-width can drop
	   below 380px on small screens), avoiding overflow. */
	.otpBoxes {
		display: flex;
		gap: 8px;
		width: 100%;
	}

	.otpBox {
		flex: 1 1 0;
		min-width: 0;
		height: 44px;
		padding: 0;
		text-align: center;
		font-family: ui-monospace, 'JetBrains Mono', 'SFMono-Regular', Menlo, monospace;
		font-size: 18px;
		color: var(--color-text);
		background-color: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-pill);
		transition: border-color var(--transition-base);
	}

	.otpBox:hover {
		border-color: var(--color-border-strong);
	}

	.otpBox:focus {
		outline: none;
		border-color: var(--color-border-strong);
	}

	.otpBox:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.error {
		width: auto;
		margin: -4px 0 -2px;
		font-size: 11px;
		color: var(--color-error);
	}

	/* The global `button` rule already paints the gradient + radius — this
	   only overrides geometry. width 100% always wins over the 142px
	   min-width inside the 380px - 44px padding modal. */
	.primary {
		width: 100%;
		height: 36px;
	}

	.primary:disabled {
		cursor: not-allowed;
		filter: grayscale(0.4) brightness(0.85);
		box-shadow: none;
	}

	.links {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 8px;
		margin: -4px -8px -8px;
	}

	/* Shared geometry / typography for the two below-CTA links. The
	   colour + interaction signatures diverge per-button below. */
	.backLink,
	.resendLink {
		all: unset;
		padding: var(--space-sm);
		font-family: var(--font-sans);
		font-size: var(--text-sm);
		font-weight: 300;
		letter-spacing: var(--tracking-default);
		cursor: pointer;
	}

	/* Back: starts at the secondary (muted) text colour so it reads as
	   subordinate to the verify CTA above; brightens to the primary text
	   colour on hover; opacity dip on press for tactile feedback without
	   another colour shift. */
	.backLink {
		color: var(--color-text-muted);
		transition:
			color var(--transition-base),
			opacity var(--transition-base);
	}

	.backLink:hover {
		color: var(--color-text);
	}

	.backLink:active {
		opacity: 0.8;
	}

	.backLink:disabled {
		cursor: not-allowed;
		color: var(--color-text-faded);
	}

	/* Resend: tinted in the primary teal so it reads as a secondary
	   accent against the back link. Faded at rest so it doesn't
	   compete with the verify CTA above; full brightness on hover;
	   slight dip on press for tactile feedback. */
	.resendLink {
		color: var(--color-primary);
		opacity: 0.6;
		transition: opacity var(--transition-base);
	}

	.resendLink:hover {
		opacity: 1;
	}

	.resendLink:active {
		opacity: 0.8;
	}

	.resendLink:disabled {
		cursor: not-allowed;
		opacity: 0.3;
	}

	/* Success-stage card. Holds the EOA + smart wallet addresses in a
	   surface-on-elevated treatment so it reads as a distinct "here are
	   your new credentials" block rather than a continuation of the
	   form. Non-interactive — no hover state. */
	.walletCard {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 12px 14px;
		background-color: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}

	.walletRow {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
	}

	.addr {
		font-family: ui-monospace, 'JetBrains Mono', 'SFMono-Regular', Menlo, monospace;
		font-size: 12px;
		color: var(--color-text);
	}
</style>
