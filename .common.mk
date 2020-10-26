SHELL := bash

ifeq ($(ROOT),)
    $(error ROOT not defined)
endif

SPEC_PATCHED_YAML := $(ROOT)/build/yaml-spec-1.2-patched.yaml
SPEC_YAML := $(ROOT)/build/yaml-spec-1.2.yaml
SPEC_PATCH := $(ROOT)/build/yaml-spec-1.2.patch
GENERATOR := $(ROOT)/build/bin/generate-yaml-grammar
GENERATOR_LIB := $(ROOT)/build/lib/generate-yaml-grammar.coffee
GENERATOR_LANG_LIB := $(ROOT)/build/lib/generate-yaml-grammar-$(LANG).coffee
NODE_MODULES := $(ROOT)/node_modules

PATH := $(NODE_MODULES)/.bin:$(PATH)
PATH := $(ROOT)/test/testml/bin:$(PATH)
export PATH

export TESTML_RUN := $(BIN)-tap
export TESTML_LIB := $(ROOT)/test/suite/test:$(TESTML_LIB)

BUILD_DEPS ?= $(ROOT)/node_modules
TEST_DEPS ?= \
    ../test/testml \
    ../test/suite \

test := test/*.tml

.DELETE_ON_ERROR:

default:

build:: $(BUILD_DEPS) $(GRAMMAR)

test:: build $(TEST_DEPS)
	TRACE=$(TRACE) TRACE_QUIET=$(TRACE_QUIET) DEBUG=$(DEBUG) \
	    prove -v $(test)

clean::

$(GRAMMAR): $(SPEC_PATCHED_YAML) $(GENERATOR) $(GENERATOR_LIB) $(GENERATOR_LANG_LIB)
	$(GENERATOR) \
	    --from=$< \
	    --to=$(LANG) \
	    --rule=l-yaml-stream \
	> $@

$(SPEC_PATCHED_YAML): $(SPEC_YAML)
	cp $< $@
	patch $@ < $(SPEC_PATCH)

$(SPEC_YAML):
	cp $(ROOT)/../yaml-grammar/yaml-spec-1.2.yaml $@ || \
	wget https://raw.githubusercontent.com/yaml/yaml-grammar/master/yaml-spec-1.2.yaml || \
	curl -O https://raw.githubusercontent.com/yaml/yaml-grammar/master/yaml-spec-1.2.yaml

../test/testml:
	git clone https://github.com/testml-lang/testml $@
	make -C $@ ext/perl
	make -C $@ src/node_modules

../test/suite:
	git clone https://github.com/yaml/yaml-test-suite $@

$(NODE_MODULES):
	make -C $(ROOT) $(@:$(ROOT)/%=%)
