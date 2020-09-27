SHELL := bash

ifeq ($(ROOT),)
    $(error ROOT not defined)
endif

SPEC_YAML := $(ROOT)/build/yaml-spec-1.2-patch.yaml
GENERATOR := $(ROOT)/build/bin/generate-yaml-grammar
GENERATOR_LIB := $(ROOT)/build/lib/generate-yaml-grammar.coffee
GENERATOR_LANG_LIB := $(ROOT)/build/lib/generate-yaml-grammar-$(LANG).coffee
NODE_MODULES := $(ROOT)/node_modules

PATH := $(NODE_MODULES)/.bin:$(PATH)
PATH := $(ROOT)/test/testml/bin:$(PATH)
export PATH

test := test/*.tml

.DELETE_ON_ERROR:

default:

build:: $(BUILD_DEPS) $(GRAMMAR)

test:: build $(TEST_DEPS)
	TRACE=$(TRACE) TRACE_QUIET=$(TRACE_QUIET) DEBUG=$(DEBUG) \
	    prove -v $(test)

clean::

$(GRAMMAR): $(SPEC_YAML) $(GENERATOR) $(GENERATOR_LIB) $(GENERATOR_LANG_LIB)
	$(GENERATOR) \
	    --from=$< \
	    --to=$(LANG) \
	    --rule=l-yaml-stream \
	> $@

../test/testml:
	git clone https://github.com/testml-lang/testml $@
	make -C $@ ext/perl
	make -C $@ src/node_modules

$(NODE_MODULES) $(SPEC_YAML):
	make -C $(ROOT) $(@:$(ROOT)/%=%)
