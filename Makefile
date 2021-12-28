SHELL := bash

ROOT := $(shell pwd)

CODE_1_2 := 1.2
CODE_1_3 := 1.3

ALL := \
    $(CODE_1_2) \
    $(CODE_1_3) \

ALL_TEST := $(ALL:%=test-%)
ALL_CLEAN := $(ALL:%=clean-%)

default:
	@echo $(ALL_TEST)

test: test-all

test-all: $(ALL_TEST)

$(ALL_TEST):
	$(MAKE) -C $(@:test-%=%) test TRACE=$(TRACE) DEBUG=$(DEBUG)

clean: $(ALL_CLEAN)

$(ALL_CLEAN):
	$(MAKE) -C $(@:clean-%=%) clean
