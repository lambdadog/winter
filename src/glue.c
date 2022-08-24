/*
  Zig has issues translating some macros, so this file defines glue
  functions that wrap the macros we need.
 */

#include <libguile.h>

extern int
scm_is_a_p (SCM val, SCM type)
{
  return SCM_IS_A_P (val, type);
}
