module main

import rand
import vsl.plot

fn main() {
	rand.seed([u32(1), 42])

	mut x := []f64{cap: 100}
	for _ in 1 .. 100 {
		x << rand.f64n(100) or { 0 }
	}

	mut plt := plot.new_plot()
	plt.add_trace(
		trace_type: .scatter
		x: x
		y: x
		mode: 'markers'
		marker: plot.Marker{
			size: []f64{len: x.len, init: 10.0}
			color: []string{len: x.len, init: '#FF0000'}
		}
	)
	plt.add_trace(
		trace_type: .histogram
		x: x
	)
	plt.set_layout(
		title: 'Scatter with Histogram'
	)
	plt.show()!
}
