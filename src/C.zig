// Disabling inlining makes zig translate-c's job much easier
const C = @cImport({
    @cInclude("libguile/scmconfig.h");
    @cUndef("SCM_C_INLINE");
    @cInclude("libguile.h");
});

pub usingnamespace C;

// glue.c
pub extern fn scm_is_a_p(C.SCM, C.SCM) bool;
