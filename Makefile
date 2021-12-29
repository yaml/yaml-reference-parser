SHELL := bash

ROOT := $(shell pwd)

PARSER_1_3 := parser-1.3
PARSER_1_2 := parser-1.2

ALL := \
    $(PARSER_1_3) \
    $(PARSER_1_2) \

ALL_TEST := $(ALL:parser-%=test-%)
ALL_CLEAN := $(ALL:parser-%=clean-%)

default:
	@echo $(ALL_TEST)

test: test-1.3

test-all: $(ALL_TEST)

$(ALL_TEST):
	$(MAKE) -C $(@:test-%=parser-%) test TRACE=$(TRACE) DEBUG=$(DEBUG)

clean: $(ALL_CLEAN)
	rm -fr node_modules

$(ALL_CLEAN):
	$(MAKE) -C $(@:clean-%=parser-%) clean

node_modules:
	git branch --track $@ origin/$@ 2>/dev/null || true
	git worktree add -f $@ $@
