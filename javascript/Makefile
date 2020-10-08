ROOT := $(shell cd ..; pwd)
LANG := javascript
BIN := node
GRAMMAR :=

ALL_JS := \
    bin/yaml-parser \
    lib/debug-parser.js \
    lib/grammar.js \
    lib/parser.js \
    lib/prelude.js \
    lib/test-receiver.js \
    test/testml-bridge.js \

BUILD_DEPS := \
    build-coffee \
    $(ALL_JS) \

TEST_DEPS := \
    ../test/testml \


include $(ROOT)/.common.mk


build:: ../test/testml/src/node/lib

build-coffee:
	make -C ../coffeescript build

bin/%: ../coffeescript/bin/%
	echo '#!/usr/bin/env node' > $@
	coffee -cp $< >> $@
	chmod +x $@

lib/%.js: ../coffeescript/lib/%.coffee
	coffee -cp $< > $@

test/%.js: ../coffeescript/test/%.coffee
	coffee -cp $< > $@
	perl -pi -e 's{/coffee/}{/node/}' $@

../test/testml/src/node/lib: ../test/testml
	make -C $(@:%/lib=%) js-files

../test/testml:
	git clone https://github.com/testml-lang/testml $@
	make -C $@ ext/perl
	make -C $@ src/node_modules

../test/testml/src/node/lib:
	make -C ../test/testml src/node/lib
