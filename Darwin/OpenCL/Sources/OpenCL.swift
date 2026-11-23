// The Apple extension that sets a kernel's arguments in one call takes C
// varargs, which Swift doesn't import; the overlay passes Swift's through
// the va_list form of it.

@available(macOS 10.7, *)
public func clSetKernelArgsListAPPLE(_ kernel: cl_kernel, _ uint: cl_uint, _ args: CVarArg...) -> cl_int {
    withVaList(args) { clSetKernelArgsVaListAPPLE(kernel, uint, $0) }
}
