// Disabling inlining makes zig translate-c's job much easier
pub usingnamespace @cImport({
    @cInclude("libguile/scmconfig.h");
    @cUndef("SCM_C_INLINE");
    @cInclude("libguile.h");
});
