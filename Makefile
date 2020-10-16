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
	make -C $(@:build-%=%) build

test: $(ALL_TEST)

test-%:
	make -C $(@:test-%=%) test TRACE=$(TRACE) DEBUG=$(DEBUG)

clean: $(ALL_CLEAN)
	rm -fr node_modules
	rm -fr test/testml
	rm -fr test/.testml
	rm -fr test/suite

clean-%:
	make -C $(@:clean-%=%) clean

docker-build:
	docker build -t yaml-grammar-test test

docker-test: docker-build
	docker run -t \
	    -v"$(ROOT):/yaml-grammar" \
	    -u $$(id -u "$$USER"):$$(id -g "$$USER") \
	    yaml-grammar-test \
	    make -C /yaml-grammar/parser test

node_modules:
	git branch --track $@ origin/$@ 2>/dev/null || true
	git worktree add -f $@ $@

$(SPEC_YAML):
	cp $(ROOT)/../yaml-grammar/$(@:build/%=%) $@ || \
	wget https://raw.githubusercontent.com/yaml/yaml-grammar/master/$@ || \
	curl -O https://raw.githubusercontent.com/yaml/yaml-grammar/master/$@
