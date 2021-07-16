module vimpl

[unsafe]
pub fn q_rsqrt(x f64) f64 {
	x_half := 0.5 * x
	mut i := i64(vimpl.f64_bits(x))
	i = 0x5fe6eb50c7b537a9 - (i >> 1)
	mut j := vimpl.f64_from_bits(u64(i))
	j *= (1.5 - x_half * j * j)
	j *= (1.5 - x_half * j * j)
	return j
}
