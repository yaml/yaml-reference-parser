ROOT := $(shell cd ../..; pwd)
BASE := $(ROOT)/loader/coffeescript
PARSER_LANG := coffeescript
BIN := coffee
GRAMMAR :=

export NODE_PATH := $(ROOT)/parser-1.3/coffeescript/lib:$(BASE)/lib

# include $(ROOT)/.common.mk

test := test/pass.t

test::
	coffee test.coffee
