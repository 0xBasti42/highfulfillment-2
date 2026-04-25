import type { IChartApi, ISeriesApi, SeriesType } from 'lightweight-charts';
import {
	DrawingManager,
	getToolRegistry,
	type Anchor,
	type DrawingStyle,
	type IDrawing
} from 'lightweight-charts-drawing';

/**
 * Thin facade over `lightweight-charts-drawing`'s `DrawingManager`.
 *
 * Why this exists rather than binding directly:
 * - The library is v0.1.x with a single maintainer, so we want one file to
 *   swap if we later move to a different plugin or roll our own primitives.
 * - More importantly, `manager.setActiveTool()` only sets a flag — it does NOT
 *   wire up interactive placement. That whole pipeline (click → coords →
 *   anchors → preview → final drawing) is the consumer's job; the library's
 *   own demo implements it manually. This adapter encapsulates that loop so
 *   `ChartTools.svelte` stays declarative ("activate this tool, please").
 *
 * Reactive `state` is a `$state` object the adapter mutates from inside
 * `DrawingManager` event subscriptions, so Svelte components just read
 * `adapter.state.activeTool` and re-render automatically.
 */

export interface ChartDrawingState {
	/** Tool type currently in interactive-placement mode (e.g. 'trend-line'), or null. */
	activeTool: string | null;
	/** Whether a drawing is currently selected (drives the delete button's enabled state). */
	hasSelection: boolean;
}

/** Stable id for the in-progress preview drawing. Filtered out of any future "drawing list" UI. */
const PREVIEW_ID = '__lwc-drawing-preview__';

/**
 * Default style for new drawings. Soft neutral grey with built-in alpha sits
 * on top of both bullish and bearish candles without competing for attention,
 * which is the right call for analyst markup overlaid on price action.
 *
 * Format is 8-char hex (#RRGGBBAA): line at ~44% alpha, fill at ~10% so
 * shape interiors (rectangles, channels, fib zones) stay legible.
 */
const DEFAULT_DRAWING_STYLE: Partial<DrawingStyle> = {
	lineColor: '#d6d6d670',
	lineWidth: 2,
	fillColor: '#d6d6d61a'
};

/**
 * Fibonacci tools render N parallel lines and benefit from being thinner and
 * slightly darker so the multiple levels read as a single grouped overlay
 * rather than as N independent prominent lines competing with the candles.
 */
const FIB_DRAWING_STYLE: Partial<DrawingStyle> = {
	lineColor: '#737373',
	lineWidth: 1,
	fillColor: '#73737326'
};

export class ChartDrawingAdapter {
	readonly manager: DrawingManager;
	readonly state: ChartDrawingState = $state({ activeTool: null, hasSelection: false });

	private _chart: IChartApi | null = null;
	private _series: ISeriesApi<SeriesType> | null = null;
	private _container: HTMLElement | null = null;

	private _eventUnsubscribers: Array<() => void> = [];

	// Interactive placement state
	private _pendingAnchors: Anchor[] = [];
	private _previewDrawing: IDrawing | null = null;
	private _idCounter = 0;

	// Tracks whether we've temporarily disabled chart panning for an in-progress
	// drag of a drawing or anchor; pointerup uses this to know if it needs to
	// restore the chart options.
	private _chartPanLocked = false;

	constructor() {
		this.manager = new DrawingManager();
	}

	attach(chart: IChartApi, series: ISeriesApi<SeriesType>, container: HTMLElement): void {
		this._chart = chart;
		this._series = series;
		this._container = container;

		this.manager.attach(chart, series, container);

		this._eventUnsubscribers.push(
			this.manager.on('tool:changed', (event) => {
				const next = event.toolType ?? null;
				// Switching tools mid-placement aborts the in-progress drawing —
				// otherwise stale anchors from the previous tool would carry over.
				if (next !== this.state.activeTool) this.cancelPlacement();
				this.state.activeTool = next;
			}),
			this.manager.on('drawing:selected', () => {
				this.state.hasSelection = true;
			}),
			this.manager.on('drawing:deselected', () => {
				this.state.hasSelection = false;
			}),
			this.manager.on('drawing:removed', () => {
				// Removing the selected drawing implicitly deselects it; the library
				// doesn't always fire `drawing:deselected` in that case, so re-derive.
				this.state.hasSelection = this.manager.getSelectedDrawing() !== null;
			}),
			this.manager.on('drawing:cleared', () => {
				this.state.hasSelection = false;
				this.cancelPlacement();
				this.manager.setActiveTool(null);
			})
		);

		// Click on the chart surface is what advances the placement FSM. Mousemove
		// drives the rubber-band preview. Escape cancels. Listen at the container
		// level so all canvas children bubble up.
		container.addEventListener('click', this.onContainerClick);
		container.addEventListener('mousemove', this.onContainerMouseMove);
		document.addEventListener('keydown', this.onDocumentKeyDown);

		// Capture-phase pointer listeners run BEFORE lightweight-charts' own
		// handlers, giving us a chance to disable chart panning when the user
		// presses on a drawing or anchor. Without this, a drag on an anchor
		// also pans the chart simultaneously because both event systems claim
		// the same pointerdown.
		container.addEventListener('pointerdown', this.onContainerPointerDownCapture, {
			capture: true
		});
		document.addEventListener('pointerup', this.onDocumentPointerUpCapture, {
			capture: true
		});
	}

	detach(): void {
		this._container?.removeEventListener('click', this.onContainerClick);
		this._container?.removeEventListener('mousemove', this.onContainerMouseMove);
		document.removeEventListener('keydown', this.onDocumentKeyDown);
		this._container?.removeEventListener('pointerdown', this.onContainerPointerDownCapture, {
			capture: true
		});
		document.removeEventListener('pointerup', this.onDocumentPointerUpCapture, {
			capture: true
		});
		// In case detach happens mid-drag, leave chart in a sane state.
		this.unlockChartPan();

		for (const unsub of this._eventUnsubscribers) unsub();
		this._eventUnsubscribers = [];

		this.cancelPlacement();
		this.manager.detach();

		this._chart = null;
		this._series = null;
		this._container = null;
		this.state.activeTool = null;
		this.state.hasSelection = false;
	}

	toggleActiveTool(toolType: string): void {
		const next = this.state.activeTool === toolType ? null : toolType;
		this.manager.setActiveTool(next);
	}

	clearActiveTool(): void {
		this.manager.setActiveTool(null);
	}

	removeSelected(): void {
		const selected = this.manager.getSelectedDrawing();
		if (!selected) return;
		this.manager.removeDrawing(selected.id);
	}

	clearAll(): void {
		this.manager.clearAll();
	}

	// --- Interactive placement engine -------------------------------------------------

	/**
	 * Arrow-bound so removing the listener uses the same reference. Ignores
	 * clicks when no tool is active (chart pan / crosshair behavior is unaffected)
	 * and silently drops clicks that fall outside the data range.
	 */
	private onContainerClick = (event: MouseEvent): void => {
		const tool = this.state.activeTool;
		if (!tool || !this._chart || !this._series || !this._container) return;

		const anchor = this.eventToAnchor(event);
		if (!anchor) return;

		this._pendingAnchors.push(anchor);
		const required = this.getRequiredAnchors(tool);

		if (this._pendingAnchors.length >= required) {
			// Promote the in-progress preview into a real, persisted drawing,
			// then auto-deselect the tool. This is smoother than keeping the tool
			// armed because users typically want to inspect or adjust the drawing
			// they just placed before drawing another — keeping the tool active
			// makes every subsequent chart click an accidental new anchor.
			this.removePreview();
			const drawing = this.createDrawing(tool, this._pendingAnchors);
			if (drawing) this.manager.addDrawing(drawing);
			this._pendingAnchors = [];
			this.manager.setActiveTool(null);
		} else {
			this.refreshPreview(anchor);
		}
	};

	private onContainerMouseMove = (event: MouseEvent): void => {
		if (!this.state.activeTool || this._pendingAnchors.length === 0) return;
		if (!this._previewDrawing) return;

		const cursorAnchor = this.eventToAnchor(event);
		if (!cursorAnchor) return;

		// Update only the anchor(s) the user hasn't placed yet — fixed anchors
		// stay where they were committed.
		const required = this.getRequiredAnchors(this.state.activeTool);
		for (let i = this._pendingAnchors.length; i < required; i++) {
			this._previewDrawing.updateAnchor(i, cursorAnchor);
		}
	};

	private onDocumentKeyDown = (event: KeyboardEvent): void => {
		if (event.key !== 'Escape') return;
		// Escape unwinds: first cancel any in-progress placement, then exit draw mode.
		if (this._pendingAnchors.length > 0 || this._previewDrawing) {
			this.cancelPlacement();
		} else if (this.state.activeTool) {
			this.manager.setActiveTool(null);
		}
	};

	/**
	 * Suppress chart panning when the user presses on a drawing or anchor so
	 * the drawing library's drag-edit can run without the chart simultaneously
	 * panning. We never call `event.stopPropagation()` — the drawing library
	 * still needs the pointerdown to start its own drag FSM. We just toggle
	 * chart options, which lightweight-charts will read when it processes the
	 * pointerdown right after us.
	 *
	 * Skipping while a tool is active means we don't suppress chart panning
	 * during interactive placement (the user might brush past an existing
	 * drawing on the way to placing a new anchor).
	 */
	private onContainerPointerDownCapture = (event: PointerEvent): void => {
		if (!this._chart || !this._container) return;
		if (this.state.activeTool) return;

		const rect = this._container.getBoundingClientRect();
		const point = { x: event.clientX - rect.left, y: event.clientY - rect.top };

		// `hitTest` covers the drawing body (translate-the-whole-shape drag).
		// `hitTestAnchor` covers the per-vertex handles on the selected drawing.
		const hitsDrawing = this.manager.hitTest(point) !== null;
		const hitsAnchor = this.manager.hitTestAnchor(point) !== null;
		if (!hitsDrawing && !hitsAnchor) return;

		this.lockChartPan();
	};

	/**
	 * Fires on document so we still catch pointerup if the user drags off the
	 * container before releasing. Capture phase symmetrical with pointerdown
	 * so we restore options before lightweight-charts evaluates anything.
	 */
	private onDocumentPointerUpCapture = (): void => {
		if (this._chartPanLocked) this.unlockChartPan();
	};

	private lockChartPan(): void {
		if (!this._chart || this._chartPanLocked) return;
		this._chart.applyOptions({
			handleScroll: { pressedMouseMove: false },
			handleScale: { axisPressedMouseMove: false }
		});
		this._chartPanLocked = true;
	}

	private unlockChartPan(): void {
		if (!this._chart || !this._chartPanLocked) return;
		this._chart.applyOptions({
			handleScroll: { pressedMouseMove: true },
			handleScale: { axisPressedMouseMove: true }
		});
		this._chartPanLocked = false;
	}

	private cancelPlacement(): void {
		this.removePreview();
		this._pendingAnchors = [];
	}

	/**
	 * Build / rebuild the preview drawing whenever a new anchor is committed.
	 * Some tools require N>2 anchors — we fill the unplaced slots with the
	 * latest anchor so the preview is geometrically valid; mousemove will then
	 * stretch them to follow the cursor.
	 */
	private refreshPreview(latestAnchor: Anchor): void {
		const tool = this.state.activeTool;
		if (!tool) return;

		const required = this.getRequiredAnchors(tool);
		const previewAnchors: Anchor[] = [...this._pendingAnchors];
		while (previewAnchors.length < required) previewAnchors.push({ ...latestAnchor });

		this.removePreview();
		const preview = this.createDrawing(tool, previewAnchors, PREVIEW_ID);
		if (preview) {
			this._previewDrawing = preview;
			this.manager.addDrawing(preview);
		}
	}

	private removePreview(): void {
		if (!this._previewDrawing) return;
		this.manager.removeDrawing(PREVIEW_ID);
		this._previewDrawing = null;
	}

	private createDrawing(
		toolType: string,
		anchors: Anchor[],
		id?: string
	): IDrawing | null {
		const drawingId = id ?? `drawing-${++this._idCounter}-${Date.now()}`;
		return getToolRegistry().createDrawing(toolType, drawingId, [...anchors], this.getStyleFor(toolType));
	}

	/**
	 * Resolve the style override for a given tool. Fib tools get a thinner,
	 * darker palette so the multiple parallel lines read as one grouped overlay.
	 * All other tools fall back to the default soft-grey style.
	 */
	private getStyleFor(toolType: string): Partial<DrawingStyle> {
		if (toolType.startsWith('fib-')) return FIB_DRAWING_STYLE;
		return DEFAULT_DRAWING_STYLE;
	}

	private getRequiredAnchors(toolType: string): number {
		return getToolRegistry().get(toolType)?.requiredAnchors ?? 2;
	}

	/**
	 * Convert a DOM mouse event to a chart-space anchor. Returns null if the
	 * click falls outside the data range (lightweight-charts returns null for
	 * coords beyond the visible series), which we treat as a no-op rather than
	 * rejecting with an error.
	 */
	private eventToAnchor(event: MouseEvent): Anchor | null {
		if (!this._chart || !this._series || !this._container) return null;
		const rect = this._container.getBoundingClientRect();
		const x = event.clientX - rect.left;
		const y = event.clientY - rect.top;

		const time = this._chart.timeScale().coordinateToTime(x);
		const price = this._series.coordinateToPrice(y);
		if (time === null || price === null) return null;
		return { time, price };
	}
}
