/* >>>> Generated by mkmark.rkt from mzmarksrc.c <<<< */

static int mark_string_convert_SIZE(void *p, struct NewGC *gc) {
  return
  gcBYTES_TO_WORDS(sizeof(Scheme_Converter));
}

static int mark_string_convert_MARK(void *p, struct NewGC *gc) {
  Scheme_Converter *c = (Scheme_Converter *)p;
  gcMARK2(c->mref, gc);
  return
  gcBYTES_TO_WORDS(sizeof(Scheme_Converter));
}

static int mark_string_convert_FIXUP(void *p, struct NewGC *gc) {
  Scheme_Converter *c = (Scheme_Converter *)p;
  gcFIXUP2(c->mref, gc);
  return
  gcBYTES_TO_WORDS(sizeof(Scheme_Converter));
}

#define mark_string_convert_IS_ATOMIC 0
#define mark_string_convert_IS_CONST_SIZE 1

