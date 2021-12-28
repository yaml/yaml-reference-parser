SHELL := bash

.PHONY: test

ifeq (,$(ROOT))
    $(error ROOT not defined)
endif
ifeq (,$(BASE))
    $(error BASE not defined)
endif
BASE12 := $(ROOT)/1.2

LOCAL_MAKE := $(ROOT)/.git/local.mk
ifneq (,$(wildcard $(LOCAL_MAKE)))
    $(info ***** USING LOCAL MAKEFILE OVERRIDES *****)
    $(info ***** $(LOCAL_MAKE))
    include $(LOCAL_MAKE)
endif

SPEC_PATCHED_YAML := $(BASE)/build/yaml-spec-1.2-patched.yaml
SPEC_YAML := $(BASE)/build/yaml-spec-1.2.yaml
SPEC_PATCH := $(BASE)/build/yaml-spec-1.2.patch
GENERATOR := $(BASE)/build/bin/generate-yaml-grammar
GENERATOR_LIB := $(BASE)/build/lib/generate-yaml-grammar.coffee
GENERATOR_LANG_LIB := $(BASE)/build/lib/generate-yaml-grammar-$(PARSER_LANG).coffee
NODE_MODULES := $(ROOT)/node_modules

TESTML_REPO ?= https://github.com/testml-lang/testml
TESTML_COMMIT ?= master
YAML_TEST_SUITE_REPO ?= https://github.com/yaml/yaml-test-suite
YAML_TEST_SUITE_COMMIT ?= main

PATH := $(NODE_MODULES)/.bin:$(PATH)
PATH := $(ROOT)/test/testml/bin:$(PATH)
export PATH

export TESTML_RUN := $(BIN)-tap
export TESTML_LIB := $(ROOT)/test:$(ROOT)/test/suite/test:$(TESTML_LIB)

BUILD_DEPS ?= $(NODE_MODULES)
TEST_DEPS ?= \
    $(ROOT)/test/testml \
    $(ROOT)/test/suite \

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
	    --to=$(PARSER_LANG) \
	    --rule=l-yaml-stream \
	> $@

$(SPEC_PATCHED_YAML): $(SPEC_YAML)
	cp $< $@
	patch $@ < $(SPEC_PATCH)

$(SPEC_YAML):
	cp $(ROOT)/../yaml-grammar/yaml-spec-1.2.yaml $@ || \
	wget https://raw.githubusercontent.com/yaml/yaml-grammar/master/yaml-spec-1.2.yaml || \
	curl -O https://raw.githubusercontent.com/yaml/yaml-grammar/master/yaml-spec-1.2.yaml

$(ROOT)/test/suite \
$(ROOT)/test/testml: $(ROOT)/test $(BASE12)/perl/ext-perl
	$(eval override export PERL5LIB := $(BASE12)/perl/ext-perl/lib/perl5:$(PERL5LIB))
	$(MAKE) -C $< all

$(NODE_MODULES):
	$(MAKE) -C $(ROOT) $(@:$(ROOT)/%=%)

$(BASE12)/perl/ext-perl:
	$(MAKE) -C $(BASE12)/perl ext-perl


define git-clone
mkdir $1
git -C $1 init --quiet
git -C $1 remote add origin $2
git -C $1 fetch origin $3
git -C $1 reset --hard FETCH_HEAD
endef
