ROOT := $(shell cd ..; pwd)
LANG := coffeescript
BIN := coffee
GRAMMAR := lib/grammar.coffee

BUILD_DEPS := \
    $(ROOT)/node_modules \

TEST_DEPS := \
    ../test/testml \

export TESTML_RUN := coffee-tap
export TESTML_LIB := $(ROOT)/test/suite/test:$(TESTML_LIB)

include ../.common.mk
