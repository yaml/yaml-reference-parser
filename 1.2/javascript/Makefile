ROOT := $(shell cd ..; pwd)
PARSER_LANG := javascript
BIN := node
GRAMMAR :=

ALL_JS := \
    bin/yaml-parser \
    lib/grammar.js \
    lib/parser.js \
    lib/prelude.js \
    lib/receiver.js \
    lib/test-receiver.js \
    test/testml-bridge.js \

BUILD_DEPS := \
    $(ROOT)/node_modules \
    build-coffee \
    $(ALL_JS) \
    $(ROOT)/test/testml/src/node/lib \


include $(ROOT)/.common.mk


build-coffee:
	$(MAKE) -C $(ROOT)/coffeescript build

bin/%: $(ROOT)/coffeescript/bin/%
	echo '#!/usr/bin/env node' > $@
	coffee -cp $< >> $@
	chmod +x $@

lib/%.js: $(ROOT)/coffeescript/lib/%.coffee
	coffee -cp $< > $@

test/%.js: $(ROOT)/coffeescript/test/%.coffee
	coffee -cp $< > $@
	perl -pi -e 's{/coffee/}{/node/}' $@

$(ROOT)/test/testml/src/node/lib: $(ROOT)/test/testml
	$(MAKE) -C $(@:%/lib=%) js-files
