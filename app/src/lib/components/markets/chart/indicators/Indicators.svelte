<script lang="ts">
	import PointsEst from './points-est/PointsEst.svelte';
	import Volume from './volume/Volume.svelte';
</script>

<!--
	Indicator components register themselves as panes on the parent PriceChart's
	chart instance via context. They render no DOM; their visual output is the
	chart panes inside the PriceChart canvas. Source order here = pane order
	(top-to-bottom under the candles).
-->
<PointsEst defaultHeight={50} />
<Volume defaultHeight={30} />
