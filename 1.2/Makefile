SHELL := bash

ROOT := $(shell pwd)

SPEC_YAML := build/yaml-spec-1.2-patch.yaml

ALL := \
    coffeescript \
    javascript \
    perl \

ALL_BUILD := $(ALL:%=build-%)
ALL_TEST := $(ALL:%=test-%)
ALL_CLEAN := $(ALL:%=clean-%)

default:

build: $(ALL_BUILD)

build-%:
	$(MAKE) -C $(@:build-%=%) build

test: $(ALL_TEST)

test-%:
	$(MAKE) -C $(@:test-%=%) test TRACE=$(TRACE) DEBUG=$(DEBUG)

clean: $(ALL_CLEAN)
	rm -fr node_modules
	$(MAKE) -C $(ROOT)/test $@

clean-%:
	$(MAKE) -C $(@:clean-%=%) clean

docker-build:
	docker build -t yaml-grammar-test test

docker-test: docker-build
	docker run -t \
	    -v"$(ROOT):/yaml-grammar" \
	    -u $$(id -u "$$USER"):$$(id -g "$$USER") \
	    yaml-grammar-test \
	    $(MAKE) -C /yaml-grammar/parser test

node_modules:
	git branch --track $@ origin/$@ 2>/dev/null || true
	git worktree add -f $@ $@
