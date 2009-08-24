#
# $Id$
#

# GNU MAKE file for Pelles ISO C Compiler

OBJ_EXT := .obj
LIB_PREF :=
LIB_EXT := .lib

HB_DYN_COPT := -DHB_DYNLIB

CC := pocc.exe
CC_IN := -c
CC_OUT := -Fo

CPPFLAGS := -I.
CPPFLAGS += -Ze -Go -MT
CFLAGS :=
LDFLAGS :=

ifneq ($(HB_BUILD_WARN),no)
   CPPFLAGS += -W1
endif

ifneq ($(HB_BUILD_OPTIM),no)
   CPPFLAGS += -Ot
   # -Ox: can cause GPF in 4.50/5.00, so it's disabled.
endif

ifneq ($(HB_INC_COMPILE),)
   CPPFLAGS += -I$(HB_INC_COMPILE)
endif

ifeq ($(HB_BUILD_DEBUG),yes)
   CPPFLAGS += -Zi
endif

LD := polink.exe
LD_OUT := /out:

LIBPATHS := /libpath:$(LIB_DIR)
LDLIBS := $(foreach lib,$(LIBS) $(SYSLIBS),$(lib)$(LIB_EXT))

LDFLAGS += /subsystem:console
LDFLAGS += $(LIBPATHS)

AR := polib.exe
ARFLAGS :=
AR_RULE = $(AR) $(ARFLAGS) $(HB_USER_AFLAGS) /out:$(LIB_DIR)/$@ $(^F)

DY := $(LD)
DFLAGS := /nologo /dll
DY_OUT := $(LD_OUT)
DLIBS := $(foreach lib,$(SYSLIBS),$(lib)$(LIB_EXT))

# NOTE: The empty line directly before 'endef' HAVE TO exist!
define dyn_object
   @$(ECHO) $(ECHOQUOTE)$(file)$(ECHOQUOTE) >> __dyn__.tmp

endef
define create_dynlib
   $(if $(wildcard __dyn__.tmp),@$(RM) __dyn__.tmp,)
   $(foreach file,$^,$(dyn_object))
   $(DY) $(DFLAGS) $(HB_USER_DFLAGS) $(DY_OUT)"$(subst /,$(DIRSEP),$(DYN_DIR)/$@)" /implib:"$(IMP_FILE)" @__dyn__.tmp $(DLIBS)
endef

DY_RULE = $(create_dynlib)

include $(TOP)$(ROOT)config/rules.mk
