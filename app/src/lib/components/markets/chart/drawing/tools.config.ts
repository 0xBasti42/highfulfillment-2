/**
 * Curated subset of `lightweight-charts-drawing`'s 68 tools surfaced in the
 * `ChartTools` palette. Picked for what's actually useful in a price chart
 * for an active trader — lines, channels, Fib, simple shapes, position
 * planning, and a free-draw brush. The full registry is still reachable via
 * the manager for power users / programmatic creation.
 *
 * `type` strings match the tool class `readonly type` literals exported by
 * the library (e.g. `TrendLine.type = 'trend-line'`), so they're the strings
 * `DrawingManager.setActiveTool(type)` expects.
 *
 * Icons are inline SVG path data on a 16x16 viewBox, drawn with `currentColor`
 * stroke so they pick up the button's text color (active vs idle).
 */

export interface ChartTool {
	type: string;
	label: string;
	icon: string;
}

export interface ChartToolGroup {
	id: string;
	tools: ChartTool[];
}

export const CHART_TOOL_GROUPS: ChartToolGroup[] = [
	{
		id: 'lines',
		tools: [
			{
				type: 'trend-line',
				label: 'Trend line',
				icon: 'M2.5 13.5 L13.5 2.5'
			},
			{
				type: 'horizontal-line',
				label: 'Horizontal line',
				icon: 'M1.5 8 L14.5 8'
			},
			{
				type: 'ray',
				label: 'Ray',
				icon: 'M2.5 13.5 L13.5 2.5 M13.5 2.5 L10.5 3 M13.5 2.5 L13 5.5'
			}
		]
	},
	{
		id: 'analysis',
		tools: [
			{
				type: 'parallel-channel',
				label: 'Parallel channel',
				icon: 'M2 12 L14 4 M2 14 L14 6'
			},
			{
				type: 'fib-retracement',
				label: 'Fibonacci retracement',
				icon: 'M2 13 L14 13 M2 10 L14 10 M2 7 L14 7 M2 4 L14 4 M2 13 L14 4'
			}
		]
	},
	{
		id: 'shapes',
		tools: [
			{
				type: 'rectangle',
				label: 'Rectangle',
				icon: 'M2.5 3.5 L13.5 3.5 L13.5 12.5 L2.5 12.5 Z'
			},
			{
				type: 'brush',
				label: 'Brush',
				icon: 'M2 13 C 5 9, 7 12, 10 7 S 13 4, 14 3'
			}
		]
	},
	{
		id: 'trading',
		tools: [
			{
				type: 'long-position',
				label: 'Long position',
				icon: 'M2.5 11.5 L13.5 11.5 L13.5 7.5 L2.5 7.5 Z M8 6 L8 2 M5.5 4 L8 1.5 L10.5 4'
			},
			{
				type: 'short-position',
				label: 'Short position',
				icon: 'M2.5 8.5 L13.5 8.5 L13.5 4.5 L2.5 4.5 Z M8 10 L8 14 M5.5 12 L8 14.5 L10.5 12'
			}
		]
	},
	{
		id: 'annotations',
		tools: [
			{
				type: 'text-annotation',
				label: 'Text',
				icon: 'M3 3 L13 3 M8 3 L8 13'
			}
		]
	}
];
