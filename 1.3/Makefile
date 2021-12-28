SHELL := bash

ROOT := $(shell cd ..; pwd)

ALL := \
    javascript \

# ALL_BUILD := $(ALL:%=build-%)
ALL_TEST := $(ALL:%=test-%)
ALL_CLEAN := $(ALL:%=clean-%)

default:

# build: $(ALL_BUILD)

# build-%:
# 	$(MAKE) -C $(@:build-%=%) build

test: $(ALL_TEST)

test-%:
	$(MAKE) -C $(@:test-%=%) test TRACE=$(TRACE) DEBUG=$(DEBUG)

clean: $(ALL_CLEAN)
	$(MAKE) -C $(ROOT)/test $@

clean-%:
	$(MAKE) -C $(@:clean-%=%) clean
