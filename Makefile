R := https://github.com/makeplus/makes
M := .cache/makes
$(shell [ -d '$M' ] || git clone -q $R '$M')
include $M/init.mk
include $M/node.mk
include $M/clean.mk

MAKES-CLEAN := node_modules

ALL := \
  parser-1.2 \
  parser-1.3 \

ALL-TEST := $(ALL:parser-%=test-%)
ALL-CLEAN := $(ALL:parser-%=clean-%)


test: test-1.2

test-all: $(ALL-TEST)

$(ALL-TEST):
	$(MAKE) -C $(@:test-%=parser-%) test TRACE=$(TRACE) DEBUG=$(DEBUG)

clean::
	$(MAKE) -C parser-1.2 clean
	$(MAKE) -C parser-1.3 clean

node_modules:
	git branch --track $@ origin/$@ 2>/dev/null || true
	git worktree add -f $@ $@
