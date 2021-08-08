module vcl

pub type ArgumentType = Bytes | Vector | byte | f32 | i8 | int | u32 | u8

// kernel returns a kernel
// if retrieving the kernel didn't complete the function will return an error
pub fn (d &Device) kernel(name string) ?&Kernel {
	mut k := C.cl_kernel{}
	mut ret := 0
	for p in d.programs {
		k = C.clCreateKernel(p, name, &ret)
		if ret == C.CL_INVALID_KERNEL_NAME {
			continue
		}
		if ret != C.CL_SUCCESS {
			return vcl_error(ret)
		}
		break
	}
	if ret == C.CL_INVALID_KERNEL_NAME {
		return error("kernel with name '$name' not found")
	}
	return new_kernel(d, k)
}

// UnsupportedArgumentTypeError error
pub struct UnsupportedArgumentTypeError {
pub:
	code  int
	msg   string
	index int
	value ArgumentType
}

fn new_unsupported_argument_type_error(index int, value ArgumentType) IError {
	return UnsupportedArgumentTypeError{
		index: index
		value: value
		msg: 'cl: unsupported argument type for index $index: $value'
	}
}

// Kernel represent a single kernel
pub struct Kernel {
	d &Device
	k C.cl_kernel
}

// global returns an kernel with global size set
pub fn (k &Kernel) global(global_work_sizes ...int) KernelWithGlobal {
	return KernelWithGlobal{
		kernel: unsafe { k }
		global_work_sizes: global_work_sizes
	}
}

// KernelWithGlobal is a kernel with the global size set
// to run the kernel it must also set the local size
pub struct KernelWithGlobal {
	kernel            &Kernel
	global_work_sizes []int
}

// local ets the local work sizes and returns an KernelCall which takes kernel arguments and runs the kernel
fn (kg KernelWithGlobal) local(local_work_sizes ...int) KernelCall {
	return KernelCall{
		kernel: kg.kernel
		global_work_sizes: kg.global_work_sizes
		local_work_sizes: local_work_sizes
	}
}

// KernelCall is a kernel with global and local work sizes set
// and it's ready to be run
pub struct KernelCall {
	kernel            &Kernel
	global_work_sizes []int
	local_work_sizes  []int
}

// run calls the kernel on its device with specified global and local work sizes and arguments
// it's a non-blocking call, so it returns a channel that will send an error value when the kernel is done
// or nil if the call was successful
fn (kc KernelCall) run(args ...ArgumentType) chan IError {
	ch := chan IError{cap: 1}
	kc.kernel.set_args(...args) or {
		ch <- err
		return ch
	}
	return kc.kernel.call(kc.global_work_sizes, kc.local_work_sizes)
}

fn release_kernel(k &Kernel) {
	C.clReleaseKernel(k.k)
}

fn new_kernel(d &Device, k C.cl_kernel) &Kernel {
	return &Kernel{
		d: d
		k: k
	}
}

fn (k &Kernel) set_args(args ...ArgumentType) ? {
	for i, arg in args {
		k.set_arg(i, arg) ?
	}
}

fn (k &Kernel) set_arg(index int, arg ArgumentType) ? {
	match arg {
		u8 {
			return k.set_arg_u8(index, arg)
		}
		i8 {
			return k.set_arg_i8(index, arg)
		}
		u32 {
			return k.set_arg_u32(index, arg)
		}
		int {
			return k.set_arg_int(index, arg)
		}
		f32 {
			return k.set_arg_f32(index, arg)
		}
		Bytes {
			return k.set_arg_buffer(index, arg.buf)
		}
		Vector {
			return k.set_arg_buffer(index, arg.buf)
		}
		// @todo: Image {
		// 	return k.set_arg_buffer(index, arg.buf)
		// }
		// @todo: LocalBuffer {
		//     return k.set_arg_local(index, int(arg))
		// }
		else {
			return new_unsupported_argument_type_error(index, arg)
		}
	}
}

fn (k &Kernel) set_arg_buffer(index int, buf &Buffer) ? {
	mem := buf.memobj
	return vcl_error(C.clSetKernelArg(k.k, u32(index), int(sizeof(mem)), unsafe { &mem }))
}

fn (k &Kernel) set_arg_f32(index int, val f32) ? {
	return k.set_arg_unsafe(index, int(sizeof(val)), unsafe { &val })
}

fn (k &Kernel) set_arg_i8(index int, val i8) ? {
	return k.set_arg_unsafe(index, int(sizeof(val)), unsafe { &val })
}

fn (k &Kernel) set_arg_u8(index int, val u8) ? {
	return k.set_arg_unsafe(index, int(sizeof(val)), unsafe { &val })
}

fn (k &Kernel) set_arg_int(index int, val int) ? {
	return k.set_arg_unsafe(index, int(sizeof(val)), unsafe { &val })
}

fn (k &Kernel) set_arg_u32(index int, val u32) ? {
	return k.set_arg_unsafe(index, int(sizeof(val)), unsafe { &val })
}

fn (k &Kernel) set_arg_local(index int, size int) ? {
	return k.set_arg_unsafe(index, size, voidptr(0))
}

fn (k &Kernel) set_arg_unsafe(index int, arg_size int, arg voidptr) ? {
	res := C.clSetKernelArg(k.k, u32(index), u32(arg_size), arg)
	if res != C.CL_SUCCESS {
		return vcl_error(res)
	}
}

fn (k &Kernel) call(work_sizes []int, lokal_sizes []int) chan IError {
	ch := chan IError{cap: 1}
	work_dim := work_sizes.len
	if work_dim != lokal_sizes.len {
		ch <- error('length of work_sizes and localSizes differ')
		return ch
	}
	mut global_work_offset_ptr := []u32{len: work_dim}
	mut global_work_size_ptr := []u32{len: work_dim}
	for i in 0 .. work_dim {
		global_work_size_ptr[i] = u32(work_sizes[i])
	}
	mut local_work_size_ptr := []u32{len: work_dim}
	for i in 0 .. work_dim {
		local_work_size_ptr[i] = u32(lokal_sizes[i])
	}
	mut event := C.cl_event{}
	res := C.clEnqueueNDRangeKernel(k.d.queue, k.k, u32(work_dim), unsafe { &global_work_offset_ptr[0] },
		unsafe { &global_work_size_ptr[0] }, unsafe { &local_work_size_ptr[0] }, 0, voidptr(0),
		unsafe { &event })
	if res != C.CL_SUCCESS {
		err := vcl_error(res)
		ch <- err
		return ch
	}
	go fn (event C.cl_event) {
		defer {
			C.clReleaseEvent(event)
		}
		res := C.clWaitForEvents(1, unsafe { &event })
		if res != C.CL_SUCCESS {
			ch <- vcl_error(res)
		}
	}(event)
	return ch
}
