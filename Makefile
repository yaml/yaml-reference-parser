SHELL := bash

ROOT := $(shell pwd)

CODE_1_3 := 1.3
CODE_1_2 := 1.2

ALL := \
    $(CODE_1_3) \
    $(CODE_1_2) \

ALL_TEST := $(ALL:%=test-%)
ALL_CLEAN := $(ALL:%=clean-%)

default:
	@echo $(ALL_TEST)

test: test-1.3

test-all: $(ALL_TEST)

$(ALL_TEST):
	$(MAKE) -C $(@:test-%=%) test TRACE=$(TRACE) DEBUG=$(DEBUG)

clean: $(ALL_CLEAN)
	rm -fr node_modules

$(ALL_CLEAN):
	$(MAKE) -C $(@:clean-%=%) clean

node_modules:
	git branch --track $@ origin/$@ 2>/dev/null || true
	git worktree add -f $@ $@
